## Terminal screen buffer.
##
## A grid of cells representing what the user sees on screen, plus the
## cursor, scroll region, alternate-screen buffer, and a fixed-size
## scrollback ring. This widget is pure logic: it exposes a set of
## procedures to mutate the buffer.

import std/[options, strutils, unicode]

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
    afDim
    afItalic
    afUnderline
    afStrike
    afInverse
    afHidden
    afOverline

  UnderlineStyle* = enum
    usNone
    usSingle
    usDouble
    usCurly
    usDotted
    usDashed

  Attrs* = object
    fg*, bg*: Color
    flags*: set[AttrFlag]
    underlineStyle*: UnderlineStyle

  Cell* = object
    rune*: uint32
    width*: uint8          ## 0 (continuation), 1 (normal), 2 (wide)
    attrs*: Attrs

  CursorStyle* = enum
    csBlock
    csUnderline
    csBar

  Cursor* = object
    row*, col*: int
    attrs*: Attrs
    visible*: bool
    style*: CursorStyle
    pendingWrap*: bool     ## True if cursor is logically past end-of-line

  ScreenMode* = enum
    smAutoWrap
    smInsert
    smOrigin

  ScreenCharset* = enum
    scsAscii
    scsDecSpecialGraphics

  ScreenContextTransition* = object
    changed*: bool
    enteredAlt*: bool
    leftAlt*: bool
    clearTransientUi*: bool
    resetViewport*: bool
    resetOutputFootprint*: bool

  EraseMode* = enum
    emToEnd
    emToStart
    emAll
    emScrollback

  SgrParam* = object
    value*: int
    subParams*: seq[int]

  SavedScreenState = object
    cursor: Cursor
    g0Charset: ScreenCharset
    g1Charset: ScreenCharset
    activeCharset: int
    modes: set[ScreenMode]

  Screen* = ref object
    cols*, rows*: int
    grid: seq[seq[Cell]]
    altGrid: seq[seq[Cell]]
    rowSoftWrap: seq[bool]
    altRowSoftWrap: seq[bool]
    cursor*: Cursor
    savedCursor: Option[SavedScreenState]
    savedCursorAlt: Option[SavedScreenState]
    scrollTop*, scrollBottom*: int
    tabStops: seq[bool]
    modes*: set[ScreenMode]
    scrollback*: seq[seq[Cell]]
    scrollbackSoftWrap: seq[bool]
    altScrollback: seq[seq[Cell]]
    altScrollbackSoftWrap: seq[bool]
    scrollbackCap*: int
    altScrollbackEnabled*: bool
    usingAlt*: bool
    charset*: ScreenCharset
    g0Charset*: ScreenCharset
    g1Charset*: ScreenCharset
    activeCharset*: int
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
    selection:  rgb(148, 113, 24),
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
  Attrs(fg: defaultColor(), bg: defaultColor(), flags: {}, underlineStyle: usNone)

func emptyCell*(attrs: Attrs = defaultAttrs()): Cell =
  Cell(rune: uint32(' '), width: 1, attrs: attrs)

func isContinuation*(c: Cell): bool = c.width == 0

func makeRow(cols: int, attrs: Attrs = defaultAttrs()): seq[Cell] =
  result = newSeq[Cell](cols)
  for i in 0 ..< cols: result[i] = emptyCell(attrs)

func makeGrid(cols, rows: int, attrs: Attrs = defaultAttrs()): seq[seq[Cell]] =
  result = newSeq[seq[Cell]](rows)
  for i in 0 ..< rows: result[i] = makeRow(cols, attrs)

func makeWrapFlags(rows: int): seq[bool] =
  newSeq[bool](rows)

func makeTabStops(cols, width: int): seq[bool] =
  result = newSeq[bool](cols)
  for i in countup(width, cols - 1, width): result[i] = true

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func newCursor(): Cursor =
  Cursor(row: 0, col: 0, attrs: defaultAttrs(), visible: true, style: csBlock, pendingWrap: false)

