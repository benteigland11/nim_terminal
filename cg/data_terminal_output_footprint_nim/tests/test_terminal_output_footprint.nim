import std/unittest
import terminal_output_footprint_lib

suite "Terminal output footprint":
  test "records lowest touched row":
    var f = newOutputFootprint()
    f.recordRow(2)
    f.recordRows(1, 4)
    f.recordRow(3)
    check f.bottomRow == 4

  test "does not track alternate screen rows":
    var f = newOutputFootprint()
    f.recordRow(5, activeAlternate = true)
    check f.bottomRow == -1

  test "arms after cursor restore above footprint":
    var f = newOutputFootprint()
    f.markFullDisplayErase()
    f.recordRows(2, 4)
    f.armAfterCursorRestore(cursorRow = 1)
    check f.isArmed

  test "does not arm after cursor restore without full display erase":
    var f = newOutputFootprint()
    f.recordRows(2, 4)
    f.armAfterCursorRestore(cursorRow = 1)
    check not f.isArmed

  test "does not arm after cursor restore below footprint":
    var f = newOutputFootprint()
    f.markFullDisplayErase()
    f.recordRows(2, 4)
    f.armAfterCursorRestore(cursorRow = 5)
    check not f.isArmed

  test "resume moves to row below footprint":
    var f = newOutputFootprint()
    f.markFullDisplayErase()
    f.recordRows(2, 4)
    f.armAfterCursorRestore(cursorRow = 1)
    let action = f.consumeResume(cursorRow = 1, screenRows = 10)
    check action.shouldMove
    check action.targetRow == 5
    check action.scrollCount == 0
    check f.bottomRow == -1
    check not f.isArmed

  test "resume scrolls when footprint reaches bottom":
    var f = newOutputFootprint()
    f.markFullDisplayErase()
    f.recordRow(5)
    f.armAfterCursorRestore(cursorRow = 1)
    let action = f.consumeResume(cursorRow = 1, screenRows = 6)
    check action.shouldMove
    check action.targetRow == 5
    check action.scrollCount == 1

  test "force consumes without armed cursor restore":
    var f = newOutputFootprint()
    f.recordRow(3)
    let action = f.consumeResume(cursorRow = 1, screenRows = 10, force = true)
    check action.shouldMove
    check action.targetRow == 4

  test "unarmed resume is ignored":
    var f = newOutputFootprint()
    f.recordRow(3)
    let action = f.consumeResume(cursorRow = 1, screenRows = 10)
    check not action.shouldMove
    check f.bottomRow == 3
