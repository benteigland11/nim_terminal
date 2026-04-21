## Terminal screen buffer.
##
## A grid of cells representing what the user sees on screen, plus the
## cursor, scroll region, alternate-screen buffer, and a fixed-size
## scrollback ring. This widget is pure logic: it exposes a set of
## operations (write a character, move the cursor, erase a region,
## scroll, set SGR attributes) and callers query it for rendering.
##
## The API is intentionally decoupled from any particular escape-sequence
## parser. Callers translate parsed events into calls on this module;
## the widget imposes no dependency on a specific VT parser.
##
## Coordinates are 0-indexed: row 0 is the topmost visible line, column 0
## is the leftmost column.

import std/options

const
  DefaultTabWidth* = 8
  DefaultScrollback* = 1000

# ---------------------------------------------------------------------------
# Attributes and colors
# ---------------------------------------------------------------------------

type
  ColorKind* = enum
    ckDefault
    ckIndexed
    ckRgb

  Color* = object
    case kind*: ColorKind
    of ckDefault:
      discard
    of ckIndexed:
      index*: uint8
    of ckRgb:
      r*, g*, b*: uint8

  AttrFlag* = enum
    afBold
    afDim
    afItalic
    afUnderline
    afBlink
    afInverse
    afHidden
    afStrike

  Attrs* = object
    flags*: set[AttrFlag]
    fg*: Color
    bg*: Color

func defaultAttrs*(): Attrs =
  Attrs(flags: {}, fg: Color(kind: ckDefault), bg: Color(kind: ckDefault))

func defaultColor*(): Color = Color(kind: ckDefault)
func indexed*(i: uint8): Color = Color(kind: ckIndexed, index: i)
func rgb*(r, g, b: uint8): Color = Color(kind: ckRgb, r: r, g: g, b: b)

# ---------------------------------------------------------------------------
# Cell
# ---------------------------------------------------------------------------

type
  Cell* = object
    ## `rune` is the Unicode codepoint shown. `width` is 1 for narrow cells,
    ## 2 for a double-wide leading half, 0 for a continuation cell (the slot
    ## occupied by the right half of a double-wide char).
    rune*: uint32
    width*: uint8
    attrs*: Attrs

func emptyCell*(attrs: Attrs = defaultAttrs()): Cell =
  Cell(rune: uint32(' '), width: 1, attrs: attrs)

func isContinuation*(c: Cell): bool = c.width == 0

# ---------------------------------------------------------------------------
# Cursor
# ---------------------------------------------------------------------------

type
  Cursor* = object
    row*: int
    col*: int
    attrs*: Attrs
    pendingWrap*: bool

func newCursor*(): Cursor =
  Cursor(row: 0, col: 0, attrs: defaultAttrs(), pendingWrap: false)

# ---------------------------------------------------------------------------
# Screen
# ---------------------------------------------------------------------------

type
  ScreenMode* = enum
    smAutoWrap        ## DECAWM (default on)
    smInsert          ## IRM
    smOrigin          ## DECOM
    smReverseVideo    ## DECSCNM

  Grid = seq[seq[Cell]]

  Screen* = ref object
    cols*, rows*: int
    grid: Grid
    altGrid: Grid
    cursor*: Cursor
    savedCursor: Option[Cursor]
    savedCursorAlt: Option[Cursor]
    scrollTop*, scrollBottom*: int
    tabStops: seq[bool]
    modes*: set[ScreenMode]
    scrollback: seq[seq[Cell]]
    scrollbackCap*: int
    usingAlt*: bool

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func makeRow(cols: int, attrs: Attrs): seq[Cell] =
  result = newSeq[Cell](cols)
  for i in 0 ..< cols:
    result[i] = emptyCell(attrs)

func makeGrid(cols, rows: int, attrs: Attrs): Grid =
  result = newSeq[seq[Cell]](rows)
  for r in 0 ..< rows:
    result[r] = makeRow(cols, attrs)

func makeTabStops(cols: int, stride: int): seq[bool] =
  result = newSeq[bool](cols)
  var i = stride
  while i < cols:
    result[i] = true
    i += stride

