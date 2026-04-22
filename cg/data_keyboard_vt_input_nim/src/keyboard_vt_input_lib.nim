## Keyboard event → VT/xterm input byte encoder.
##
## Pure translation layer: a GUI (or any input source) supplies a
## `KeyEvent` — a platform-independent description of a keystroke — and
## this widget produces the exact byte sequence a terminal application
## expects on its stdin.
##
## Coverage is the xterm-common subset:
##   * Printable characters (UTF-8, with Ctrl/Alt transforms)
##   * Navigation keys (arrows, Home/End/PgUp/PgDn/Insert/Delete)
##   * Function keys F1–F12
##   * Enter / Tab (with Shift-Tab as CSI Z) / Backspace / Escape
##   * Keypad-Enter respecting DECKPAM
##
## Two terminal modes change the encoding:
##
##   * `cursorApp`  — DECCKM. Arrow/Home/End use `ESC O x` instead of
##                    `ESC [ x`.
##   * `keypadApp`  — DECKPAM. Keypad keys use SS3 forms.
##
## Modifier-encoded sequences (xterm `modifyOtherKeys`, kitty keyboard
## protocol) are deliberately *not* emitted here. They add ambiguity
## without improving compatibility with the apps this widget targets
## first (vim, tmux, htop). Extension is easy when needed.

type
  KeyCode* = enum
    ## Symbolic key identifier. Printable keys use `kChar`; everything
    ## else gets its own kind so the encoder can look up the right
    ## sequence without character-level decisions.
    kNone
    kChar
    kEnter
    kTab
    kBackspace
    kEscape
    kInsert
    kDelete
    kHome
    kEnd
    kPageUp
    kPageDown
    kArrowUp
    kArrowDown
    kArrowLeft
    kArrowRight
    kF1, kF2, kF3, kF4, kF5, kF6, kF7, kF8, kF9, kF10, kF11, kF12
    kKeypadEnter

  Modifier* = enum
    modShift
    modAlt
    modCtrl
    modSuper

  KeyEvent* = object
    code*: KeyCode
    rune*: uint32          ## Unicode codepoint; meaningful only for `kChar`
    mods*: set[Modifier]

  KeyboardMode* = object
    ## DEC mode flags that alter byte-level encoding. Callers flip these
    ## in response to DECSET 1 (DECCKM) and DECKPAM.
    cursorApp*: bool
    keypadApp*: bool

func newKeyboardMode*(): KeyboardMode = KeyboardMode()

func keyChar*(rune: uint32, mods: set[Modifier] = {}): KeyEvent =
  ## Convenience constructor for a printable character event.
  KeyEvent(code: kChar, rune: rune, mods: mods)

func key*(code: KeyCode, mods: set[Modifier] = {}): KeyEvent =
  ## Convenience constructor for a non-character key event.
  KeyEvent(code: code, mods: mods)

# ---------------------------------------------------------------------------
# Low-level byte helpers
# ---------------------------------------------------------------------------

const
  Esc* = 0x1B'u8
  Del* = 0x7F'u8
  Cr*  = 0x0D'u8
  Ht*  = 0x09'u8

func appendInt(buf: var seq[byte], n: int) =
  if n == 0:
    buf.add byte('0')
    return
  var s: array[10, byte]
  var i = 0
  var x = n
  while x > 0:
    s[i] = byte('0') + byte(x mod 10)
    x = x div 10
    inc i
  for j in countdown(i - 1, 0):
    buf.add s[j]

func appendUtf8(buf: var seq[byte], cp: uint32) =
  var c = cp
  if c > 0x10FFFF'u32: c = 0xFFFD'u32
  if c < 0x80'u32:
    buf.add byte(c)
  elif c < 0x800'u32:
    buf.add byte(0xC0'u32 or (c shr 6))
    buf.add byte(0x80'u32 or (c and 0x3F'u32))
  elif c < 0x10000'u32:
    buf.add byte(0xE0'u32 or (c shr 12))
    buf.add byte(0x80'u32 or ((c shr 6) and 0x3F'u32))
    buf.add byte(0x80'u32 or (c and 0x3F'u32))
  else:
    buf.add byte(0xF0'u32 or (c shr 18))
    buf.add byte(0x80'u32 or ((c shr 12) and 0x3F'u32))
    buf.add byte(0x80'u32 or ((c shr 6) and 0x3F'u32))
    buf.add byte(0x80'u32 or (c and 0x3F'u32))

func modParam(mods: set[Modifier]): int =
  ## xterm modifier parameter: 1 + bitmask (shift=1, alt=2, ctrl=4, meta=8).
  ## Returns 0 when no modifier is present, meaning "omit the parameter".
  var m = 0
  if modShift in mods: m = m or 1
  if modAlt in mods:   m = m or 2
  if modCtrl in mods:  m = m or 4
  if modSuper in mods: m = m or 8
  if m == 0: 0 else: m + 1

# ---------------------------------------------------------------------------
# Encoders by key family
# ---------------------------------------------------------------------------

