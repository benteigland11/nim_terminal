import terminal_resize_policy_lib

## Pane collapsed mid-drag: hold the last good 80x24 grid instead of 8x3.

let held = planTerminalResize(8, 3, 80, 24, minCols = 40, minRows = 8)
doAssert held.heldLastGood
doAssert not held.apply

## User grows the pane again: apply the new healthy size.

let grown = planTerminalResize(100, 28, 80, 24, minCols = 40, minRows = 8)
doAssert grown.apply
doAssert grown.cols == 100 and grown.rows == 28

var limit = newResizeRateLimit(0.05)
limit.noteResizeActivity()
doAssert takePending(limit)

echo "terminal-resize-policy example ok"
