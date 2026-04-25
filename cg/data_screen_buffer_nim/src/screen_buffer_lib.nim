## Terminal screen buffer.
##
## A grid of cells representing what the user sees on screen, plus the
## cursor, scroll region, alternate-screen buffer, and a fixed-size
## scrollback ring. This widget is pure logic: it exposes a set of
## procedures to mutate the buffer.

import std/[options, unicode]

const
  DefaultTabWidth* = 8
  DefaultScrollback* = 1000

# ---------------------------------------------------------------------------
# Types and Enums
# ---------------------------------------------------------------------------

type
  PaletteColor* = object
    r*, g*, b*: uint8

  TerminalTheme* = ref object
    background*: PaletteColor
    foreground*: PaletteColor
    cursor*: PaletteColor
    selection*: PaletteColor
    ansi*: array[16, PaletteColor]

  ColorKind* = enum
    ckDefault
    ckIndexed
    ckRgb

  Color* = object
    case kind*: ColorKind
    of ckDefault: discard
    of ckIndexed: index*: int
    of ckRgb:     r*, g*, b*: uint8

  AttrFlag* = enum
    afBold
    afItalic
    afUnderline
    afInverse
    afHidden

  Attrs* = object
    fg*, bg*: Color
    flags*: set[AttrFlag]

  Cell* = object
    rune*: uint32
    width*: uint8          ## 0 (continuation), 1 (normal), 2 (wide)
    attrs*: Attrs

  Cursor* = object
    row*, col*: int
    attrs*: Attrs
    visible*: bool
    pendingWrap*: bool     ## True if cursor is logically past end-of-line

  ScreenMode* = enum
    smAutoWrap
    smInsert

  EraseMode* = enum
    emToEnd
    emToStart
    emAll

  SgrParam* = object
    value*: int
    subParams*: seq[int]

  Screen* = ref object
    cols*, rows*: int
    grid: seq[seq[Cell]]
    altGrid: seq[seq[Cell]]
    cursor*: Cursor
    savedCursor: Option[Cursor]
    savedCursorAlt: Option[Cursor]
    scrollTop*, scrollBottom*: int
    tabStops: seq[bool]
    modes*: set[ScreenMode]
    scrollback*: seq[seq[Cell]]
    scrollbackCap*: int
    usingAlt*: bool
    title*: string
    iconName*: string
    theme*: TerminalTheme

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func rgb*(r, g, b: uint8): PaletteColor = PaletteColor(r: r, g: g, b: b)

func defaultTheme*(): TerminalTheme =
  TerminalTheme(
    background: rgb(0, 0, 0),
    foreground: rgb(229, 229, 229),
    cursor:     rgb(255, 255, 255),
    selection:  rgb(173, 214, 255),
    ansi: [
      rgb(0, 0, 0), rgb(205, 0, 0), rgb(0, 205, 0), rgb(205, 205, 0),
      rgb(0, 0, 238), rgb(205, 0, 205), rgb(0, 205, 205), rgb(229, 229, 229),
      rgb(127, 127, 127), rgb(255, 0, 0), rgb(0, 255, 0), rgb(255, 255, 255),
      rgb(92, 92, 255), rgb(255, 0, 255), rgb(0, 255, 255), rgb(255, 255, 255)
    ]
  )

func defaultColor*(): Color = Color(kind: ckDefault)
func indexedColor*(i: int): Color = Color(kind: ckIndexed, index: i)
func rgbColor*(r, g, b: uint8): Color = Color(kind: ckRgb, r: r, g: g, b: b)

func defaultAttrs*(): Attrs =
  Attrs(fg: defaultColor(), bg: defaultColor(), flags: {})

func emptyCell*(attrs: Attrs = defaultAttrs()): Cell =
  Cell(rune: uint32(' '), width: 1, attrs: attrs)

func isContinuation*(c: Cell): bool = c.width == 0

func makeRow(cols: int, attrs: Attrs = defaultAttrs()): seq[Cell] =
  result = newSeq[Cell](cols)
  for i in 0 ..< cols: result[i] = emptyCell(attrs)

func makeGrid(cols, rows: int, attrs: Attrs = defaultAttrs()): seq[seq[Cell]] =
  result = newSeq[seq[Cell]](rows)
  for i in 0 ..< rows: result[i] = makeRow(cols, attrs)

