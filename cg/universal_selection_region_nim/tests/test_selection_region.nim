import std/unittest
import selection_region_lib

const Cols = 10

suite "construction and lifecycle":

  test "fresh selection is inactive and empty":
    let s = newSelection()
    check s.isActive == false
    check s.isEmpty
    check s.spans(Cols).len == 0

  test "start activates with anchor == focus":
    var s = newSelection()
    s.start(point(2, 4))
    check s.isActive
    check s.anchor == point(2, 4)
    check s.focus == point(2, 4)
    check s.isEmpty                    # not yet dragged
    check s.mode == smStream

  test "update moves focus":
    var s = newSelection()
    s.start(point(1, 0))
    s.update(point(1, 5))
    check s.focus == point(1, 5)
    check s.isEmpty == false

  test "update on inactive selection is no-op":
    var s = newSelection()
    s.update(point(3, 3))
    check s.isActive == false

  test "clear resets everything":
    var s = newSelection()
    s.start(point(0, 0))
    s.update(point(2, 2))
    s.clear
    check s.isActive == false
    check s.isEmpty
    check s.spans(Cols).len == 0

suite "stream mode: single row":

  test "forward single-row drag":
    var s = newSelection()
    s.start(point(1, 2))
    s.update(point(1, 6))
    let sp = s.spans(Cols)
    check sp.len == 1
    check sp[0] == Span(row: 1, startCol: 2, endCol: 7)   # half-open

  test "backward drag normalizes":
    var s = newSelection()
    s.start(point(1, 6))
    s.update(point(1, 2))
    let sp = s.spans(Cols)
    check sp.len == 1
    check sp[0] == Span(row: 1, startCol: 2, endCol: 7)

  test "single cell drag (anchor == focus) is empty":
    var s = newSelection()
    s.start(point(0, 3))
    # no update
    check s.isEmpty
    check s.spans(Cols).len == 0

suite "stream mode: multi-row":

  test "two-row forward drag":
    var s = newSelection()
    s.start(point(0, 4))
    s.update(point(1, 2))
    let sp = s.spans(Cols)
    check sp.len == 2
    check sp[0] == Span(row: 0, startCol: 4, endCol: Cols)
    check sp[1] == Span(row: 1, startCol: 0, endCol: 3)

  test "two-row backward drag":
    var s = newSelection()
    s.start(point(2, 1))
    s.update(point(0, 8))
    let sp = s.spans(Cols)
    check sp.len == 3
    check sp[0] == Span(row: 0, startCol: 8, endCol: Cols)
    check sp[1] == Span(row: 1, startCol: 0, endCol: Cols)
    check sp[2] == Span(row: 2, startCol: 0, endCol: 2)

  test "three-row drag middle rows are full width":
    var s = newSelection()
    s.start(point(0, 3))
    s.update(point(4, 5))
    let sp = s.spans(Cols)
    check sp.len == 5
    check sp[0] == Span(row: 0, startCol: 3, endCol: Cols)
    check sp[1] == Span(row: 1, startCol: 0, endCol: Cols)
    check sp[2] == Span(row: 2, startCol: 0, endCol: Cols)
    check sp[3] == Span(row: 3, startCol: 0, endCol: Cols)
    check sp[4] == Span(row: 4, startCol: 0, endCol: 6)

suite "line mode":

  test "same-row line select covers whole row":
    var s = newSelection()
    s.start(point(2, 0), smLine)
    let sp = s.spans(Cols)
    check sp.len == 1
    check sp[0] == Span(row: 2, startCol: 0, endCol: Cols)

  test "multi-row line drag covers every row in range":
    var s = newSelection()
    s.start(point(1, 3), smLine)
    s.update(point(3, 7))
    let sp = s.spans(Cols)
    check sp.len == 3
    check sp[0] == Span(row: 1, startCol: 0, endCol: Cols)
    check sp[1] == Span(row: 2, startCol: 0, endCol: Cols)
    check sp[2] == Span(row: 3, startCol: 0, endCol: Cols)

  test "line mode ignores column fields":
    var s1, s2: Selection
    s1.start(point(0, 0), smLine); s1.update(point(2, 0))
    s2.start(point(0, 9), smLine); s2.update(point(2, 1))
    check s1.spans(Cols) == s2.spans(Cols)

  test "line mode is never empty when active":
    var s = newSelection()
    s.start(point(5, 0), smLine)
    check s.isEmpty == false