proc newScreen*(cols, rows: int, scrollback = DefaultScrollback): Screen =
  doAssert cols > 0 and rows > 0, "screen must have positive dimensions"
  let attrs = defaultAttrs()
  result = Screen(
    cols: cols, rows: rows,
    grid: makeGrid(cols, rows, attrs),
    altGrid: makeGrid(cols, rows, attrs),
    cursor: newCursor(),
    scrollTop: 0, scrollBottom: rows - 1,
    tabStops: makeTabStops(cols, DefaultTabWidth),
    modes: {smAutoWrap},
    scrollback: @[],
    scrollbackCap: scrollback,
    usingAlt: false,
  )

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func cellAt*(s: Screen, row, col: int): Cell =
  if row < 0 or row >= s.rows or col < 0 or col >= s.cols:
    return emptyCell()
  (if s.usingAlt: s.altGrid else: s.grid)[row][col]

func lineText*(s: Screen, row: int): string =
  ## Render one visible row as text (continuation halves skipped).
  if row < 0 or row >= s.rows: return ""
  let g = if s.usingAlt: s.altGrid else: s.grid
  result = newStringOfCap(s.cols)
  for c in g[row]:
    if c.isContinuation: continue
    let cp = c.rune
    if cp <= 0x7F:
      result.add char(cp)
    elif cp <= 0x7FF:
      result.add char(0xC0 or (cp shr 6))
      result.add char(0x80 or (cp and 0x3F))
    elif cp <= 0xFFFF:
      result.add char(0xE0 or (cp shr 12))
      result.add char(0x80 or ((cp shr 6) and 0x3F))
      result.add char(0x80 or (cp and 0x3F))
    else:
      result.add char(0xF0 or (cp shr 18))
      result.add char(0x80 or ((cp shr 12) and 0x3F))
      result.add char(0x80 or ((cp shr 6) and 0x3F))
      result.add char(0x80 or (cp and 0x3F))

func scrollbackLen*(s: Screen): int = s.scrollback.len

func scrollbackLine*(s: Screen, idx: int): seq[Cell] =
  ## Index 0 is the oldest line in scrollback.
  if idx < 0 or idx >= s.scrollback.len: return @[]
  s.scrollback[idx]

# ---------------------------------------------------------------------------
# Scrolling primitives
# ---------------------------------------------------------------------------

proc pushScrollback(s: Screen, line: seq[Cell]) =
  if s.usingAlt: return
  if s.scrollbackCap <= 0: return
  s.scrollback.add line
  if s.scrollback.len > s.scrollbackCap:
    let overflow = s.scrollback.len - s.scrollbackCap
    for _ in 0 ..< overflow:
      s.scrollback.delete(0)

proc scrollRegionUp(s: Screen, n: int) =
  if n <= 0: return
  let top = s.scrollTop
  let bot = s.scrollBottom
  let height = bot - top + 1
  let k = min(n, height)
  let fullScreenRegion = top == 0 and bot == s.rows - 1
  let blankAttrs = s.cursor.attrs
  if fullScreenRegion:
    for i in 0 ..< k:
      if s.usingAlt:
        s.pushScrollback(s.altGrid[top + i])
      else:
        s.pushScrollback(s.grid[top + i])
  if s.usingAlt:
    for i in 0 ..< (height - k):
      s.altGrid[top + i] = s.altGrid[top + i + k]
    for i in (height - k) ..< height:
      s.altGrid[top + i] = makeRow(s.cols, blankAttrs)
  else:
    for i in 0 ..< (height - k):
      s.grid[top + i] = s.grid[top + i + k]
    for i in (height - k) ..< height:
      s.grid[top + i] = makeRow(s.cols, blankAttrs)

proc scrollRegionDown(s: Screen, n: int) =
  if n <= 0: return
  let top = s.scrollTop
  let bot = s.scrollBottom
  let height = bot - top + 1
  let k = min(n, height)
  let blankAttrs = s.cursor.attrs
  if s.usingAlt:
    for i in countdown(height - 1, k):
      s.altGrid[top + i] = s.altGrid[top + i - k]
    for i in 0 ..< k:
      s.altGrid[top + i] = makeRow(s.cols, blankAttrs)
  else:
    for i in countdown(height - 1, k):
      s.grid[top + i] = s.grid[top + i - k]
    for i in 0 ..< k:
      s.grid[top + i] = makeRow(s.cols, blankAttrs)

