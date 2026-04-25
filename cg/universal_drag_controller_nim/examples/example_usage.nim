## Example usage of Drag Controller.

import drag_controller_lib

# 1. Setup a controller for a 24-row viewport
var c = newDragController(24)

# 2. Update on mouse movement
# User clicks at row 5, col 10
c.update(5, 10, true)
doAssert c.state == dsActive
doAssert c.startY == 5

# User drags to row 10, col 20
c.update(10, 20, true)
doAssert c.currY == 10
doAssert c.currX == 20

# User drags below the window -> Auto-scroll signaled
c.update(25, 20, true)
doAssert c.state == dsOutsideBottom

# 3. Handle auto-scroll in your main loop
if c.state == dsOutsideBottom:
  echo "Main loop should scroll down now!"

# 4. End drag on mouse release
c.update(10, 20, false)
doAssert c.state == dsIdle

echo "Drag controller example verified."
