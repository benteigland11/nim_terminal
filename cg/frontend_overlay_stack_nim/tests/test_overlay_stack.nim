import std/unittest
import overlay_stack_lib

suite "overlay stack":
  test "push and dismiss modal layers":
    let stack = newOverlayStack()
    check overlayIsEmpty(stack)
    stack.overlayPushModal(
      "one",
      OverlayPanel(title: "Title", body: "Body", buttons: @[]),
    )
    check not overlayIsEmpty(stack)
    check overlayTop(stack).id == "one"
    check overlayDismissTop(stack)
    check overlayIsEmpty(stack)

  test "computeModalChromeLayout centers panel and buttons":
    let bounds = OverlayRect(x: 0, y: 32, w: 800, h: 600)
    let panel = OverlayPanel(
      title: "Validate widget",
      body: "Run validation on backend-foo-python?",
      buttons: @[
        OverlayButton(label: "Cancel", actionId: "cancel"),
        OverlayButton(label: "Validate", actionId: "confirm", primary: true),
      ],
    )
    let metrics = defaultModalChromeMetrics(cellWidth = 8, cellHeight = 14)
    let layout = computeModalChromeLayout(bounds, panel, metrics)
    check layout.panel.w >= metrics.minPanelWidth
    check layout.panel.x + layout.panel.w <= bounds.x + bounds.w
    check layout.buttons.len == 2
    check layout.buttonActionIds[^1] == "confirm"
    check layout.buttons[^1].x + layout.buttons[^1].w <= layout.panel.x + layout.panel.w - metrics.pad

  test "overlayHitTestModal resolves backdrop and buttons":
    let bounds = OverlayRect(x: 0, y: 0, w: 400, h: 300)
    let panel = OverlayPanel(
      title: "Confirm",
      body: "Proceed?",
      buttons: @[OverlayButton(label: "OK", actionId: "ok")],
    )
    let layout = computeModalChromeLayout(bounds, panel, defaultModalChromeMetrics(8, 14))
    let backdrop = overlayHitTestModal(layout, 1, 1, dismissOnBackdrop = true)
    check backdrop.kind == ohBackdrop
    let btn = layout.buttons[0]
    let buttonHit = overlayHitTestModal(layout, btn.x + 2, btn.y + 2, dismissOnBackdrop = true)
    check buttonHit.kind == ohButton
    check buttonHit.actionId == "ok"

  test "computeExplorerChromeLayout splits tree and code panes":
    let bounds = OverlayRect(x: 0, y: 32, w: 900, h: 700)
    let metrics = defaultExplorerChromeMetrics(cellWidth = 8, cellHeight = 14)
    let layout = computeExplorerChromeLayout(bounds, "Inspect: sample", metrics)
    check layout.panel.w >= metrics.minPanelWidth
    check layout.treePane.w > 0
    check layout.codePane.w > 0
    check layout.treePane.x + layout.treePane.w + metrics.pad <= layout.codePane.x

  test "overlayHitTestExplorer resolves backdrop":
    let bounds = OverlayRect(x: 0, y: 0, w: 500, h: 400)
    let layout = computeExplorerChromeLayout(bounds, "Inspect", defaultExplorerChromeMetrics(8, 14))
    let hit = overlayHitTestExplorer(layout, 2, 2, dismissOnBackdrop = true)
    check hit.kind == ohBackdrop