func makeTabStops(cols, width: int): seq[bool] =
  result = newSeq[bool](cols)
  for i in countup(width, cols - 1, width): result[i] = true

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func newCursor(): Cursor =
  Cursor(row: 0, col: 0, attrs: defaultAttrs(), visible: true, pendingWrap: false)

proc newScreen*(
    cols, rows: int,
    scrollback: int = DefaultScrollback
): Screen =
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
    title: "",
    iconName: "",
    theme: defaultTheme(),
  )

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func cellAt*(s: Screen, row, col: int): Cell =
  if row < 0 or row >= s.rows or col < 0 or col >= s.cols: return emptyCell()
  (if s.usingAlt: s.altGrid else: s.grid)[row][col]

func totalRows*(s: Screen): int =
  if s.usingAlt: s.rows else: s.scrollback.len + s.rows

func absoluteRowAt*(s: Screen, absRow: int): seq[Cell] =
  if absRow < 0: return @[]
  if s.usingAlt:
    if absRow >= s.rows: return @[]
    return s.altGrid[absRow]
  if absRow < s.scrollback.len: return s.scrollback[absRow]
  let gr = absRow - s.scrollback.len
  if gr >= s.rows: return @[]
  s.grid[gr]

func absoluteCellAt*(s: Screen, absRow, col: int): Cell =
  if col < 0 or col >= s.cols or absRow < 0: return emptyCell()
  if s.usingAlt:
    if absRow >= s.rows: return emptyCell()
    let row = s.altGrid[absRow]
    if col >= row.len: return emptyCell()
    return row[col]
  if absRow < s.scrollback.len:
    if col >= s.scrollback[absRow].len: return emptyCell()
    return s.scrollback[absRow][col]
  let gr = absRow - s.scrollback.len
  if gr >= s.rows: return emptyCell()
  let row = s.grid[gr]
  if col >= row.len: return emptyCell()
  row[col]

func lineText*(s: Screen, row: int): string =
  if row < 0 or row >= s.rows: return ""
  let g = if s.usingAlt: s.altGrid else: s.grid
  result = newStringOfCap(s.cols)
  for c in g[row]:
    if c.isContinuation: continue
    result.add Rune(c.rune)

func absoluteLineText*(s: Screen, absRow: int): string =
  let cells = s.absoluteRowAt(absRow)
  result = newStringOfCap(cells.len)
  for c in cells:
    if c.isContinuation: continue
    result.add Rune(c.rune)

func colOfByteIndex*(s: Screen, absRow: int, byteIdx: int): int =
  ## Maps a byte index from the UTF-8 string back to a grid column.
  let cells = s.absoluteRowAt(absRow)
  var currentByte = 0
  for col, c in cells:
    if c.isContinuation: continue
    if byteIdx <= currentByte: return col
    let r = Rune(c.rune)
    currentByte += ($r).len
    if byteIdx <= currentByte: return col + max(1, int(c.width))
  cells.len

# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------

proc setCell(s: Screen, row, col: int, cell: Cell) =
  if row < 0 or row >= s.rows or col < 0 or col >= s.cols: return
  if s.usingAlt:
    if col < s.altGrid[row].len: s.altGrid[row][col] = cell
  else:
    if col < s.grid[row].len: s.grid[row][col] = cell

proc clearRow(s: Screen, row: int, startCol, endCol: int, attrs: Attrs) =
  if row < 0 or row >= s.rows or s.cols <= 0: return
  let first = max(0, startCol)
  let last = min(s.cols - 1, endCol)
  if first > last: return
  for c in first .. last: s.setCell(row, c, emptyCell(attrs))

proc clearGrid(grid: var seq[seq[Cell]], startRow, endRow: int, cols: int, attrs: Attrs) =
  for r in startRow .. endRow:
    for c in 0 ..< cols: grid[r][c] = emptyCell(attrs)

proc scrollUp*(s: Screen, count: int = 1) =
  let n = min(count, s.scrollBottom - s.scrollTop + 1)
  if n <= 0: return
  let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  if not s.usingAlt and s.scrollTop == 0 and s.scrollBottom == s.rows - 1:
    for i in 0 ..< n:
      s.scrollback.add g[][i]
      if s.scrollback.len > s.scrollbackCap: s.scrollback.delete(0)
  for r in s.scrollTop .. (s.scrollBottom - n): g[][r] = g[][r + n]
  let attrs = defaultAttrs()
  for r in (s.scrollBottom - n + 1) .. s.scrollBottom: g[][r] = makeRow(s.cols, attrs)

