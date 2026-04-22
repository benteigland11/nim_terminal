import std/unittest
import damage_tracker_lib

suite "construction":

  test "fresh tracker has requested size and no damage":
    let d = newDamage(10)
    check d.size == 10
    check d.anyDirty == false
    check d.fullRepaint == false
    check d.dirtyRows.len == 0

  test "negative size clamps to zero":
    let d = newDamage(-5)
    check d.size == 0
    check d.anyDirty == false

  test "zero size is valid and silent":
    var d = newDamage(0)
    d.markRow(0)
    d.markRows(0, 10)
    d.markAll
    check d.anyDirty == false
    check d.dirtyRows.len == 0

suite "single-index marking":

  test "markRow flags exactly that index":
    var d = newDamage(5)
    d.markRow(2)
    check d.isDirty(2)
    check d.isDirty(1) == false
    check d.isDirty(3) == false
    check d.dirtyRows == @[2]

  test "out-of-range markRow is silently ignored":
    var d = newDamage(3)
    d.markRow(-1)
    d.markRow(3)
    d.markRow(100)
    check d.anyDirty == false

  test "marking same index twice is idempotent":
    var d = newDamage(4)
    d.markRow(1)
    d.markRow(1)
    check d.dirtyRows == @[1]

suite "range marking":

  test "markRows covers inclusive range":
    var d = newDamage(6)
    d.markRows(1, 3)
    check d.dirtyRows == @[1, 2, 3]

  test "markRows clamps overlapping range":
    var d = newDamage(5)
    d.markRows(-2, 2)
    check d.dirtyRows == @[0, 1, 2]

  test "markRows clamps overflow":
    var d = newDamage(5)
    d.markRows(3, 99)
    check d.dirtyRows == @[3, 4]

  test "markRows inverted range is a no-op":
    var d = newDamage(5)
    d.markRows(3, 1)
    check d.anyDirty == false

  test "markRows fully outside is a no-op":
    var d = newDamage(5)
    d.markRows(10, 20)
    d.markRows(-10, -1)
    check d.anyDirty == false

  test "single-index range works":
    var d = newDamage(5)
    d.markRows(2, 2)
    check d.dirtyRows == @[2]

suite "markAll":

  test "markAll dirties every index":
    var d = newDamage(4)
    d.markAll
    check d.dirtyRows == @[0, 1, 2, 3]

  test "markAll sets fullRepaint":
    var d = newDamage(4)
    d.markAll
    check d.fullRepaint

  test "markAll on zero-size stays silent":
    # Empty tracker: nothing to paint, so markAll is a no-op (including
    # the fullRepaint flag — we don't want a renderer to be signaled
    # to repaint an empty range).
    var d = newDamage(0)
    d.markAll
    check d.fullRepaint == false
    check d.anyDirty == false

suite "clear":

  test "clear wipes marks":
    var d = newDamage(4)
    d.markRow(0)
    d.markRow(3)
    d.clear
    check d.anyDirty == false
    check d.dirtyRows.len == 0

  test "clear wipes fullRepaint":
    var d = newDamage(4)
    d.markAll
    d.clear
    check d.fullRepaint == false
    check d.anyDirty == false

  test "clear on clean tracker is idempotent":
    var d = newDamage(4)
    d.clear
    d.clear
    check d.anyDirty == false

suite "resize":

  test "resize grows and marks everything dirty":
    var d = newDamage(3)
    d.resize(7)
    check d.size == 7
    check d.dirtyRows == @[0, 1, 2, 3, 4, 5, 6]
    check d.fullRepaint

  test "resize shrinks and marks survivors dirty":
    var d = newDamage(10)
    d.resize(3)
    check d.size == 3
    check d.dirtyRows == @[0, 1, 2]
    check d.fullRepaint

  test "resize to zero collapses and dirties nothing":
    var d = newDamage(5)
    d.resize(0)
    check d.size == 0
    check d.fullRepaint
    check d.dirtyRows.len == 0

  test "resize negative clamps to zero":
    var d = newDamage(5)
    d.resize(-2)
    check d.size == 0

  test "resize drops stale marks":
    var d = newDamage(5)
    d.markRow(4)
    d.resize(3)
    # Post-resize, every surviving index is dirty by fullRepaint
    # semantics; we don't need to verify "index 4 is not dirty" —
    # it no longer exists.
    check d.size == 3
    check d.dirtyRows == @[0, 1, 2]

suite "query helpers":

  test "isDirty out of range returns false, never throws":
    let d = newDamage(3)
    check d.isDirty(-1) == false
    check d.isDirty(3) == false
    check d.isDirty(999) == false

  test "dirtyRows returns empty on clean tracker":
    let d = newDamage(5)
    check d.dirtyRows.len == 0

  test "dirtyRows is sorted ascending":
    var d = newDamage(6)
    d.markRow(4)
    d.markRow(1)
    d.markRow(5)
    d.markRow(0)
    check d.dirtyRows == @[0, 1, 4, 5]

  test "anyDirty short-circuits on fullRepaint":
    var d = newDamage(3)
    d.markAll
    # Even after clearing the dirty bits manually we shouldn't be able
    # to — full is the authority for repaint intent.
    check d.anyDirty

suite "typical render-loop sequence":

  test "mark/query/clear cycle works across two frames":
    var d = newDamage(5)

    # Frame 1: caller marks rows 1 and 3.
    d.markRow(1)
    d.markRow(3)
    check d.dirtyRows == @[1, 3]

    # Renderer paints and clears.
    d.clear
    check d.anyDirty == false

    # Frame 2: caller marks a range.
    d.markRows(0, 2)
    check d.dirtyRows == @[0, 1, 2]
    check d.fullRepaint == false

  test "scroll-style event: markAll then clear":
    var d = newDamage(5)
    d.markAll
    check d.fullRepaint
    d.clear
    check d.fullRepaint == false
    check d.anyDirty == false

  test "resize mid-session still usable":
    var d = newDamage(3)
    d.markRow(0)
    d.resize(6)
    d.clear
    d.markRow(5)
    check d.dirtyRows == @[5]