template writeCell(s: Screen, r, c: int, cell: Cell) =
  if s.usingAlt: s.altGrid[r][c] = cell else: s.grid[r][c] = cell

template writeRow(s: Screen, r: int, row: seq[Cell]) =
  if s.usingAlt: s.altGrid[r] = row else: s.grid[r] = row

template readCell(s: Screen, r, c: int): Cell =
  (if s.usingAlt: s.altGrid[r][c] else: s.grid[r][c])

template readRow(s: Screen, r: int): seq[Cell] =
  (if s.usingAlt: s.altGrid[r] else: s.grid[r])

# ---------------------------------------------------------------------------
# Cursor movement
# ---------------------------------------------------------------------------

func clampCursor(s: Screen) =
  if s.cursor.row < 0: s.cursor.row = 0
  if s.cursor.row >= s.rows: s.cursor.row = s.rows - 1
  if s.cursor.col < 0: s.cursor.col = 0
  if s.cursor.col >= s.cols: s.cursor.col = s.cols - 1

func cursorTo*(s: Screen, row, col: int) =
  s.cursor.row = row
  s.cursor.col = col
  s.cursor.pendingWrap = false
  s.clampCursor()

func cursorUp*(s: Screen, n = 1) =
  s.cursor.row = max(s.scrollTop, s.cursor.row - max(1, n))
  s.cursor.pendingWrap = false

func cursorDown*(s: Screen, n = 1) =
  s.cursor.row = min(s.scrollBottom, s.cursor.row + max(1, n))
  s.cursor.pendingWrap = false

func cursorForward*(s: Screen, n = 1) =
  s.cursor.col = min(s.cols - 1, s.cursor.col + max(1, n))
  s.cursor.pendingWrap = false

func cursorBackward*(s: Screen, n = 1) =
  s.cursor.col = max(0, s.cursor.col - max(1, n))
  s.cursor.pendingWrap = false

func saveCursor*(s: Screen) =
  if s.usingAlt: s.savedCursorAlt = some(s.cursor)
  else:          s.savedCursor    = some(s.cursor)

func restoreCursor*(s: Screen) =
  let saved = if s.usingAlt: s.savedCursorAlt else: s.savedCursor
  if saved.isSome:
    s.cursor = saved.get
    s.clampCursor()

# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

proc linefeed*(s: Screen) =
  if s.cursor.row == s.scrollBottom:
    s.scrollRegionUp(1)
  elif s.cursor.row < s.rows - 1:
    inc s.cursor.row
  s.cursor.pendingWrap = false

proc carriageReturn*(s: Screen) =
  s.cursor.col = 0
  s.cursor.pendingWrap = false

proc backspace*(s: Screen) =
  if s.cursor.col > 0:
    dec s.cursor.col
  s.cursor.pendingWrap = false

proc tab*(s: Screen) =
  var c = s.cursor.col + 1
  while c < s.cols - 1 and not s.tabStops[c]:
    inc c
  if c >= s.cols: c = s.cols - 1
  s.cursor.col = c
  s.cursor.pendingWrap = false

proc writeRune*(s: Screen, rune: uint32, width: int = 1) =
  ## Place a codepoint at the cursor, advancing by `width` (1 or 2).
  let w = if width == 2: 2 else: 1
  if s.cursor.pendingWrap and smAutoWrap in s.modes:
    s.carriageReturn()
    s.linefeed()
  if w == 2 and s.cursor.col >= s.cols - 1:
    if smAutoWrap in s.modes:
      writeCell(s, s.cursor.row, s.cursor.col, emptyCell(s.cursor.attrs))
      s.carriageReturn()
      s.linefeed()
    else:
      s.cursor.col = s.cols - 2
  let row = s.cursor.row
  let col = s.cursor.col
  writeCell(s, row, col, Cell(rune: rune, width: uint8(w), attrs: s.cursor.attrs))
  if w == 2 and col + 1 < s.cols:
    writeCell(s, row, col + 1, Cell(rune: 0, width: 0, attrs: s.cursor.attrs))
  if s.cursor.col + w >= s.cols:
    s.cursor.col = s.cols - 1
    s.cursor.pendingWrap = smAutoWrap in s.modes
  else:
    s.cursor.col += w
    s.cursor.pendingWrap = false

