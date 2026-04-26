import std/unittest
import ../src/viewport_lib

suite "universal viewport":

  test "initial state (pinned to bottom)":
    let v = newViewport(24)
    check v.height == 24
    check v.totalRows == 24
    check v.scrollOffset == 0
    check v.isAtBottom == true
    check v.viewportToBuffer(0) == 0
    check v.viewportToBuffer(23) == 23

  test "scrolling up into history":
    var v = newViewport(24)
    v.updateBufferHeight(100)
    v.scrollUp(10)
    check v.scrollOffset == 10
    check v.isAtBottom == false
    
    # Bottom row of viewport (index 23) should be buffer row 89
    # (100 - 1) - 10 = 89
    check v.viewportToBuffer(23) == 89
    # Top row (index 0) should be 89 - 23 = 66
    check v.viewportToBuffer(0) == 66

  test "stick to bottom behavior":
    var v = newViewport(24)
    v.updateBufferHeight(50)
    check v.isAtBottom == true
    v.updateBufferHeight(60, stickToBottom = true)
    check v.isAtBottom == true
    check v.scrollOffset == 0

  test "clamping":
    var v = newViewport(24)
    v.updateBufferHeight(30)
    v.scrollUp(100) # way past history
    check v.scrollOffset == 6 # capped at 30-24
    v.scrollDown(100)
    check v.scrollOffset == 0 # capped at 0

  test "capture and restore anchor preserves top when target stays visible":
    var v = newViewport(10)
    v.updateBufferHeight(100)
    v.scrollUp(20)
    let anchor = v.captureAnchor(75)
    v.restoreAnchor(totalRows = 100, height = 6, anchor = anchor, contextRowsAbove = 2)
    check v.viewportToBuffer(0) == anchor.topRow
    check v.bufferToViewport(75) >= 0

  test "restore anchor keeps context above target when top would hide it":
    var v = newViewport(10)
    v.updateBufferHeight(100)
    v.scrollUp(20)
    let anchor = v.captureAnchor(89)
    v.restoreAnchor(totalRows = 100, height = 4, anchor = anchor, contextRowsAbove = 2)
    check v.viewportToBuffer(0) == 87
    check v.bufferToViewport(89) == 2

  test "bottom anchor remains pinned to bottom":
    var v = newViewport(10)
    v.updateBufferHeight(100)
    let anchor = v.captureAnchor(99)
    v.restoreAnchor(totalRows = 120, height = 8, anchor = anchor, contextRowsAbove = 2)
    check v.isAtBottom

  test "resize anchor keeps visible cursor visible without forcing bottom pin":
    var v = newViewport(10)
    v.updateBufferHeight(100)
    let anchor = v.captureResizeAnchor(95)
    v.restoreAnchor(totalRows = 100, height = 6, anchor = anchor, contextRowsAbove = 2, pinBottom = false)
    check v.bufferToViewport(95) >= 0
    check v.isAtBottom == false

  test "resize anchor preserves top row when target is not visible":
    var v = newViewport(10)
    v.updateBufferHeight(100)
    v.scrollUp(40)
    let top = v.viewportToBuffer(0)
    let anchor = v.captureResizeAnchor(99)
    check anchor.targetRow == -1
    v.restoreAnchor(totalRows = 100, height = 6, anchor = anchor, contextRowsAbove = 2, pinBottom = false)
    check v.viewportToBuffer(0) == top

  test "ensureVisible scrolls only when target is outside the viewport":
    var v = newViewport(5)
    v.updateBufferHeight(20)
    v.scrollUp(10)
    let originalTop = v.viewportToBuffer(0)

    v.ensureVisible(originalTop + 2, 1)
    check v.viewportToBuffer(0) == originalTop

    v.ensureVisible(19, 2)
    check v.bufferToViewport(19) != -1
    check v.viewportToBuffer(0) == 15