proc scrollDown*(s: Screen, count: int = 1) =
  let n = min(count, s.scrollBottom - s.scrollTop + 1)
  if n <= 0: return
  let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  for r in countdown(s.scrollBottom, s.scrollTop + n): g[][r] = g[][r - n]
  let attrs = defaultAttrs()
  for r in s.scrollTop .. (s.scrollTop + n - 1): g[][r] = makeRow(s.cols, attrs)

proc useAlternateScreen*(s: Screen, active: bool) =
  if active == s.usingAlt: return
  s.usingAlt = active

proc reset*(s: Screen) =
  s.cursor = newCursor(); s.scrollTop = 0; s.scrollBottom = s.rows - 1
  s.tabStops = makeTabStops(s.cols, DefaultTabWidth); s.modes = {smAutoWrap}
  s.usingAlt = false; s.scrollback.setLen(0); s.title = ""; s.iconName = ""
  s.theme = defaultTheme(); let attrs = defaultAttrs()
  for r in 0 ..< s.rows: (s.grid[r] = makeRow(s.cols, attrs); s.altGrid[r] = makeRow(s.cols, attrs))

proc resize*(s: Screen, cols, rows: int) =
  if cols <= 0 or rows <= 0: return
  if cols == s.cols and rows == s.rows: return
  let oldRows = s.rows; let oldCols = s.cols; let attrs = defaultAttrs()
  if rows < oldRows and not s.usingAlt:
    let diff = oldRows - rows
    for i in 0 ..< diff:
      var row = s.grid[i]
      row.setLen(cols)
      for c in oldCols ..< cols: row[c] = emptyCell(attrs)
      s.scrollback.add row
      if s.scrollback.len > s.scrollbackCap: s.scrollback.delete(0)
    for i in 0 ..< rows: s.grid[i] = s.grid[i + diff]
    s.grid.setLen(rows); s.altGrid.setLen(rows)
    for r in 0 ..< rows:
      s.grid[r].setLen(cols)
      s.altGrid[r].setLen(cols)
      for c in oldCols ..< cols:
        s.grid[r][c] = emptyCell(attrs)
        s.altGrid[r][c] = emptyCell(attrs)
  else:
    s.grid.setLen(rows); s.altGrid.setLen(rows)
    for r in 0 ..< rows:
      if r < oldRows:
        s.grid[r].setLen(cols); s.altGrid[r].setLen(cols)
        for c in oldCols ..< cols: (s.grid[r][c] = emptyCell(attrs); s.altGrid[r][c] = emptyCell(attrs))
      else: (s.grid[r] = makeRow(cols, attrs); s.altGrid[r] = makeRow(cols, attrs))
  s.cols = cols; s.rows = rows; s.cursor.row = max(0, min(rows-1, s.cursor.row)); s.cursor.col = max(0, min(cols-1, s.cursor.col))
  s.scrollTop = 0; s.scrollBottom = rows - 1; s.tabStops = makeTabStops(cols, DefaultTabWidth)

proc cursorTo*(s: Screen, row, col: int) = (s.cursor.row = max(0, min(s.rows-1, row)); s.cursor.col = max(0, min(s.cols-1, col)); s.cursor.pendingWrap = false)
proc cursorUp*(s: Screen, count: int = 1) = (s.cursor.row = max(s.scrollTop, s.cursor.row - count); s.cursor.pendingWrap = false)
proc cursorDown*(s: Screen, count: int = 1) = (s.cursor.row = min(s.scrollBottom, s.cursor.row + count); s.cursor.pendingWrap = false)
proc cursorForward*(s: Screen, count: int = 1) = (s.cursor.col = min(s.cols - 1, s.cursor.col + count); s.cursor.pendingWrap = false)
proc cursorBackward*(s: Screen, count: int = 1) = (s.cursor.col = max(0, s.cursor.col - count); s.cursor.pendingWrap = false)
proc lineFeed*(s: Screen) =
  if s.cursor.row == s.scrollBottom: s.scrollUp(1)
  else: s.cursor.row = min(s.rows - 1, s.cursor.row + 1)
  s.cursor.pendingWrap = false
