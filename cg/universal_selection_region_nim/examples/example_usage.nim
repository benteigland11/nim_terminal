## Simulate a user dragging a selection across a 10-column grid and
## pulling text out of it. The grid content lives on the caller side;
## the selection widget only yields the half-open spans.

import selection_region_lib

# Imagine a 4-row grid whose rows look like this (padded to 10 cols):
let grid = @[
  "hello world",   # row 0
  "the quick ",    # row 1
  "brown fox ",    # row 2
  "jumps over",    # row 3
]
const Cols = 10

# Extract the characters inside the given half-open spans from our
# fake grid. Rows shorter than the span get the available prefix —
# this mirrors how a real terminal would walk its cell buffer.
proc extract(spans: seq[Span]): string =
  for sp in spans:
    let line = grid[sp.row]
    let lo = min(sp.startCol, line.len)
    let hi = min(sp.endCol, line.len)
    if lo < hi: result.add line[lo ..< hi]
    if sp.row != spans[^1].row: result.add '\n'

# -- Stream selection: click on 'q' in row 1, drag to 'x' in row 2. ---
var sel = newSelection()
sel.start(point(1, 4))      # 'q' in "the quick"
sel.update(point(2, 8))     # 'x' in "brown fox"

doAssert sel.isActive
doAssert sel.spans(Cols).len == 2
let streamText = extract(sel.spans(Cols))
doAssert streamText == "quick \nbrown fox"

# -- Line selection: select rows 0..2 entirely (triple-click + drag). -
sel.clear
sel.start(point(0, 0), smLine)
sel.update(point(2, 0))

let lineSpans = sel.spans(Cols)
doAssert lineSpans.len == 3
doAssert lineSpans[0] == Span(row: 0, startCol: 0, endCol: Cols)
doAssert lineSpans[2] == Span(row: 2, startCol: 0, endCol: Cols)

# -- Block selection: rectangular pull of columns 2..5 across rows 1..3
sel.clear
sel.start(point(1, 2), smBlock)
sel.update(point(3, 5))

let blockSpans = sel.spans(Cols)
doAssert blockSpans.len == 3
for sp in blockSpans:
  doAssert sp.startCol == 2
  doAssert sp.endCol == 6      # inclusive col 5 → exclusive 6

# -- Hit-testing for rendering highlights. ----------------------------
doAssert sel.contains(2, 4, Cols)       # inside
doAssert sel.contains(2, 6, Cols) == false   # just past
doAssert sel.contains(0, 2, Cols) == false   # wrong row

# -- Clearing restores inactive state. --------------------------------
sel.clear
doAssert sel.isActive == false
doAssert sel.spans(Cols).len == 0
