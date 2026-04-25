## Pure geometric selection over a (row, col) grid. The widget tracks
## an anchor and a focus point plus a mode, and exposes the covered
## region as a sequence of half-open row spans `[startCol, endCol)`.
##
## Three modes:
##
## * `smStream` — character-linearized across rows. Start at the anchor,
##   sweep to the focus as if reading left-to-right top-to-bottom. Top
##   row covers [startCol, cols); middle rows are full [0, cols);
##   bottom row covers [0, endCol+1). Single-row selections are one
##   span, ends normalized so startCol <= endCol.
## * `smLine` — whole rows between min(anchor.row, focus.row) and
##   max(anchor.row, focus.row), inclusive. Column fields ignored.
## * `smBlock` — rectangular region; each row spans the same
##   [min(anchor.col, focus.col), max+1) window.
##
## The widget never sees grid content. Callers that want text
## extraction walk `spans` against their own storage; callers that
## want word-level selection pre-snap anchor/focus to word edges and
## use `smStream`.
##
## Coordinates are zero-based. `cols` is the grid width; selections
## are clamped into [0, cols) defensively on each query.

type
  SelectionMode* = enum
    smStream
    smLine
    smBlock

  Point* = object
    row*: int
    col*: int

  Selection* = object
    anchor: Point
    focus:  Point
    mode:   SelectionMode
    live:   bool

  Span* = object
    row*:      int
    startCol*: int   # inclusive
    endCol*:   int   # exclusive

func point*(row, col: int): Point = Point(row: row, col: col)

func newSelection*(): Selection =
  ## Empty, inactive selection.
  Selection(live: false)

func start*(s: var Selection, anchor: Point, mode: SelectionMode = smStream) =
  ## Begin a new selection at `anchor`. The focus starts at the same
  ## point — an un-dragged click selects nothing until `update` moves
  ## the focus.
  s.anchor = anchor
  s.focus  = anchor
  s.mode   = mode
  s.live   = true

func update*(s: var Selection, focus: Point) =
  ## Move the focus (drag). No-op if the selection isn't active.
  if not s.live: return
  s.focus = focus

func clear*(s: var Selection) =
  ## Dismiss the selection.
  s.live = false
  s.anchor = Point()
  s.focus  = Point()

func isActive*(s: Selection): bool = s.live

func anchor*(s: Selection): Point = s.anchor
func focus*(s: Selection): Point  = s.focus
func mode*(s: Selection): SelectionMode = s.mode

func isEmpty*(s: Selection): bool =
  ## True if the selection covers no cells. An inactive selection is
  ## always empty; an active selection is empty only in smStream /
  ## smBlock when anchor == focus.
  if not s.live: return true
  case s.mode
  of smStream, smBlock:
    s.anchor.row == s.focus.row and s.anchor.col == s.focus.col
  of smLine:
    false   # smLine always covers at least one full row

func normalized*(s: Selection): (Point, Point) =
  ## Return (topLeft, bottomRight) of the bounding box. For smStream
  ## and smLine the "bottomRight" column reflects the focus/anchor
  ## pair ordering, not the actual right edge of the last row. Use
  ## `spans` for a rendering-ready decomposition.
  let a = s.anchor
  let f = s.focus
  if (a.row < f.row) or (a.row == f.row and a.col <= f.col):
    (a, f)
  else:
    (f, a)

func minMax(a, b: int): (int, int) =
  if a <= b: (a, b) else: (b, a)

func clampSpan(startCol, endCol, cols: int): (int, int) =
  ## Clamp a half-open span into [0, cols]. Returns (0, 0) if the
  ## clamped span is empty.
  let s = max(0, startCol)
  let e = min(cols, endCol)
  if s >= e: (0, 0) else: (s, e)

func spans*(s: Selection, cols: int): seq[Span] =
  ## Decompose the selection into per-row half-open spans, clamped to
  ## `cols`. Empty or inactive selections return an empty seq.
  if not s.live or cols <= 0: return
  if s.isEmpty: return

  case s.mode
  of smStream:
    let (top, bot) = s.normalized
    if top.row == bot.row:
      let (lo, hi) = minMax(top.col, bot.col)
      # Single-row stream: inclusive on both ends, convert to half-open.
      let (a, b) = clampSpan(lo, hi + 1, cols)
      if a < b: result.add Span(row: top.row, startCol: a, endCol: b)
    else:
      # Top row: from top.col to end of row.
      block:
        let (a, b) = clampSpan(top.col, cols, cols)
        if a < b: result.add Span(row: top.row, startCol: a, endCol: b)
      # Middle rows: entire width.
      for r in (top.row + 1) ..< bot.row:
        let (a, b) = clampSpan(0, cols, cols)
        if a < b: result.add Span(row: r, startCol: a, endCol: b)
      # Bottom row: 0 through bot.col (inclusive) → [0, bot.col+1).
      block:
        let (a, b) = clampSpan(0, bot.col + 1, cols)
        if a < b: result.add Span(row: bot.row, startCol: a, endCol: b)

  of smLine:
    let (lo, hi) = minMax(s.anchor.row, s.focus.row)
    for r in lo .. hi:
      let (a, b) = clampSpan(0, cols, cols)
      if a < b: result.add Span(row: r, startCol: a, endCol: b)

  of smBlock:
    let (loR, hiR) = minMax(s.anchor.row, s.focus.row)
    let (loC, hiC) = minMax(s.anchor.col, s.focus.col)
    let (a, b) = clampSpan(loC, hiC + 1, cols)
    if a < b:
      for r in loR .. hiR:
        result.add Span(row: r, startCol: a, endCol: b)

func contains*(s: Selection, row, col, cols: int): bool =
  ## Hit-test a single cell. `cols` is the grid width and must match
  ## what's passed to `spans` for consistent results.
  if not s.live or cols <= 0: return false
  if col < 0 or col >= cols: return false
  for sp in s.spans(cols):
    if sp.row == row and col >= sp.startCol and col < sp.endCol:
      return true
  false

func rowRange*(s: Selection): (int, int) =
  ## Inclusive (minRow, maxRow) of the bounding box, or (0, -1) if
  ## inactive/empty — callers can cheaply test `hi < lo` for "no rows."
  if not s.live or s.isEmpty: return (0, -1)
  minMax(s.anchor.row, s.focus.row)

type
  CellData* = object
    rune*: uint32
    width*: int

  RowAccessCallback* = proc(row: int): seq[CellData] {.closure.}

import std/unicode

proc extractText*(s: Selection, cols: int, getRow: RowAccessCallback): string =
  ## Extract text from the selection using a row-access callback.
  ## Corrects for newlines between rows.
  if not s.live or s.isEmpty: return ""
  
  let allSpans = s.spans(cols)
  if allSpans.len == 0: return ""
  
  result = ""
  var lastRow = allSpans[0].row
  
  for sp in allSpans:
    if sp.row > lastRow:
      result.add "\n"
    
    let cells = getRow(sp.row)
    if cells.len == 0: continue
    
    for c in sp.startCol ..< min(sp.endCol, cells.len):
      let cell = cells[c]
      if cell.width > 0: # Skip continuation cells
        result.add Rune(cell.rune)
    lastRow = sp.row