func encodeCharInto(buf: var seq[byte], rune: uint32, mods: set[Modifier]) =
  var r = rune
  if modCtrl in mods:
    # Map Ctrl+letter and Ctrl+symbol to the traditional C0 range.
    # Ctrl+a..z → 0x01..0x1A ; Ctrl+@..] → 0x00..0x1D ; Ctrl+? → DEL.
    if r >= uint32('a') and r <= uint32('z'):
      r = r - uint32('a') + 1
    elif r >= uint32('A') and r <= uint32('Z'):
      r = r - uint32('A') + 1
    elif r == uint32(' ') or r == uint32('@'):
      r = 0
    elif r >= uint32('[') and r <= uint32('_'):
      r = r - uint32('@')
    elif r == uint32('?'):
      r = uint32(Del)
  if modAlt in mods:
    buf.add Esc
  appendUtf8(buf, r)

func encodeCursorInto(buf: var seq[byte], final: byte,
                      mods: set[Modifier], cursorApp: bool) =
  let p = modParam(mods)
  if p > 0:
    # Modified cursor keys always use CSI 1 ; p final, even in
    # application-cursor mode — applications rely on this.
    buf.add Esc; buf.add byte('[')
    buf.add byte('1'); buf.add byte(';')
    appendInt(buf, p)
    buf.add final
  elif cursorApp:
    buf.add Esc; buf.add byte('O'); buf.add final
  else:
    buf.add Esc; buf.add byte('['); buf.add final

func encodeTildeInto(buf: var seq[byte], code: int, mods: set[Modifier]) =
  buf.add Esc; buf.add byte('[')
  appendInt(buf, code)
  let p = modParam(mods)
  if p > 0:
    buf.add byte(';'); appendInt(buf, p)
  buf.add byte('~')

func encodeSs3Into(buf: var seq[byte], final: byte, mods: set[Modifier]) =
  ## F1–F4. Unmodified uses SS3 (ESC O x); modified falls back to
  ## CSI 1 ; p x (what xterm emits, what vim expects).
  let p = modParam(mods)
  if p > 0:
    buf.add Esc; buf.add byte('[')
    buf.add byte('1'); buf.add byte(';')
    appendInt(buf, p)
    buf.add final
  else:
    buf.add Esc; buf.add byte('O'); buf.add final

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc encode*(ev: KeyEvent, mode: KeyboardMode = KeyboardMode()): seq[byte] =
  ## Translate a single `KeyEvent` into pty input bytes. Empty seq for
  ## `kNone` or a zero-rune `kChar`. Never raises.
  result = @[]
  case ev.code
  of kNone: return
  of kChar:
    if ev.rune == 0: return
    encodeCharInto(result, ev.rune, ev.mods)
  of kEnter:
    if modAlt in ev.mods: result.add Esc
    result.add Cr
  of kTab:
    if modShift in ev.mods:
      # Shift-Tab = CSI Z (reverse tab). Other modifiers ignored to
      # match xterm, which does not decorate Z with a modparam.
      result.add Esc; result.add byte('['); result.add byte('Z')
    else:
      if modAlt in ev.mods: result.add Esc
      result.add Ht
  of kBackspace:
    # xterm default: emit DEL (0x7F). Readline/vim both expect this.
    if modAlt in ev.mods: result.add Esc
    result.add Del
  of kEscape:
    if modAlt in ev.mods: result.add Esc
    result.add Esc
  of kArrowUp:    encodeCursorInto(result, byte('A'), ev.mods, mode.cursorApp)
  of kArrowDown:  encodeCursorInto(result, byte('B'), ev.mods, mode.cursorApp)
  of kArrowRight: encodeCursorInto(result, byte('C'), ev.mods, mode.cursorApp)
  of kArrowLeft:  encodeCursorInto(result, byte('D'), ev.mods, mode.cursorApp)
  of kHome:       encodeCursorInto(result, byte('H'), ev.mods, mode.cursorApp)
  of kEnd:        encodeCursorInto(result, byte('F'), ev.mods, mode.cursorApp)
  of kInsert:     encodeTildeInto(result, 2, ev.mods)
  of kDelete:     encodeTildeInto(result, 3, ev.mods)
  of kPageUp:     encodeTildeInto(result, 5, ev.mods)
  of kPageDown:   encodeTildeInto(result, 6, ev.mods)
  of kF1:         encodeSs3Into(result, byte('P'), ev.mods)
  of kF2:         encodeSs3Into(result, byte('Q'), ev.mods)
  of kF3:         encodeSs3Into(result, byte('R'), ev.mods)
  of kF4:         encodeSs3Into(result, byte('S'), ev.mods)
  of kF5:         encodeTildeInto(result, 15, ev.mods)
  of kF6:         encodeTildeInto(result, 17, ev.mods)
  of kF7:         encodeTildeInto(result, 18, ev.mods)
  of kF8:         encodeTildeInto(result, 19, ev.mods)
  of kF9:         encodeTildeInto(result, 20, ev.mods)
  of kF10:        encodeTildeInto(result, 21, ev.mods)
  of kF11:        encodeTildeInto(result, 23, ev.mods)
  of kF12:        encodeTildeInto(result, 24, ev.mods)
  of kKeypadEnter:
    if mode.keypadApp:
      result.add Esc; result.add byte('O'); result.add byte('M')
    else:
      if modAlt in ev.mods: result.add Esc
      result.add Cr

proc encodeString*(s: string): seq[byte] =
  ## Convenience: encode a UTF-8 string as bare bytes. Useful for paste
  ## paths where per-keystroke modifier handling is not relevant.
  result = newSeq[byte](s.len)
  for i, ch in s:
    result[i] = byte(ch)