proc reverseIndex*(s: Screen) =
  if s.cursor.row == s.scrollTop: s.scrollDown(1)
  else: s.cursor.row = max(0, s.cursor.row - 1)
  s.cursor.pendingWrap = false

func scrollbackLen*(s: Screen): int = s.scrollback.len
func scrollbackText*(s: Screen, idx: int): string =
  if idx < 0 or idx >= s.scrollback.len: return ""
  result = newStringOfCap(s.cols)
  for c in s.scrollback[idx]:
    if c.isContinuation: continue
    result.add Rune(c.rune)
func scrollbackLine*(s: Screen, idx: int): seq[Cell] = (if idx < 0 or idx >= s.scrollback.len: @[] else: s.scrollback[idx])
proc carriageReturn*(s: Screen) = (s.cursor.col = 0; s.cursor.pendingWrap = false)
proc backspace*(s: Screen) = (s.cursor.col = max(0, s.cursor.col - 1); s.cursor.pendingWrap = false)
proc tab*(s: Screen) =
  for c in (s.cursor.col + 1) ..< s.cols: (if s.tabStops[c]: (s.cursor.col = c; return))
  s.cursor.col = s.cols - 1

proc writeRune*(s: Screen, cp: uint32, width: int) =
  if s.cursor.pendingWrap: (s.carriageReturn(); s.lineFeed())
  if s.cursor.col + width > s.cols: (s.carriageReturn(); s.lineFeed())
  if s.cursor.row >= s.rows: return
  if smInsert in s.modes:
    let g = if s.usingAlt: addr s.altGrid else: addr s.grid
    for c in countdown(s.cols - 1, s.cursor.col + width): g[][s.cursor.row][c] = g[][s.cursor.row][c - width]
  s.setCell(s.cursor.row, s.cursor.col, Cell(rune: cp, width: uint8(width), attrs: s.cursor.attrs))
  for i in 1 ..< width: (if s.cursor.col + i < s.cols: s.setCell(s.cursor.row, s.cursor.col + i, Cell(rune: 0, width: 0, attrs: s.cursor.attrs)))
  if s.cursor.col + width >= s.cols:
    if smAutoWrap in s.modes: s.cursor.pendingWrap = true; s.cursor.col = s.cols - 1
    else: s.cursor.col = s.cols - 1
  else: s.cursor.col += width

proc writeChar*(s: Screen, c: char) = s.writeRune(uint32(c), 1)
func sgr*(v: int, sub: seq[int] = @[]): SgrParam = SgrParam(value: v, subParams: sub)
proc writeString*(s: Screen, text: string) = (for r in text.runes: s.writeRune(uint32(r), 1))

proc eraseInLine*(s: Screen, mode: EraseMode) =
  case mode
  of emToEnd: s.clearRow(s.cursor.row, s.cursor.col, s.cols - 1, s.cursor.attrs)
  of emToStart: s.clearRow(s.cursor.row, 0, s.cursor.col, s.cursor.attrs)
  of emAll: s.clearRow(s.cursor.row, 0, s.cols - 1, s.cursor.attrs)

proc eraseInDisplay*(s: Screen, mode: EraseMode) =
  let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  case mode
  of emToEnd: (s.eraseInLine(emToEnd); if s.cursor.row < s.rows - 1: clearGrid(g[], s.cursor.row + 1, s.rows - 1, s.cols, s.cursor.attrs))
  of emToStart: (s.eraseInLine(emToStart); if s.cursor.row > 0: clearGrid(g[], 0, s.cursor.row - 1, s.cols, s.cursor.attrs))
  of emAll: clearGrid(g[], 0, s.rows - 1, s.cols, s.cursor.attrs)

proc insertLines*(s: Screen, count: int) = (if s.cursor.row >= s.scrollTop and s.cursor.row <= s.scrollBottom: (let ot = s.scrollTop; s.scrollTop = s.cursor.row; s.scrollDown(count); s.scrollTop = ot))
proc deleteLines*(s: Screen, count: int) = (if s.cursor.row >= s.scrollTop and s.cursor.row <= s.scrollBottom: (let ot = s.scrollTop; s.scrollTop = s.cursor.row; s.scrollUp(count); s.scrollTop = ot))
proc insertChars*(s: Screen, count: int) =
  let c = s.cursor.col; let r = s.cursor.row; let n = min(count, s.cols - c); let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  for i in countdown(s.cols - 1, c + n): g[][r][i] = g[][r][i - n]
  s.clearRow(r, c, c + n - 1, s.cursor.attrs)
