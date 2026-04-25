## Example usage of Terminal Output Footprint.

import terminal_output_footprint_lib

var footprint = newOutputFootprint()
footprint.recordRows(2, 4)
footprint.armAfterCursorRestore(cursorRow = 1)

let action = footprint.consumeResume(cursorRow = 1, screenRows = 10)
doAssert action.shouldMove
doAssert action.targetRow == 5
doAssert action.scrollCount == 0
