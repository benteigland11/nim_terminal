## Input event → VT/xterm byte encoder.
##
## Translates high-level input events (keyboard, mouse) into the byte
## sequences terminal applications expect on stdin.
##
## Supports:
##   * Full keyboard encoding (arrows, F-keys, modifiers)
##   * Mouse tracking: X11 (CSI M) and SGR (CSI <) protocols
##   * Bracketed paste (CSI 200~ / 201~)

import input_types

export input_types

type
  MouseMode* = enum
    mmNone        ## Mouse tracking disabled
    mmX11         ## Legacy X10/X11 tracking (CSI M b x y)
    mmSgr         ## SGR tracking (CSI < b ; x ; y M/m)

  InputMode* = object
    ## Flags that alter byte-level encoding.
    cursorApp*: bool      ## DECCKM (Application Cursor Keys)
    keypadApp*: bool      ## DECKPAM (Application Keypad)
    mouseMode*: MouseMode ## Active mouse protocol
    bracketedPaste*: bool ## \e[?2004h (Bracketed Paste Mode)
    focusReporting*: bool ## \e[?1004h (Focus Reporting Mode)

func newInputMode*(): InputMode = InputMode(mouseMode: mmNone)

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
  if x < 0: x = 0 # sanity
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
  var m = 0
  if modShift in mods: m = m or 1
  if modAlt in mods:   m = m or 2
  if modCtrl in mods:  m = m or 4
  if modSuper in mods: m = m or 8
  if m == 0: 0 else: m + 1

# ---------------------------------------------------------------------------
# Keyboard Encoders
# ---------------------------------------------------------------------------

func encodeCharInto(buf: var seq[byte], rune: uint32, mods: set[Modifier]) =
  var r = rune
  if modCtrl in mods:
    if r >= uint32('a') and r <= uint32('z'): r = r - uint32('a') + 1
    elif r >= uint32('A') and r <= uint32('Z'): r = r - uint32('A') + 1
    elif r == uint32(' ') or r == uint32('@'): r = 0
    elif r >= uint32('[') and r <= uint32('_'): r = r - uint32('@')
    elif r == uint32('?'): r = uint32(Del)
  if modAlt in mods: buf.add Esc
  appendUtf8(buf, r)

func encodeCursorInto(buf: var seq[byte], final: byte, mods: set[Modifier], cursorApp: bool) =
  let p = modParam(mods)
  if p > 0:
    buf.add Esc; buf.add byte('['); buf.add byte('1'); buf.add byte(';'); appendInt(buf, p); buf.add final
  elif cursorApp:
    buf.add Esc; buf.add byte('O'); buf.add final
  else:
    buf.add Esc; buf.add byte('['); buf.add final

func encodeTildeInto(buf: var seq[byte], code: int, mods: set[Modifier]) =
  buf.add Esc; buf.add byte('[')
  appendInt(buf, code)
  let p = modParam(mods)
  if p > 0: buf.add byte(';'); appendInt(buf, p)
  buf.add byte('~')

func encodeSs3Into(buf: var seq[byte], final: byte, mods: set[Modifier]) =
  let p = modParam(mods)
  if p > 0:
    buf.add Esc; buf.add byte('['); buf.add byte('1'); buf.add byte(';'); appendInt(buf, p); buf.add final
  else:
    buf.add Esc; buf.add byte('O'); buf.add final

# ---------------------------------------------------------------------------
# Mouse Encoders
# ---------------------------------------------------------------------------

func mouseBtnParam(ev: MouseEvent): int =
  ## Encode button + modifiers into the 0..255 parameter byte.
  var b = 0
  case ev.button
  of mbLeft:      b = 0
  of mbMiddle:    b = 1
  of mbRight:     b = 2
  of mbRelease:   b = 3
  of mbWheelUp:   b = 64
  of mbWheelDown: b = 65
  of mbExtra1:    b = 66
  of mbExtra2:    b = 67
  
  if ev.kind == meMove or ev.kind == meDrag:
    b = b or 32
    
  if modShift in ev.mods: b = b or 4
  if modAlt in ev.mods:   b = b or 8
  if modCtrl in ev.mods:  b = b or 16
  b

func encodeMouseInto(buf: var seq[byte], ev: MouseEvent, mode: MouseMode) =
  case mode
  of mmNone: discard
  of mmX11:
    # CSI M <btn+32> <x+32> <y+32>
    # Note: Limited to 223 columns/rows.
    buf.add Esc; buf.add byte('['); buf.add byte('M')
    buf.add byte(mouseBtnParam(ev) + 32)
    buf.add byte(max(1, min(223, ev.col + 1)) + 32)
    buf.add byte(max(1, min(223, ev.row + 1)) + 32)
  of mmSgr:
    # CSI < <btn> ; <x> ; <y> M (press) / m (release)
    buf.add Esc; buf.add byte('['); buf.add byte('<')
    appendInt(buf, mouseBtnParam(ev))
    buf.add byte(';')
    appendInt(buf, ev.col + 1)
    buf.add byte(';')
    appendInt(buf, ev.row + 1)
    buf.add(if ev.kind == meRelease or ev.button == mbRelease: byte('m') else: byte('M'))

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc encodeKeyEvent*(ev: KeyEvent, mode: InputMode = newInputMode()): seq[byte] =
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
      result.add Esc; result.add byte('['); result.add byte('Z')
    else:
      if modAlt in ev.mods: result.add Esc
      result.add Ht
  of kBackspace:
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
    if mode.keypadApp: result.add Esc; result.add byte('O'); result.add byte('M')
    else: (if modAlt in ev.mods: result.add Esc); result.add Cr

proc encodeMouseEvent*(ev: MouseEvent, mode: InputMode = newInputMode()): seq[byte] =
  result = @[]
  if mode.mouseMode == mmNone: return
  encodeMouseInto(result, ev, mode.mouseMode)

proc encodePaste*(s: string, mode: InputMode = newInputMode()): seq[byte] =
  result = @[]
  if mode.bracketedPaste:
    result.add Esc; result.add byte('['); result.add byte('2'); result.add byte('0'); result.add byte('0'); result.add byte('~')
  for ch in s: result.add byte(ch)
  if mode.bracketedPaste:
    result.add Esc; result.add byte('['); result.add byte('2'); result.add byte('0'); result.add byte('1'); result.add byte('~')

func shouldIntercept*(mode: InputMode, mods: set[Modifier] = {}): bool =
  ## Decide if a mouse click should be handled by the terminal UI (True)
  ## or sent to the child process (False).
  ##
  ## Logic:
  ##   * If Shift is held, ALWAYS intercept (user override).
  ##   * If mouse tracking is disabled, intercept.
  ##   * Otherwise, pass to child.
  if modShift in mods: return true
  if mode.mouseMode == mmNone: return true
  false