proc deleteChars*(s: Screen, count: int) =
  let c = s.cursor.col; let r = s.cursor.row; let n = min(count, s.cols - c); let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  for i in c .. (s.cols - n - 1): g[][r][i] = g[][r][i + n]
  s.clearRow(r, s.cols - n, s.cols - 1, s.cursor.attrs)

func applyIndexedOr24bit(p: openArray[SgrParam], si: int, cur: Color): (Color, int) =
  if si >= p.len: return (cur, 0)
  if p[si].subParams.len > 0:
    let sp = p[si].subParams
    if sp[0] == 5 and sp.len >= 2: return (indexedColor(sp[1]), 0)
    if sp[0] == 2 and sp.len >= 4:
      let r = if sp.len >= 3: sp[sp.len-3] else: 0
      let g = if sp.len >= 2: sp[sp.len-2] else: 0
      let b = sp[sp.len-1]
      return (rgbColor(uint8(r), uint8(g), uint8(b)), 0)
    if sp[0] == 2 and sp.len == 5: return (rgbColor(uint8(sp[2]), uint8(sp[3]), uint8(sp[4])), 0)
  if si + 1 >= p.len: return (cur, 0)
  case p[si+1].value
  of 5:
    if si + 2 < p.len: return (indexedColor(p[si+2].value), 2)
  of 2:
    if si + 4 < p.len:
      return (rgbColor(uint8(p[si+2].value), uint8(p[si+3].value), uint8(p[si+4].value)), 4)
  else: discard
  
  return (cur, 0)

proc applySgr*(s: Screen, params: openArray[SgrParam]) =
  var i = 0
  while i < params.len:
    case params[i].value
    of 0: s.cursor.attrs = defaultAttrs()
    of 1: s.cursor.attrs.flags.incl afBold
    of 3: s.cursor.attrs.flags.incl afItalic
    of 4: s.cursor.attrs.flags.incl afUnderline
    of 7: s.cursor.attrs.flags.incl afInverse
    of 8: s.cursor.attrs.flags.incl afHidden
    of 22: s.cursor.attrs.flags.excl afBold
    of 23: s.cursor.attrs.flags.excl afItalic
    of 24: s.cursor.attrs.flags.excl afUnderline
    of 27: s.cursor.attrs.flags.excl afInverse
    of 28: s.cursor.attrs.flags.excl afHidden
    of 30..37: s.cursor.attrs.fg = indexedColor(params[i].value - 30)
    of 38: (let (c, consumed) = applyIndexedOr24bit(params, i, s.cursor.attrs.fg); s.cursor.attrs.fg = c; i += consumed)
    of 39: s.cursor.attrs.fg = defaultColor()
    of 40..47: s.cursor.attrs.bg = indexedColor(params[i].value - 40)
    of 48: (let (c, consumed) = applyIndexedOr24bit(params, i, s.cursor.attrs.bg); s.cursor.attrs.bg = c; i += consumed)
    of 49: s.cursor.attrs.bg = defaultColor()
    of 90..97:  s.cursor.attrs.fg = indexedColor(params[i].value - 90 + 8)
    of 100..107: s.cursor.attrs.bg = indexedColor(params[i].value - 100 + 8)
    else: discard
    inc i

proc setTabStop*(s: Screen) = (if s.cursor.col < s.cols: s.tabStops[s.cursor.col] = true)
proc clearTabStop*(s: Screen) = (if s.cursor.col < s.cols: s.tabStops[s.cursor.col] = false)
proc clearAllTabStops*(s: Screen) = (for i in 0 ..< s.cols: s.tabStops[i] = false)
proc setScrollRegion*(s: Screen, t, b: int) = (s.scrollTop = max(0, min(s.rows - 1, t)); s.scrollBottom = max(s.scrollTop, min(s.rows - 1, b)))
proc saveCursor*(s: Screen) = (if s.usingAlt: s.savedCursorAlt = some(s.cursor) else: s.savedCursor = some(s.cursor))
proc restoreCursor*(s: Screen) = (let saved = if s.usingAlt: s.savedCursorAlt else: s.savedCursor; if saved.isSome: (s.cursor = saved.get; s.cursor.pendingWrap = false))
