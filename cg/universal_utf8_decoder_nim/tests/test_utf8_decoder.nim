import std/unittest
import utf8_decoder_lib

type DecodedEvent = object
  rune: uint32
  width: int

proc runBytes(bytes: openArray[byte]): seq[DecodedEvent] =
  var d = newUtf8Decoder()
  var events: seq[DecodedEvent]
  let emit: Utf8Emit = proc (rune: uint32, width: int) =
    events.add DecodedEvent(rune: rune, width: width)
  d.feed(bytes, emit)
  events

proc runString(s: string): seq[DecodedEvent] =
  var bs = newSeq[byte](s.len)
  for i, c in s: bs[i] = byte(c)
  runBytes(bs)

suite "Well-formed input":
  test "ASCII passes through":
    let ev = runString("hello")
    check ev.len == 5
    check ev[0].rune == uint32('h') and ev[0].width == 1
    check ev[4].rune == uint32('o')

  test "two-byte sequence (é = U+00E9)":
    let ev = runBytes([0xC3'u8, 0xA9'u8])
    check ev.len == 1
    check ev[0].rune == 0x00E9'u32
    check ev[0].width == 1

  test "three-byte sequence (中 = U+4E2D, wide)":
    let ev = runBytes([0xE4'u8, 0xB8'u8, 0xAD'u8])
    check ev.len == 1
    check ev[0].rune == 0x4E2D'u32
    check ev[0].width == 2

  test "four-byte sequence (🚀 = U+1F680, wide)":
    let ev = runBytes([0xF0'u8, 0x9F'u8, 0x9A'u8, 0x80'u8])
    check ev.len == 1
    check ev[0].rune == 0x1F680'u32
    check ev[0].width == 2

  test "combining diacritic has width 0":
    # 'e' + U+0301 COMBINING ACUTE ACCENT (0xCC 0x81)
    let ev = runBytes([byte('e'), 0xCC'u8, 0x81'u8])
    check ev.len == 2
    check ev[0].rune == uint32('e') and ev[0].width == 1
    check ev[1].rune == 0x0301'u32 and ev[1].width == 0

suite "Split-buffer resumption":
  test "two-byte char split across feeds":
    var d = newUtf8Decoder()
    var seen: seq[uint32]
    let emit: Utf8Emit = proc (rune: uint32, width: int) = seen.add rune
    d.feed([0xC3'u8], emit)
    check seen.len == 0
    check d.pending
    d.feed([0xA9'u8], emit)
    check seen == @[0x00E9'u32]
    check not d.pending

  test "four-byte char split byte-by-byte":
    var d = newUtf8Decoder()
    var seen: seq[uint32]
    let emit: Utf8Emit = proc (rune: uint32, width: int) = seen.add rune
    for b in [0xF0'u8, 0x9F'u8, 0x9A'u8, 0x80'u8]:
      d.feed([b], emit)
    check seen == @[0x1F680'u32]

suite "Error handling":
  test "stray continuation byte emits FFFD":
    let ev = runBytes([0x80'u8])
    check ev.len == 1
    check ev[0].rune == 0xFFFD'u32
    check ev[0].width == 1

  test "overlong encoding of NUL is rejected":
    # Overlong NUL: 0xC0 0x80 (well-formed bit pattern, illegal per spec).
    let ev = runBytes([0xC0'u8, 0x80'u8])
    check ev.len == 1
    check ev[0].rune == 0xFFFD'u32

  test "surrogate codepoint is rejected":
    # U+D800 encoded as three bytes: 0xED 0xA0 0x80
    let ev = runBytes([0xED'u8, 0xA0'u8, 0x80'u8])
    check ev.len == 1
    check ev[0].rune == 0xFFFD'u32

  test "truncated sequence aborted by new lead byte emits FFFD + next char":
    # Start 2-byte (0xC3), then interrupt with ASCII 'a'.
    let ev = runBytes([0xC3'u8, byte('a')])
    check ev.len == 2
    check ev[0].rune == 0xFFFD'u32
    check ev[1].rune == uint32('a')

  test "finish() flushes a truncated in-flight sequence":
    var d = newUtf8Decoder()
    var seen: seq[uint32]
    let emit: Utf8Emit = proc (rune: uint32, width: int) = seen.add rune
    d.feed([0xC3'u8], emit)
    check seen.len == 0
    d.finish(emit)
    check seen == @[0xFFFD'u32]

  test "invalid lead (0xFF) emits FFFD":
    let ev = runBytes([0xFF'u8])
    check ev.len == 1
    check ev[0].rune == 0xFFFD'u32

suite "Width classification":
  test "narrow Latin-1 has width 1":
    check runeWidth(uint32('A')) == 1
    check runeWidth(0x00E9'u32) == 1

  test "wide CJK has width 2":
    check runeWidth(0x4E2D'u32) == 2
    check runeWidth(0xAC00'u32) == 2     # Hangul
    check runeWidth(0xFF21'u32) == 2     # fullwidth A

  test "emoji range has width 2":
    check runeWidth(0x1F600'u32) == 2    # 😀
    check runeWidth(0x1F680'u32) == 2    # 🚀

  test "combining has width 0":
    check runeWidth(0x0301'u32) == 0
    check runeWidth(0x200D'u32) == 0     # ZWJ

  test "C0 controls and DEL have width 0":
    check runeWidth(0x00'u32) == 0
    check runeWidth(0x1B'u32) == 0
    check runeWidth(0x7F'u32) == 0
