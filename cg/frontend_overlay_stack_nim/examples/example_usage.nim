## Example usage of Overlay Stack.

import overlay_stack_lib

let stack = newOverlayStack()
stack.overlayPushModal(
  "demo",
  OverlayPanel(
    title: "Replace file?",
    body: "An item named example.txt already exists in this folder.",
    buttons: @[
      OverlayButton(label: "Cancel", actionId: "cancel"),
      OverlayButton(label: "Replace", actionId: "confirm", primary: true),
    ],
  ),
)
let layout = computeModalChromeLayout(
  OverlayRect(x: 0, y: 0, w: 640, h: 480),
  overlayTop(stack).panel,
  defaultModalChromeMetrics(cellWidth = 8, cellHeight = 14),
)
doAssert layout.buttons.len == 2
doAssert overlayCapturesInput(stack)
discard overlayDismissTop(stack)
doAssert overlayIsEmpty(stack)
