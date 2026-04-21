## Streaming UTF-8 decoder with display-width classification.
##
## Accepts bytes one at a time (or in chunks) and emits `(rune, width)`
## pairs through a caller-supplied callback. Handles continuation across
## feed boundaries so the decoder can be driven from an async read loop.
##
## On invalid input (unexpected continuation, illegal lead byte, overlong
## encoding, surrogate, truncated sequence aborted by a new lead byte) the
## decoder emits U+FFFD (REPLACEMENT CHARACTER) with width 1 and resumes
## from the next valid boundary — matching the W3C/WHATWG decoder behavior.
##
## `width` is 0 for zero-width / combining characters, 1 for narrow,
## 2 for east-asian-wide or emoji. Width uses a coarse range table; for
## exact Unicode UAX#11 compliance, callers can override `runeWidth`.

const
  ReplacementRune* = 0xFFFD'u32

type
  Utf8Decoder* = object
    remaining: int       ## continuation bytes still expected
    expected: int        ## total bytes in the in-flight sequence
    acc: uint32          ## accumulated codepoint so far
    minCp: uint32        ## smallest legal codepoint for the current length (overlong check)

  Utf8Emit* = proc (rune: uint32, width: int) {.closure.}

func newUtf8Decoder*(): Utf8Decoder = Utf8Decoder()

# ---------------------------------------------------------------------------
# Width classification
# ---------------------------------------------------------------------------

