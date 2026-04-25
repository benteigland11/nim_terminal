import std/unittest
import ../src/drag_controller_lib

suite "drag controller":

  test "start and end drag":
    var c = newDragController(24)
    check c.state == dsIdle
    
    # Mouse down at (5, 10)
    c.update(5, 10, true)
    check c.state == dsActive
    check c.startY == 5
    check c.startX == 10
    
    # Mouse release
    c.update(5, 10, false)
    check c.state == dsIdle

  test "auto-scroll signaling":
    var c = newDragController(24)
    c.update(10, 10, true)
    check c.state == dsActive
    
    # Drag below viewport
    c.update(25, 10, true)
    check c.state == dsOutsideBottom
    
    # Drag above viewport
    c.update(-1, 10, true)
    check c.state == dsOutsideTop
