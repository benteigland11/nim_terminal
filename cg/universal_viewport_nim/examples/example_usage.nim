## Example usage of Viewport.

import viewport_lib

# View 10 lines of a 100-line buffer
var v = newViewport(10)
v.updateBufferHeight(100)

# Scroll up into history
v.scrollUp(50)
doAssert v.scrollOffset == 50

# Map a viewport row to absolute buffer row
let absoluteRow = v.viewportToBuffer(0)
# Bottom is 99, scrolled up 50 -> viewport bottom is 49
# Viewport is 10 high -> viewport top is 40
doAssert absoluteRow == 40

# Stay pinned to bottom when data arrives
v.scrollToBottom()
v.updateBufferHeight(110, stickToBottom = true)
doAssert v.isAtBottom == true

echo "All viewport examples passed."