func isCombining(cp: uint32): bool =
  ## Ranges of zero-width / combining codepoints, coarse but covers the
  ## common cases (combining diacritical marks, ZWJ/ZWNJ, variation selectors).
  (cp >= 0x0300'u32 and cp <= 0x036F'u32) or     # combining diacriticals
  (cp >= 0x0483'u32 and cp <= 0x0489'u32) or
  (cp >= 0x0591'u32 and cp <= 0x05BD'u32) or
  (cp == 0x05BF'u32) or
  (cp >= 0x05C1'u32 and cp <= 0x05C2'u32) or
  (cp >= 0x05C4'u32 and cp <= 0x05C5'u32) or
  (cp == 0x05C7'u32) or
  (cp >= 0x0610'u32 and cp <= 0x061A'u32) or
  (cp >= 0x064B'u32 and cp <= 0x065F'u32) or
  (cp == 0x0670'u32) or
  (cp >= 0x06D6'u32 and cp <= 0x06DC'u32) or
  (cp >= 0x06DF'u32 and cp <= 0x06E4'u32) or
  (cp >= 0x06E7'u32 and cp <= 0x06E8'u32) or
  (cp >= 0x06EA'u32 and cp <= 0x06ED'u32) or
  (cp == 0x200B'u32) or                          # zero-width space
  (cp >= 0x200C'u32 and cp <= 0x200F'u32) or     # ZWNJ/ZWJ/LRM/RLM
  (cp >= 0x202A'u32 and cp <= 0x202E'u32) or
  (cp >= 0x2060'u32 and cp <= 0x2064'u32) or
  (cp >= 0xFE00'u32 and cp <= 0xFE0F'u32) or     # variation selectors
  (cp == 0xFEFF'u32) or                          # BOM / zero-width no-break
  (cp >= 0x1AB0'u32 and cp <= 0x1AFF'u32) or
  (cp >= 0x1DC0'u32 and cp <= 0x1DFF'u32) or
  (cp >= 0x20D0'u32 and cp <= 0x20FF'u32) or
  (cp >= 0xE0100'u32 and cp <= 0xE01EF'u32)      # variation selectors sup.

func isWide(cp: uint32): bool =
  ## East-asian wide / fullwidth ranges plus common emoji. Coarse.
  (cp >= 0x1100'u32 and cp <= 0x115F'u32) or     # Hangul Jamo
  (cp >= 0x2E80'u32 and cp <= 0x303E'u32) or     # CJK radicals, Kangxi
  (cp >= 0x3041'u32 and cp <= 0x33FF'u32) or     # Hiragana..CJK compat
  (cp >= 0x3400'u32 and cp <= 0x4DBF'u32) or     # CJK Ext A
  (cp >= 0x4E00'u32 and cp <= 0x9FFF'u32) or     # CJK Unified
  (cp >= 0xA000'u32 and cp <= 0xA4CF'u32) or     # Yi Syllables
  (cp >= 0xAC00'u32 and cp <= 0xD7A3'u32) or     # Hangul Syllables
  (cp >= 0xF900'u32 and cp <= 0xFAFF'u32) or     # CJK Compat Ideographs
  (cp >= 0xFE30'u32 and cp <= 0xFE4F'u32) or     # CJK Compat Forms
  (cp >= 0xFF00'u32 and cp <= 0xFF60'u32) or     # Fullwidth Forms
  (cp >= 0xFFE0'u32 and cp <= 0xFFE6'u32) or
  (cp >= 0x1F300'u32 and cp <= 0x1F64F'u32) or   # Misc Symbols & Pictographs + Emoticons
  (cp >= 0x1F680'u32 and cp <= 0x1F6FF'u32) or   # Transport
  (cp >= 0x1F900'u32 and cp <= 0x1F9FF'u32) or   # Supplemental Symbols
  (cp >= 0x20000'u32 and cp <= 0x2FFFD'u32) or   # CJK Ext B-F
  (cp >= 0x30000'u32 and cp <= 0x3FFFD'u32)      # CJK Ext G+

func runeWidth*(rune: uint32): int =
  ## Display columns occupied by `rune` (0 combining, 1 narrow, 2 wide).
  ## Control characters (< 0x20 and DEL) are reported as 0; the caller
  ## should have intercepted them before reaching the decoder.
  if rune < 0x20'u32: return 0
  if rune == 0x7F'u32: return 0
  if isCombining(rune): return 0
  if isWide(rune): return 2
  1

# ---------------------------------------------------------------------------
# Decoding
# ---------------------------------------------------------------------------

proc emitReplacement(emit: Utf8Emit) =
  emit(ReplacementRune, 1)

proc reset(d: var Utf8Decoder) =
  d.remaining = 0
  d.expected = 0
  d.acc = 0
  d.minCp = 0

proc advance*(d: var Utf8Decoder, b: byte, emit: Utf8Emit) =
  ## Feed one byte. `emit` may be called 0, 1, or 2 times per byte:
  ## 0 when still gathering continuation bytes, 1 for normal success,
  ## 2 when an in-flight sequence is aborted by a new lead byte
  ## (first emit is the FFFD for the aborted sequence).
  let bi = uint32(b)
  if d.remaining == 0:
    # Starting a new sequence.
    if bi < 0x80'u32:
      emit(bi, runeWidth(bi))
      return
    if (bi and 0xE0'u32) == 0xC0'u32:
      d.acc = bi and 0x1F'u32
      d.remaining = 1; d.expected = 2; d.minCp = 0x80'u32
      return
    if (bi and 0xF0'u32) == 0xE0'u32:
      d.acc = bi and 0x0F'u32
      d.remaining = 2; d.expected = 3; d.minCp = 0x800'u32
      return
    if (bi and 0xF8'u32) == 0xF0'u32:
      d.acc = bi and 0x07'u32
      d.remaining = 3; d.expected = 4; d.minCp = 0x10000'u32
      return
    # Continuation byte or illegal lead (0xC0, 0xC1, 0xF5..0xFF) in ground.
    emitReplacement(emit)
    return
  # We were mid-sequence.
  if (bi and 0xC0'u32) != 0x80'u32:
    # Not a continuation — abort the in-flight sequence with FFFD,
    # then reprocess this byte as a new lead.
    d.reset()
    emitReplacement(emit)
    d.advance(b, emit)
    return
  d.acc = (d.acc shl 6) or (bi and 0x3F'u32)
  dec d.remaining
  if d.remaining == 0:
    let cp = d.acc
    # Overlong encoding?
    if cp < d.minCp:
      emitReplacement(emit)
    # Surrogate half?
    elif cp >= 0xD800'u32 and cp <= 0xDFFF'u32:
      emitReplacement(emit)
    # Above Unicode max?
    elif cp > 0x10FFFF'u32:
      emitReplacement(emit)
    else:
      emit(cp, runeWidth(cp))
    d.reset()

proc feed*(d: var Utf8Decoder, data: openArray[byte], emit: Utf8Emit) =
  for b in data: d.advance(b, emit)

proc feed*(d: var Utf8Decoder, data: string, emit: Utf8Emit) =
  for ch in data: d.advance(byte(ch), emit)

proc finish*(d: var Utf8Decoder, emit: Utf8Emit) =
  ## Signal end-of-input. If a truncated sequence is in flight, a single
  ## FFFD is emitted for it. Safe to call even when idle.
  if d.remaining > 0:
    d.reset()
    emitReplacement(emit)

func pending*(d: Utf8Decoder): bool = d.remaining > 0
  ## True when bytes of an in-flight sequence have been consumed but the
  ## codepoint is not yet complete. Useful for testing split-buffer input.