suite "block mode":

  test "block drag yields rectangular spans":
    var s = newSelection()
    s.start(point(1, 2), smBlock)
    s.update(point(3, 6))
    let sp = s.spans(Cols)
    check sp.len == 3
    check sp[0] == Span(row: 1, startCol: 2, endCol: 7)
    check sp[1] == Span(row: 2, startCol: 2, endCol: 7)
    check sp[2] == Span(row: 3, startCol: 2, endCol: 7)

  test "block backward drag normalizes both axes":
    var s = newSelection()
    s.start(point(3, 6), smBlock)
    s.update(point(1, 2))
    let sp = s.spans(Cols)
    check sp.len == 3
    check sp[0] == Span(row: 1, startCol: 2, endCol: 7)
    check sp[2] == Span(row: 3, startCol: 2, endCol: 7)

  test "block single-row horizontal span":
    var s = newSelection()
    s.start(point(1, 2), smBlock)
    s.update(point(1, 4))
    let sp = s.spans(Cols)
    check sp.len == 1
    check sp[0] == Span(row: 1, startCol: 2, endCol: 5)

suite "clamping and edge cases":

  test "cols = 0 yields no spans":
    var s = newSelection()
    s.start(point(0, 0))
    s.update(point(1, 1))
    check s.spans(0).len == 0

  test "cols <= 0 is silent":
    var s = newSelection()
    s.start(point(0, 0))
    s.update(point(2, 2))
    check s.spans(-5).len == 0

  test "focus past cols clamps to row width":
    var s = newSelection()
    s.start(point(0, 0))
    s.update(point(0, 99))
    let sp = s.spans(Cols)
    check sp.len == 1
    check sp[0] == Span(row: 0, startCol: 0, endCol: Cols)

  test "anchor past cols on multi-row still produces valid spans":
    var s = newSelection()
    s.start(point(0, 50))
    s.update(point(2, 3))
    let sp = s.spans(Cols)
    # Top-row span is empty after clamping so it's omitted; middle
    # and bottom rows remain.
    check sp.len == 2
    check sp[0] == Span(row: 1, startCol: 0, endCol: Cols)
    check sp[1] == Span(row: 2, startCol: 0, endCol: 4)

suite "contains":

  test "stream contains covers inclusive range":
    var s = newSelection()
    s.start(point(1, 2))
    s.update(point(1, 5))
    check s.contains(1, 2, Cols)
    check s.contains(1, 5, Cols)
    check s.contains(1, 1, Cols) == false
    check s.contains(1, 6, Cols) == false
    check s.contains(0, 3, Cols) == false

  test "block contains":
    var s = newSelection()
    s.start(point(1, 2), smBlock)
    s.update(point(3, 4))
    check s.contains(2, 3, Cols)
    check s.contains(1, 2, Cols)
    check s.contains(3, 4, Cols)
    check s.contains(0, 3, Cols) == false
    check s.contains(2, 5, Cols) == false

  test "inactive contains returns false":
    let s = newSelection()
    check s.contains(0, 0, Cols) == false

  test "out-of-range col rejected":
    var s = newSelection()
    s.start(point(0, 0), smLine)
    s.update(point(0, 0))
    check s.contains(0, -1, Cols) == false
    check s.contains(0, Cols, Cols) == false

suite "rowRange and normalized":

  test "rowRange on inactive is inverted":
    let s = newSelection()
    let (lo, hi) = s.rowRange
    check hi < lo

  test "rowRange returns sorted bounds":
    var s = newSelection()
    s.start(point(4, 0))
    s.update(point(1, 0))
    check s.rowRange == (1, 4)

  test "normalized orders by row-major":
    var s = newSelection()
    s.start(point(2, 3))
    s.update(point(2, 1))
    let (top, bot) = s.normalized
    check top == point(2, 1)
    check bot == point(2, 3)

  test "normalized handles cross-row":
    var s = newSelection()
    s.start(point(2, 9))
    s.update(point(1, 0))
    let (top, bot) = s.normalized
    check top == point(1, 0)
    check bot == point(2, 9)