func newScreen*(
    cols, rows: int,
    scrollback: int = DefaultScrollback
): Screen =
  let attrs = defaultAttrs()
  result = Screen(
    cols: cols, rows: rows,
    grid: makeGrid(cols, rows, attrs),
    altGrid: makeGrid(cols, rows, attrs),
    rowSoftWrap: makeWrapFlags(rows),
    altRowSoftWrap: makeWrapFlags(rows),
    cursor: newCursor(),
    scrollTop: 0, scrollBottom: rows - 1,
    tabStops: makeTabStops(cols, DefaultTabWidth),
    modes: {smAutoWrap},
    scrollback: @[],
    scrollbackSoftWrap: @[],
    altScrollback: @[],
    altScrollbackSoftWrap: @[],
    scrollbackCap: scrollback,
    altScrollbackEnabled: false,
    usingAlt: false,
    charset: scsAscii,
    g0Charset: scsAscii,
    g1Charset: scsAscii,
    activeCharset: 0,
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
  if s.usingAlt: s.altScrollback.len + s.rows else: s.scrollback.len + s.rows

func absoluteCursorRow*(s: Screen): int =
  ## Returns the cursor row in the same absolute coordinate space used by
  ## absoluteRowAt. Alternate-screen coordinates do not include primary
  ## scrollback.
  if s.usingAlt: s.altScrollback.len + s.cursor.row else: s.scrollback.len + s.cursor.row

func absoluteRowAt*(s: Screen, absRow: int): seq[Cell] =
  if absRow < 0: return @[]
  if s.usingAlt:
    if absRow < s.altScrollback.len: return s.altScrollback[absRow]
    let gr = absRow - s.altScrollback.len
    if gr >= s.rows: return @[]
    return s.altGrid[gr]
  if absRow < s.scrollback.len: return s.scrollback[absRow]
  let gr = absRow - s.scrollback.len
  if gr >= s.rows: return @[]
  s.grid[gr]

func absoluteCellAt*(s: Screen, absRow, col: int): Cell =
  if col < 0 or col >= s.cols or absRow < 0: return emptyCell()
  if s.usingAlt:
    let row =
      if absRow < s.altScrollback.len:
        s.altScrollback[absRow]
      else:
        let gr = absRow - s.altScrollback.len
        if gr >= s.rows: return emptyCell()
        s.altGrid[gr]
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

func isBlankCell(c: Cell): bool =
  c.rune == uint32(' ') and c.width == 1

func contentLen(row: seq[Cell], softWrapped: bool): int =
  if softWrapped: return row.len
  result = row.len
  while result > 0 and isBlankCell(row[result - 1]): dec result

func absoluteContentLen*(s: Screen, absRow: int): int =
  ## Returns the display width containing non-blank content for an absolute row.
  ## Soft-wrapped rows keep their full width so wrapped logical lines remain
  ## selectable through the wrap boundary.
  if absRow < 0: return 0
  if s.usingAlt:
    if absRow < s.altScrollback.len:
      return contentLen(s.altScrollback[absRow], absRow < s.altScrollbackSoftWrap.len and s.altScrollbackSoftWrap[absRow])
    let gr = absRow - s.altScrollback.len
    if gr >= s.rows: return 0
    return contentLen(s.altGrid[gr], gr < s.altRowSoftWrap.len and s.altRowSoftWrap[gr])
  if absRow < s.scrollback.len:
    return contentLen(s.scrollback[absRow], absRow < s.scrollbackSoftWrap.len and s.scrollbackSoftWrap[absRow])
  let gr = absRow - s.scrollback.len
  if gr < 0 or gr >= s.rows: return 0
  contentLen(s.grid[gr], gr < s.rowSoftWrap.len and s.rowSoftWrap[gr])

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

func rowSoftWrapped*(s: Screen, row: int): bool =
  if row < 0 or row >= s.rows: return false
  (if s.usingAlt: s.altRowSoftWrap else: s.rowSoftWrap)[row]

func scrollbackSoftWrapped*(s: Screen, idx: int): bool =
  if idx < 0 or idx >= s.scrollbackSoftWrap.len: return false
  s.scrollbackSoftWrap[idx]

# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------

proc setCell(s: Screen, row, col: int, cell: Cell) =
  if row < 0 or row >= s.rows or col < 0 or col >= s.cols: return
  if s.usingAlt:
    if col < s.altGrid[row].len: s.altGrid[row][col] = cell
  else:
    if col < s.grid[row].len: s.grid[row][col] = cell

proc setSoftWrap(s: Screen, row: int, wrapped: bool) =
  if row < 0 or row >= s.rows: return
  if s.usingAlt: s.altRowSoftWrap[row] = wrapped
  else: s.rowSoftWrap[row] = wrapped

proc clearRow(s: Screen, row: int, startCol, endCol: int, attrs: Attrs) =
  if row < 0 or row >= s.rows or s.cols <= 0: return
  let first = max(0, startCol)
  let last = min(s.cols - 1, endCol)
  if first > last: return
  for c in first .. last: s.setCell(row, c, emptyCell(attrs))
  if first == 0 and last == s.cols - 1: s.setSoftWrap(row, false)

proc clearGrid(grid: var seq[seq[Cell]], startRow, endRow: int, cols: int, attrs: Attrs) =
  for r in startRow .. endRow:
    for c in 0 ..< cols: grid[r][c] = emptyCell(attrs)

proc addScrollbackRow(rows: var seq[seq[Cell]], wraps: var seq[bool], row: seq[Cell], wrapped: bool, cap: int) =
  rows.add row
  wraps.add wrapped
  if rows.len > cap:
    rows.delete(0)
    if wraps.len > 0: wraps.delete(0)

proc resizeScrollbackRows(rows: var seq[seq[Cell]], oldCols, cols: int, attrs: Attrs) =
  for row in rows.mitems:
    row.setLen(cols)
    for c in oldCols ..< cols:
      row[c] = emptyCell(attrs)

proc scrollUp*(s: Screen, count: int = 1) =
  let n = min(count, s.scrollBottom - s.scrollTop + 1)
  if n <= 0: return
  let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  let wraps = if s.usingAlt: addr s.altRowSoftWrap else: addr s.rowSoftWrap
  if s.usingAlt and s.altScrollbackEnabled:
    for i in 0 ..< n:
      addScrollbackRow(
        s.altScrollback,
        s.altScrollbackSoftWrap,
        g[][s.scrollTop + i],
        wraps[][s.scrollTop + i],
        s.scrollbackCap,
      )
  elif not s.usingAlt and s.scrollTop == 0:
    for i in 0 ..< n:
      addScrollbackRow(
        s.scrollback,
        s.scrollbackSoftWrap,
        g[][s.scrollTop + i],
        wraps[][s.scrollTop + i],
        s.scrollbackCap,
      )
  for r in s.scrollTop .. (s.scrollBottom - n): g[][r] = g[][r + n]
  for r in s.scrollTop .. (s.scrollBottom - n): wraps[][r] = wraps[][r + n]
  let attrs = s.cursor.attrs
  for r in (s.scrollBottom - n + 1) .. s.scrollBottom:
    g[][r] = makeRow(s.cols, attrs)
    wraps[][r] = false

proc scrollDown*(s: Screen, count: int = 1) =
  let n = min(count, s.scrollBottom - s.scrollTop + 1)
  if n <= 0: return
  let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  let wraps = if s.usingAlt: addr s.altRowSoftWrap else: addr s.rowSoftWrap
  for r in countdown(s.scrollBottom, s.scrollTop + n): g[][r] = g[][r - n]
  for r in countdown(s.scrollBottom, s.scrollTop + n): wraps[][r] = wraps[][r - n]
  let attrs = s.cursor.attrs
  for r in s.scrollTop .. (s.scrollTop + n - 1):
    g[][r] = makeRow(s.cols, attrs)
    wraps[][r] = false

proc useAlternateScreen*(s: Screen, active: bool) =
  if active == s.usingAlt: return
  if active:
    s.altScrollback.setLen(0)
    s.altScrollbackSoftWrap.setLen(0)
  s.usingAlt = active

proc switchAlternateScreen*(s: Screen, active: bool): ScreenContextTransition =
  ## Switch between primary and alternate screen contexts and return the
  ## caller-visible side effects implied by that transition.
  if active == s.usingAlt:
    return ScreenContextTransition()
  if active:
    s.altScrollback.setLen(0)
    s.altScrollbackSoftWrap.setLen(0)
  s.usingAlt = active
  ScreenContextTransition(
    changed: true,
    enteredAlt: active,
    leftAlt: not active,
    clearTransientUi: true,
    resetViewport: true,
    resetOutputFootprint: active,
  )

proc applyPrivateMode*(s: Screen, code: int, set: bool): bool =
  ## Applies private modes that belong to screen-buffer state.
  ##
  ## Returns true when the mode was handled by this widget.
  case code
  of 6:
    if set: s.modes.incl smOrigin
    else: s.modes.excl smOrigin
    s.cursor.row = if set: s.scrollTop else: 0
    s.cursor.col = 0
    s.cursor.pendingWrap = false
    true
  of 7:
    if set: s.modes.incl smAutoWrap
    else: s.modes.excl smAutoWrap
    true
  of 25:
    s.cursor.visible = set
    true
  else:
    false

proc reset*(s: Screen) =
  s.cursor = newCursor(); s.scrollTop = 0; s.scrollBottom = s.rows - 1
  s.tabStops = makeTabStops(s.cols, DefaultTabWidth); s.modes = {smAutoWrap}
  s.usingAlt = false; s.charset = scsAscii; s.g0Charset = scsAscii; s.g1Charset = scsAscii; s.activeCharset = 0; s.scrollback.setLen(0); s.scrollbackSoftWrap.setLen(0); s.altScrollback.setLen(0); s.altScrollbackSoftWrap.setLen(0); s.title = ""; s.iconName = ""
  s.theme = defaultTheme(); let attrs = defaultAttrs()
  for r in 0 ..< s.rows:
    s.grid[r] = makeRow(s.cols, attrs)
    s.altGrid[r] = makeRow(s.cols, attrs)
    s.rowSoftWrap[r] = false
    s.altRowSoftWrap[r] = false

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
      s.scrollbackSoftWrap.add s.rowSoftWrap[i]
      if s.scrollback.len > s.scrollbackCap:
        s.scrollback.delete(0)
        if s.scrollbackSoftWrap.len > 0: s.scrollbackSoftWrap.delete(0)
    for i in 0 ..< rows: s.grid[i] = s.grid[i + diff]
    for i in 0 ..< rows: s.rowSoftWrap[i] = s.rowSoftWrap[i + diff]
    s.grid.setLen(rows); s.altGrid.setLen(rows)
    s.rowSoftWrap.setLen(rows); s.altRowSoftWrap.setLen(rows)
    for r in 0 ..< rows:
      s.grid[r].setLen(cols)
      s.altGrid[r].setLen(cols)
      for c in oldCols ..< cols:
        s.grid[r][c] = emptyCell(attrs)
        s.altGrid[r][c] = emptyCell(attrs)
  else:
    s.grid.setLen(rows); s.altGrid.setLen(rows)
    s.rowSoftWrap.setLen(rows); s.altRowSoftWrap.setLen(rows)
    for r in 0 ..< rows:
      if r < oldRows:
        s.grid[r].setLen(cols); s.altGrid[r].setLen(cols)
        for c in oldCols ..< cols: (s.grid[r][c] = emptyCell(attrs); s.altGrid[r][c] = emptyCell(attrs))
      else:
        s.grid[r] = makeRow(cols, attrs)
        s.altGrid[r] = makeRow(cols, attrs)
        s.rowSoftWrap[r] = false
        s.altRowSoftWrap[r] = false
  resizeScrollbackRows(s.scrollback, oldCols, cols, attrs)
  resizeScrollbackRows(s.altScrollback, oldCols, cols, attrs)
  s.cols = cols; s.rows = rows; s.cursor.row = max(0, min(rows-1, s.cursor.row)); s.cursor.col = max(0, min(cols-1, s.cursor.col))
  s.scrollTop = 0; s.scrollBottom = rows - 1; s.tabStops = makeTabStops(cols, DefaultTabWidth)

func rowHasContent(row: seq[Cell], softWrapped: bool): bool =
  contentLen(row, softWrapped) > 0

proc resizeVisibleContentFromTop(
    s: Screen,
    cols, rows: int,
    oldGrid, oldAltGrid: seq[seq[Cell]],
    oldWraps, oldAltWraps: seq[bool],
    oldCursorRow, oldCols: int,
) =
  let attrs = defaultAttrs()
  var first = oldGrid.len
  var last = -1
  for r in 0 ..< oldGrid.len:
    if rowHasContent(oldGrid[r], r < oldWraps.len and oldWraps[r]) or r == oldCursorRow:
      first = min(first, r)
      last = max(last, r)

  if last < first:
    first = max(0, min(oldGrid.len - 1, oldCursorRow))
    last = first

  let blockLen = min(rows, last - first + 1)
  s.grid = makeGrid(cols, rows, attrs)
  s.altGrid = makeGrid(cols, rows, attrs)
  s.rowSoftWrap = makeWrapFlags(rows)
  s.altRowSoftWrap = makeWrapFlags(rows)

  for r in 0 ..< blockLen:
    let oldIndex = first + r
    s.grid[r] = oldGrid[oldIndex]
    s.altGrid[r] = oldAltGrid[oldIndex]
    s.rowSoftWrap[r] = oldIndex < oldWraps.len and oldWraps[oldIndex]
    s.altRowSoftWrap[r] = oldIndex < oldAltWraps.len and oldAltWraps[oldIndex]
    s.grid[r].setLen(cols)
    s.altGrid[r].setLen(cols)
    for c in oldCols ..< cols:
      s.grid[r][c] = emptyCell(attrs)
      s.altGrid[r][c] = emptyCell(attrs)

  s.cursor.row = max(0, min(rows - 1, oldCursorRow - first))

proc appendLogicalRows(
    logical: var seq[seq[Cell]],
    cursorLine: var int,
    cursorOffset: var int,
    rows: seq[seq[Cell]],
    wraps: seq[bool],
    startAbsRow, cursorAbsRow, cursorCol: int
) =
  var current: seq[Cell] = @[]
  for idx, row in rows:
    let absRow = startAbsRow + idx
    let wrapped = idx < wraps.len and wraps[idx]
    let keep = contentLen(row, wrapped)
    if keep == 0 and absRow > cursorAbsRow:
      continue
    if absRow == cursorAbsRow:
      cursorLine = logical.len
      cursorOffset = current.len + max(0, min(cursorCol, keep))
    for c in 0 ..< keep:
      if not row[c].isContinuation: current.add row[c]
    if not wrapped:
      logical.add current
      current = @[]
  if current.len > 0:
    logical.add current

proc rewrapLogicalLines(
    logical: seq[seq[Cell]],
    cols, rows, scrollbackCap, cursorLine, cursorOffset, preferredCursorRow: int,
    oldCursor: Cursor,
    preserveCursorRowWhenShort: bool
): tuple[
    grid: seq[seq[Cell]],
    wraps: seq[bool],
    scrollback: seq[seq[Cell]],
    scrollbackWraps: seq[bool],
    cursor: Cursor
  ] =
  let attrs = defaultAttrs()
  var allRows: seq[seq[Cell]] = @[]
  var allWraps: seq[bool] = @[]
  var cursorAbs = -1
  var cursorCol = 0

  for lineIndex, line in logical:
    var row = makeRow(cols, attrs)
    var col = 0
    var lineOffset = 0
    var cursorPlaced = false

    proc finishRow(wrapped: bool) =
      allRows.add row
      allWraps.add wrapped
      row = makeRow(cols, attrs)
      col = 0

    if line.len == 0:
      if lineIndex == cursorLine:
        cursorAbs = allRows.len
        cursorCol = 0
        cursorPlaced = true
      finishRow(false)
      continue

    for cellIndex, cell in line:
      let width = max(1, int(cell.width))
      if lineIndex == cursorLine and not cursorPlaced and cursorOffset <= lineOffset:
        cursorAbs = allRows.len
        cursorCol = min(col, cols - 1)
        cursorPlaced = true
      if col + width > cols:
        finishRow(true)
      row[col] = cell
      if width == 2 and col + 1 < cols:
        row[col + 1] = Cell(rune: 0, width: 0, attrs: cell.attrs)
      col += width
      lineOffset += width
      if col >= cols and cellIndex < line.len - 1:
        finishRow(true)

    if lineIndex == cursorLine and not cursorPlaced:
      cursorAbs = allRows.len
      cursorCol = min(col, cols - 1)
    finishRow(false)

  if allRows.len == 0:
    allRows.add makeRow(cols, attrs)
    allWraps.add false
    cursorAbs = 0
    cursorCol = 0

  var leadingBlanks = 0
  if allRows.len < rows:
    let spareRows = rows - allRows.len
    leadingBlanks =
      if preserveCursorRowWhenShort and cursorAbs >= 0: max(0, min(spareRows, preferredCursorRow - cursorAbs))
      else: 0
    for _ in 0 ..< leadingBlanks:
      allRows.insert(makeRow(cols, attrs), 0)
      allWraps.insert(false, 0)
    for _ in 0 ..< spareRows - leadingBlanks:
      allRows.add makeRow(cols, attrs)
      allWraps.add false
  if cursorAbs >= 0: cursorAbs += leadingBlanks

  let visibleStart = max(0, allRows.len - rows)
  let scrollEnd = visibleStart
  let scrollStart = max(0, scrollEnd - scrollbackCap)
  result.scrollback = allRows[scrollStart ..< scrollEnd]
  result.scrollbackWraps = allWraps[scrollStart ..< scrollEnd]
  result.grid = allRows[visibleStart ..< allRows.len]
  result.wraps = allWraps[visibleStart ..< allWraps.len]
  result.cursor = oldCursor
  if cursorAbs < 0:
    cursorAbs = allRows.len - 1
    cursorCol = 0
  result.cursor.row = max(0, min(rows - 1, cursorAbs - visibleStart))
  result.cursor.col = max(0, min(cols - 1, cursorCol))
  result.cursor.pendingWrap = false

proc resizePreserveBottom*(s: Screen, cols, rows: int, preserveCursorRowWhenShort = true) =
  ## Resize while preserving the bottom-relative position of visible content.
  ##
  ## This is useful for display-only zoom where the child process should not
  ## repaint, but the visible grid still needs to match the new cell geometry.
  if cols <= 0 or rows <= 0: return
  if cols == s.cols and rows == s.rows: return
  if s.usingAlt:
    s.resize(cols, rows)
    return

  if cols != s.cols:
    var logical: seq[seq[Cell]] = @[]
    var cursorLine = 0
    var cursorOffset = 0
    let cursorAbsRow = s.scrollback.len + s.cursor.row
    logical.appendLogicalRows(cursorLine, cursorOffset, s.scrollback, s.scrollbackSoftWrap, 0, cursorAbsRow, s.cursor.col)
    logical.appendLogicalRows(cursorLine, cursorOffset, s.grid, s.rowSoftWrap, s.scrollback.len, cursorAbsRow, s.cursor.col)
    let reflowed = rewrapLogicalLines(
      logical,
      cols,
      rows,
      s.scrollbackCap,
      cursorLine,
      cursorOffset,
      s.cursor.row,
      s.cursor,
      preserveCursorRowWhenShort,
    )
    s.grid = reflowed.grid
    s.rowSoftWrap = reflowed.wraps
    s.altGrid = makeGrid(cols, rows, defaultAttrs())
    s.altRowSoftWrap = makeWrapFlags(rows)
    s.scrollback = reflowed.scrollback
    s.scrollbackSoftWrap = reflowed.scrollbackWraps
    s.cursor = reflowed.cursor
    s.cols = cols
    s.rows = rows
    s.scrollTop = 0
    s.scrollBottom = rows - 1
    s.tabStops = makeTabStops(cols, DefaultTabWidth)
    return

  let oldRows = s.rows
  let oldCols = s.cols
  let attrs = defaultAttrs()
  let oldGrid = s.grid
  let oldAltGrid = s.altGrid
  let oldWraps = s.rowSoftWrap
  let oldAltWraps = s.altRowSoftWrap
  let oldCursorRow = s.cursor.row
  let diff = rows - oldRows

  if not preserveCursorRowWhenShort:
    resizeVisibleContentFromTop(s, cols, rows, oldGrid, oldAltGrid, oldWraps, oldAltWraps, oldCursorRow, oldCols)
    s.cols = cols
    s.rows = rows
    s.cursor.col = max(0, min(cols - 1, s.cursor.col))
    s.scrollTop = 0
    s.scrollBottom = rows - 1
    s.tabStops = makeTabStops(cols, DefaultTabWidth)
    return

  s.grid = newSeq[seq[Cell]](rows)
  s.altGrid = newSeq[seq[Cell]](rows)
  s.rowSoftWrap = newSeq[bool](rows)
  s.altRowSoftWrap = newSeq[bool](rows)

  for r in 0 ..< rows:
    let oldIndex = r - diff
    if oldIndex >= 0 and oldIndex < oldRows:
      s.grid[r] = oldGrid[oldIndex]
      s.altGrid[r] = oldAltGrid[oldIndex]
      s.rowSoftWrap[r] = oldWraps[oldIndex]
      s.altRowSoftWrap[r] = oldAltWraps[oldIndex]
      s.grid[r].setLen(cols)
      s.altGrid[r].setLen(cols)
      for c in oldCols ..< cols:
        s.grid[r][c] = emptyCell(attrs)
        s.altGrid[r][c] = emptyCell(attrs)
    else:
      s.grid[r] = makeRow(cols, attrs)
      s.altGrid[r] = makeRow(cols, attrs)
      s.rowSoftWrap[r] = false
      s.altRowSoftWrap[r] = false

  if diff < 0:
    let removed = -diff
    for i in 0 ..< min(removed, oldRows):
      var row = oldGrid[i]
      row.setLen(cols)
      for c in oldCols ..< cols: row[c] = emptyCell(attrs)
      s.scrollback.add row
      s.scrollbackSoftWrap.add oldWraps[i]
      if s.scrollback.len > s.scrollbackCap:
        s.scrollback.delete(0)
        if s.scrollbackSoftWrap.len > 0: s.scrollbackSoftWrap.delete(0)

  s.cols = cols
  s.rows = rows
  s.cursor.row = max(0, min(rows - 1, oldCursorRow + diff))
  s.cursor.col = max(0, min(cols - 1, s.cursor.col))
  s.scrollTop = 0
  s.scrollBottom = rows - 1
  s.tabStops = makeTabStops(cols, DefaultTabWidth)

proc cursorTo*(s: Screen, row, col: int) =
  let top = if smOrigin in s.modes: s.scrollTop else: 0
  let bottom = if smOrigin in s.modes: s.scrollBottom else: s.rows - 1
  s.cursor.row = max(top, min(bottom, top + row))
  s.cursor.col = max(0, min(s.cols - 1, col))
  s.cursor.pendingWrap = false
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
proc tab*(s: Screen, count: int = 1) =
  for _ in 0 ..< max(1, count):
    var moved = false
    for c in (s.cursor.col + 1) ..< s.cols:
      if s.tabStops[c]:
        s.cursor.col = c
        moved = true
        s.cursor.pendingWrap = false
        break
    if not moved:
      s.cursor.col = s.cols - 1
    s.cursor.pendingWrap = false

proc backTab*(s: Screen, count: int = 1) =
  for _ in 0 ..< max(1, count):
    var moved = false
    if s.cursor.col > 0:
      for c in countdown(s.cursor.col - 1, 0):
        if s.tabStops[c]:
          s.cursor.col = c
          moved = true
          break
    if not moved:
      s.cursor.col = 0
    s.cursor.pendingWrap = false

func decSpecialGraphic(cp: uint32): uint32 =
  case cp
  of uint32('j'): 0x2518'u32 # lower-right corner
  of uint32('k'): 0x2510'u32 # upper-right corner
  of uint32('l'): 0x250C'u32 # upper-left corner
  of uint32('m'): 0x2514'u32 # lower-left corner
  of uint32('n'): 0x253C'u32 # crossing lines
  of uint32('q'): 0x2500'u32 # horizontal line
  of uint32('t'): 0x251C'u32 # left tee
  of uint32('u'): 0x2524'u32 # right tee
  of uint32('v'): 0x2534'u32 # bottom tee
  of uint32('w'): 0x252C'u32 # top tee
  of uint32('x'): 0x2502'u32 # vertical line
  else: cp

func translateCharset(s: Screen, cp: uint32): uint32 =
  let charset = if s.activeCharset == 1: s.g1Charset else: s.g0Charset
  case charset
  of scsAscii: cp
  of scsDecSpecialGraphics: decSpecialGraphic(cp)

proc setCharset*(s: Screen, charset: ScreenCharset) =
  s.g0Charset = charset
  s.charset = charset

proc selectCharset*(s: Screen, slot: int, charset: ScreenCharset) =
  if slot == 1:
    s.g1Charset = charset
  else:
    s.g0Charset = charset
    s.charset = charset

proc shiftOut*(s: Screen) =
  s.activeCharset = 1
  s.charset = s.g1Charset

proc shiftIn*(s: Screen) =
  s.activeCharset = 0
  s.charset = s.g0Charset

proc writeRune*(s: Screen, cp: uint32, width: int) =
  let mapped = s.translateCharset(cp)
  if s.cursor.pendingWrap:
    s.setSoftWrap(s.cursor.row, true)
    s.carriageReturn()
    s.lineFeed()
  if s.cursor.col + width > s.cols:
    s.setSoftWrap(s.cursor.row, true)
    s.carriageReturn()
    s.lineFeed()
  if s.cursor.row >= s.rows: return
  if smInsert in s.modes:
    let g = if s.usingAlt: addr s.altGrid else: addr s.grid
    for c in countdown(s.cols - 1, s.cursor.col + width): g[][s.cursor.row][c] = g[][s.cursor.row][c - width]
  s.setCell(s.cursor.row, s.cursor.col, Cell(rune: mapped, width: uint8(width), attrs: s.cursor.attrs))
  for i in 1 ..< width: (if s.cursor.col + i < s.cols: s.setCell(s.cursor.row, s.cursor.col + i, Cell(rune: 0, width: 0, attrs: s.cursor.attrs)))
  if s.cursor.col + width >= s.cols:
    if smAutoWrap in s.modes: s.cursor.pendingWrap = true; s.cursor.col = s.cols - 1
    else: s.cursor.col = s.cols - 1
  else: s.cursor.col += width

func previousGraphicCell(s: Screen): Cell =
  let g = if s.usingAlt: s.altGrid else: s.grid
  var row = s.cursor.row
  var col = s.cursor.col - 1
  while row >= 0:
    while col >= 0:
      let cell = g[row][col]
      if cell.width > 0 and cell.rune != 0:
        return cell
      dec col
    dec row
    col = s.cols - 1
  emptyCell()

proc repeatPreviousChar*(s: Screen, count: int) =
  let cell = s.previousGraphicCell()
  if cell.rune == 0:
    return
  let savedAttrs = s.cursor.attrs
  s.cursor.attrs = cell.attrs
  for _ in 0 ..< max(0, count):
    s.writeRune(cell.rune, int(cell.width))
  s.cursor.attrs = savedAttrs

proc writeChar*(s: Screen, c: char) = s.writeRune(uint32(c), 1)
func sgr*(v: int, sub: seq[int] = @[]): SgrParam = SgrParam(value: v, subParams: sub)
proc writeString*(s: Screen, text: string) = (for r in text.runes: s.writeRune(uint32(r), 1))

proc eraseInLine*(s: Screen, mode: EraseMode) =
  case mode
  of emToEnd: s.clearRow(s.cursor.row, s.cursor.col, s.cols - 1, s.cursor.attrs)
  of emToStart: s.clearRow(s.cursor.row, 0, s.cursor.col, s.cursor.attrs)
  of emAll, emScrollback: s.clearRow(s.cursor.row, 0, s.cols - 1, s.cursor.attrs)

proc eraseInDisplay*(s: Screen, mode: EraseMode) =
  let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  let wraps = if s.usingAlt: addr s.altRowSoftWrap else: addr s.rowSoftWrap
  case mode
  of emToEnd:
    s.eraseInLine(emToEnd)
    if s.cursor.row < s.rows - 1:
      clearGrid(g[], s.cursor.row + 1, s.rows - 1, s.cols, s.cursor.attrs)
      for r in s.cursor.row + 1 .. s.rows - 1: wraps[][r] = false
  of emToStart:
    s.eraseInLine(emToStart)
    if s.cursor.row > 0:
      clearGrid(g[], 0, s.cursor.row - 1, s.cols, s.cursor.attrs)
      for r in 0 .. s.cursor.row - 1: wraps[][r] = false
  of emAll:
    clearGrid(g[], 0, s.rows - 1, s.cols, s.cursor.attrs)
    for r in 0 ..< s.rows: wraps[][r] = false
  of emScrollback:
    if s.usingAlt:
      s.altScrollback.setLen(0)
      s.altScrollbackSoftWrap.setLen(0)
    else:
      s.scrollback.setLen(0)
      s.scrollbackSoftWrap.setLen(0)

proc screenAlignmentTest*(s: Screen) =
  ## DECALN fills the active display with E characters using default attrs.
  let g = if s.usingAlt: addr s.altGrid else: addr s.grid
  let wraps = if s.usingAlt: addr s.altRowSoftWrap else: addr s.rowSoftWrap
  let attrs = defaultAttrs()
  for r in 0 ..< s.rows:
    for c in 0 ..< s.cols:
      g[][r][c] = Cell(rune: uint32('E'), width: 1, attrs: attrs)
    wraps[][r] = false
  s.cursor.pendingWrap = false

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

proc eraseChars*(s: Screen, count: int) =
  let c = s.cursor.col
  let r = s.cursor.row
  let n = min(max(0, count), s.cols - c)
  if n <= 0:
    return
  s.clearRow(r, c, c + n - 1, s.cursor.attrs)
  s.cursor.pendingWrap = false

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

proc applyUnderlineStyle(s: Screen, param: SgrParam) =
  ## SGR 4 can carry sub-parameters: 4:0 clears underline, while 4:1..5
  ## select visible underline styles.
  let styleCode =
    if param.subParams.len > 0: param.subParams[0]
    else: 1
  case styleCode
  of 0:
    s.cursor.attrs.flags.excl afUnderline
    s.cursor.attrs.underlineStyle = usNone
  of 2:
    s.cursor.attrs.flags.incl afUnderline
    s.cursor.attrs.underlineStyle = usDouble
  of 3:
    s.cursor.attrs.flags.incl afUnderline
    s.cursor.attrs.underlineStyle = usCurly
  of 4:
    s.cursor.attrs.flags.incl afUnderline
    s.cursor.attrs.underlineStyle = usDotted
  of 5:
    s.cursor.attrs.flags.incl afUnderline
    s.cursor.attrs.underlineStyle = usDashed
  else:
    s.cursor.attrs.flags.incl afUnderline
    s.cursor.attrs.underlineStyle = usSingle

proc applySgr*(s: Screen, params: openArray[SgrParam]) =
  if params.len == 0:
    s.cursor.attrs = defaultAttrs()
    return
  var i = 0
  while i < params.len:
    case params[i].value
    of 0: s.cursor.attrs = defaultAttrs()
    of 1: s.cursor.attrs.flags.incl afBold
    of 2: s.cursor.attrs.flags.incl afDim
    of 3: s.cursor.attrs.flags.incl afItalic
    of 4: s.applyUnderlineStyle(params[i])
    of 9: s.cursor.attrs.flags.incl afStrike
    of 21: s.cursor.attrs.flags.incl afUnderline
    of 7: s.cursor.attrs.flags.incl afInverse
    of 8: s.cursor.attrs.flags.incl afHidden
    of 22:
      s.cursor.attrs.flags.excl afBold
      s.cursor.attrs.flags.excl afDim
    of 23: s.cursor.attrs.flags.excl afItalic
    of 24:
      s.cursor.attrs.flags.excl afUnderline
      s.cursor.attrs.underlineStyle = usNone
    of 27: s.cursor.attrs.flags.excl afInverse
    of 28: s.cursor.attrs.flags.excl afHidden
    of 29: s.cursor.attrs.flags.excl afStrike
    of 53: s.cursor.attrs.flags.incl afOverline
    of 55: s.cursor.attrs.flags.excl afOverline
    of 30..37: s.cursor.attrs.fg = indexedColor(params[i].value - 30)
    of 38:
      let (c, consumed) = applyIndexedOr24bit(params, i, s.cursor.attrs.fg)
      s.cursor.attrs.fg = c
      i += consumed
    of 39: s.cursor.attrs.fg = defaultColor()
    of 40..47: s.cursor.attrs.bg = indexedColor(params[i].value - 40)
    of 48:
      let (c, consumed) = applyIndexedOr24bit(params, i, s.cursor.attrs.bg)
      s.cursor.attrs.bg = c
      i += consumed
    of 49: s.cursor.attrs.bg = defaultColor()
    of 90..97:  s.cursor.attrs.fg = indexedColor(params[i].value - 90 + 8)
    of 100..107: s.cursor.attrs.bg = indexedColor(params[i].value - 100 + 8)
    else: discard
    inc i

proc setCursorStyle*(s: Screen, code: int) =
  ## Apply xterm DECSCUSR cursor style. Blinking variants are stored as their
  ## non-blinking shape for now; rendering can add blink timing later.
  case code
  of 3, 4: s.cursor.style = csUnderline
  of 5, 6: s.cursor.style = csBar
  else: s.cursor.style = csBlock

func cursorStyleReportCode*(s: Screen): int =
  ## Return a stable DECSCUSR code for the current cursor shape.
  case s.cursor.style
  of csBlock: 1
  of csUnderline: 3
  of csBar: 5

func colorSgrParams(c: Color, foreground: bool): seq[string] =
  case c.kind
  of ckDefault:
    discard
  of ckIndexed:
    if c.index >= 0 and c.index <= 7:
      result.add $(if foreground: 30 + c.index else: 40 + c.index)
    elif c.index >= 8 and c.index <= 15:
      result.add $(if foreground: 90 + c.index - 8 else: 100 + c.index - 8)
    else:
      result.add(if foreground: "38" else: "48")
      result.add "5"
      result.add $c.index
  of ckRgb:
    result.add(if foreground: "38" else: "48")
    result.add "2"
    result.add $c.r
    result.add $c.g
    result.add $c.b

func sgrReport*(s: Screen): string =
  ## Return a compact SGR state string suitable for DECRQSS "m" replies.
  var parts: seq[string] = @[]
  if afBold in s.cursor.attrs.flags: parts.add "1"
  if afDim in s.cursor.attrs.flags: parts.add "2"
  if afItalic in s.cursor.attrs.flags: parts.add "3"
  if afUnderline in s.cursor.attrs.flags: parts.add "4"
  if afInverse in s.cursor.attrs.flags: parts.add "7"
  if afHidden in s.cursor.attrs.flags: parts.add "8"
  if afStrike in s.cursor.attrs.flags: parts.add "9"
  if afOverline in s.cursor.attrs.flags: parts.add "53"
  parts.add colorSgrParams(s.cursor.attrs.fg, foreground = true)
  parts.add colorSgrParams(s.cursor.attrs.bg, foreground = false)
  if parts.len == 0: "0m" else: parts.join(";") & "m"

func scrollRegionReport*(s: Screen): string =
  ## Return the DECSTBM state string using 1-indexed row coordinates.
  $(s.scrollTop + 1) & ";" & $(s.scrollBottom + 1) & "r"

proc setTabStop*(s: Screen) = (if s.cursor.col < s.cols: s.tabStops[s.cursor.col] = true)
proc clearTabStop*(s: Screen) = (if s.cursor.col < s.cols: s.tabStops[s.cursor.col] = false)
proc clearAllTabStops*(s: Screen) = (for i in 0 ..< s.cols: s.tabStops[i] = false)
proc setScrollRegion*(s: Screen, t, b: int) =
  let top = max(0, min(s.rows - 1, t))
  let bottom = max(0, min(s.rows - 1, b))
  if top >= bottom:
    return
  s.scrollTop = top
  s.scrollBottom = bottom
  s.cursorTo(0, 0)
func savedState(s: Screen): SavedScreenState =
  SavedScreenState(
    cursor: s.cursor,
    g0Charset: s.g0Charset,
    g1Charset: s.g1Charset,
    activeCharset: s.activeCharset,
    modes: s.modes,
  )

proc applySavedState(s: Screen, saved: SavedScreenState) =
  s.cursor = saved.cursor
  s.cursor.pendingWrap = false
  s.g0Charset = saved.g0Charset
  s.g1Charset = saved.g1Charset
  s.activeCharset = saved.activeCharset
  s.charset = if s.activeCharset == 1: s.g1Charset else: s.g0Charset
  s.modes = saved.modes

proc saveCursor*(s: Screen) =
  if s.usingAlt:
    s.savedCursorAlt = some(s.savedState())
  else:
    s.savedCursor = some(s.savedState())

proc restoreCursor*(s: Screen) =
  let saved = if s.usingAlt: s.savedCursorAlt else: s.savedCursor
  if saved.isSome:
    s.applySavedState(saved.get())
