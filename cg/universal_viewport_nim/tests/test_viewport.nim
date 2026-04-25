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