proc writeChar*(s: Screen, ch: char) =
  s.writeRune(uint32(ch), 1)

proc writeString*(s: Screen, text: string) =
  for c in text:
    s.writeRune(uint32(c), 1)

# ---------------------------------------------------------------------------
# Erase / insert / delete
# ---------------------------------------------------------------------------

type
  EraseMode* = enum
    emToEnd
    emToStart
    emAll

proc eraseInLine*(s: Screen, mode: EraseMode) =
  let attrs = s.cursor.attrs
  let row = s.cursor.row
  case mode
  of emToEnd:
    for c in s.cursor.col ..< s.cols:
      writeCell(s, row, c, emptyCell(attrs))
  of emToStart:
    for c in 0 .. s.cursor.col:
      writeCell(s, row, c, emptyCell(attrs))
  of emAll:
    for c in 0 ..< s.cols:
      writeCell(s, row, c, emptyCell(attrs))

proc eraseInDisplay*(s: Screen, mode: EraseMode) =
  let attrs = s.cursor.attrs
  case mode
  of emToEnd:
    s.eraseInLine(emToEnd)
    for r in (s.cursor.row + 1) ..< s.rows:
      writeRow(s, r, makeRow(s.cols, attrs))
  of emToStart:
    for r in 0 ..< s.cursor.row:
      writeRow(s, r, makeRow(s.cols, attrs))
    s.eraseInLine(emToStart)
  of emAll:
    for r in 0 ..< s.rows:
      writeRow(s, r, makeRow(s.cols, attrs))

proc insertLines*(s: Screen, n: int) =
  if n <= 0: return
  if s.cursor.row < s.scrollTop or s.cursor.row > s.scrollBottom: return
  let top = s.cursor.row
  let bot = s.scrollBottom
  let height = bot - top + 1
  let k = min(n, height)
  let attrs = s.cursor.attrs
  for i in countdown(height - 1, k):
    writeRow(s, top + i, readRow(s, top + i - k))
  for i in 0 ..< k:
    writeRow(s, top + i, makeRow(s.cols, attrs))
  s.cursor.pendingWrap = false

proc deleteLines*(s: Screen, n: int) =
  if n <= 0: return
  if s.cursor.row < s.scrollTop or s.cursor.row > s.scrollBottom: return
  let top = s.cursor.row
  let bot = s.scrollBottom
  let height = bot - top + 1
  let k = min(n, height)
  let attrs = s.cursor.attrs
  for i in 0 ..< (height - k):
    writeRow(s, top + i, readRow(s, top + i + k))
  for i in (height - k) ..< height:
    writeRow(s, top + i, makeRow(s.cols, attrs))
  s.cursor.pendingWrap = false

proc insertChars*(s: Screen, n: int) =
  if n <= 0: return
  let row = s.cursor.row
  let col = s.cursor.col
  let attrs = s.cursor.attrs
  let k = min(n, s.cols - col)
  for i in countdown(s.cols - 1, col + k):
    writeCell(s, row, i, readCell(s, row, i - k))
  for i in col ..< col + k:
    writeCell(s, row, i, emptyCell(attrs))

proc deleteChars*(s: Screen, n: int) =
  if n <= 0: return
  let row = s.cursor.row
  let col = s.cursor.col
  let attrs = s.cursor.attrs
  let k = min(n, s.cols - col)
  for i in col ..< s.cols - k:
    writeCell(s, row, i, readCell(s, row, i + k))
  for i in s.cols - k ..< s.cols:
    writeCell(s, row, i, emptyCell(attrs))

# ---------------------------------------------------------------------------
# Scroll region and explicit scrolls
# ---------------------------------------------------------------------------

proc setScrollRegion*(s: Screen, top, bottom: int) =
  let t = max(0, top)
  let b = min(s.rows - 1, bottom)
  if t >= b: return
  s.scrollTop = t
  s.scrollBottom = b
  s.cursor.row = t
  s.cursor.col = 0
  s.cursor.pendingWrap = false

proc resetScrollRegion*(s: Screen) =
  s.scrollTop = 0
  s.scrollBottom = s.rows - 1

proc scrollUp*(s: Screen, n: int) = s.scrollRegionUp(n)
proc scrollDown*(s: Screen, n: int) = s.scrollRegionDown(n)

# ---------------------------------------------------------------------------
# Tab stops
# ---------------------------------------------------------------------------

func setTabStop*(s: Screen) =
  if s.cursor.col >= 0 and s.cursor.col < s.cols:
    s.tabStops[s.cursor.col] = true

func clearTabStop*(s: Screen) =
  if s.cursor.col >= 0 and s.cursor.col < s.cols:
    s.tabStops[s.cursor.col] = false

func clearAllTabStops*(s: Screen) =
  for i in 0 ..< s.tabStops.len: s.tabStops[i] = false

# ---------------------------------------------------------------------------
# Alternate screen and reset
# ---------------------------------------------------------------------------

proc useAlternateScreen*(s: Screen, on: bool) =
  if on == s.usingAlt: return
  s.usingAlt = on
  if on:
    for r in 0 ..< s.rows:
      s.altGrid[r] = makeRow(s.cols, s.cursor.attrs)

proc reset*(s: Screen) =
  s.cursor = newCursor()
  s.savedCursor = none(Cursor)
  s.savedCursorAlt = none(Cursor)
  s.scrollTop = 0
  s.scrollBottom = s.rows - 1
  s.tabStops = makeTabStops(s.cols, DefaultTabWidth)
  s.modes = {smAutoWrap}
  s.usingAlt = false
  s.scrollback.setLen(0)
  let attrs = defaultAttrs()
  for r in 0 ..< s.rows:
    s.grid[r] = makeRow(s.cols, attrs)
    s.altGrid[r] = makeRow(s.cols, attrs)

# ---------------------------------------------------------------------------
# Resize
# ---------------------------------------------------------------------------

proc resize*(s: Screen, cols, rows: int) =
  doAssert cols > 0 and rows > 0
  if cols == s.cols and rows == s.rows: return
  let attrs = s.cursor.attrs
  var newGrid = makeGrid(cols, rows, attrs)
  var newAlt  = makeGrid(cols, rows, attrs)
  let copyRows = min(rows, s.rows)
  let dropTop = if rows < s.rows: s.rows - rows else: 0
  for r in 0 ..< copyRows:
    let srcRow = dropTop + r
    let copyCols = min(cols, s.cols)
    for c in 0 ..< copyCols:
      newGrid[r][c] = s.grid[srcRow][c]
      newAlt[r][c] = s.altGrid[srcRow][c]
  if dropTop > 0:
    for r in 0 ..< dropTop:
      s.pushScrollback(s.grid[r])
  s.grid = newGrid
  s.altGrid = newAlt
  s.cols = cols
  s.rows = rows
  s.tabStops = makeTabStops(cols, DefaultTabWidth)
  s.scrollTop = 0
  s.scrollBottom = rows - 1
  s.clampCursor()
  s.cursor.pendingWrap = false

# ---------------------------------------------------------------------------
# SGR
# ---------------------------------------------------------------------------

type
  SgrParam* = object
    ## Minimal parameter shape for the SGR handler. Callers adapt their
    ## parser's param type into this; keeps the widget dependency-free.
    value*: int             ## -1 indicates a defaulted/missing parameter
    subParams*: seq[int]

func sgr*(value: int, subParams: seq[int] = @[]): SgrParam =
  SgrParam(value: value, subParams: subParams)

func basicFg(idx: int): Color = indexed(uint8(idx - 30))
func basicBg(idx: int): Color = indexed(uint8(idx - 40))
func brightFg(idx: int): Color = indexed(uint8(8 + idx - 90))
func brightBg(idx: int): Color = indexed(uint8(8 + idx - 100))

proc applyIndexedOr24bit(
    params: openArray[SgrParam],
    startIdx: int,
    onto: var Color,
): int =
  ## Handle a 38/48/58 extended-color selector. Returns how many additional
  ## top-level params were consumed (0 when colon-packed into the selector).
  let selector = params[startIdx]
  if selector.subParams.len > 0:
    let kind = selector.subParams[0]
    if kind == 5 and selector.subParams.len >= 2:
      let idx = selector.subParams[1]
      if idx >= 0 and idx <= 255:
        onto = indexed(uint8(idx))
    elif kind == 2 and selector.subParams.len >= 5:
      let r = max(0, min(255, selector.subParams[2]))
      let g = max(0, min(255, selector.subParams[3]))
      let b = max(0, min(255, selector.subParams[4]))
      onto = rgb(uint8(r), uint8(g), uint8(b))
    elif kind == 2 and selector.subParams.len >= 4:
      let r = max(0, min(255, selector.subParams[1]))
      let g = max(0, min(255, selector.subParams[2]))
      let b = max(0, min(255, selector.subParams[3]))
      onto = rgb(uint8(r), uint8(g), uint8(b))
    return 0
  if startIdx + 1 >= params.len: return 0
  let kind = params[startIdx + 1].value
  if kind == 5 and startIdx + 2 < params.len:
    let idx = params[startIdx + 2].value
    if idx >= 0 and idx <= 255:
      onto = indexed(uint8(idx))
    return 2
  if kind == 2 and startIdx + 4 < params.len:
    let r = max(0, min(255, params[startIdx + 2].value))
    let g = max(0, min(255, params[startIdx + 3].value))
    let b = max(0, min(255, params[startIdx + 4].value))
    onto = rgb(uint8(r), uint8(g), uint8(b))
    return 4
  0

proc applySgr*(s: Screen, params: openArray[SgrParam]) =
  ## ECMA-48 Select Graphic Rendition. An empty list or a single defaulted
  ## parameter resets the pen.
  if params.len == 0:
    s.cursor.attrs = defaultAttrs()
    return
  var i = 0
  while i < params.len:
    let p = params[i]
    let v = if p.value < 0: 0 else: p.value
    case v
    of 0:
      s.cursor.attrs = defaultAttrs()
    of 1:  s.cursor.attrs.flags.incl afBold
    of 2:  s.cursor.attrs.flags.incl afDim
    of 3:  s.cursor.attrs.flags.incl afItalic
    of 4:  s.cursor.attrs.flags.incl afUnderline
    of 5:  s.cursor.attrs.flags.incl afBlink
    of 7:  s.cursor.attrs.flags.incl afInverse
    of 8:  s.cursor.attrs.flags.incl afHidden
    of 9:  s.cursor.attrs.flags.incl afStrike
    of 22: s.cursor.attrs.flags.excl afBold; s.cursor.attrs.flags.excl afDim
    of 23: s.cursor.attrs.flags.excl afItalic
    of 24: s.cursor.attrs.flags.excl afUnderline
    of 25: s.cursor.attrs.flags.excl afBlink
    of 27: s.cursor.attrs.flags.excl afInverse
    of 28: s.cursor.attrs.flags.excl afHidden
    of 29: s.cursor.attrs.flags.excl afStrike
    of 30..37: s.cursor.attrs.fg = basicFg(v)
    of 38:
      let consumed = applyIndexedOr24bit(params, i, s.cursor.attrs.fg)
      i += consumed
    of 39: s.cursor.attrs.fg = defaultColor()
    of 40..47: s.cursor.attrs.bg = basicBg(v)
    of 48:
      let consumed = applyIndexedOr24bit(params, i, s.cursor.attrs.bg)
      i += consumed
    of 49: s.cursor.attrs.bg = defaultColor()
    of 90..97:  s.cursor.attrs.fg = brightFg(v)
    of 100..107: s.cursor.attrs.bg = brightBg(v)
    else: discard
    inc i
