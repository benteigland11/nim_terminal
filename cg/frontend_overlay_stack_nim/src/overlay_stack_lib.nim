## Transient overlay stack for modal dialogs and anchored popups.
##
## Pure state and layout: push/pop layers, compute panel geometry, and
## resolve pointer hits. Rendering and action dispatch stay in the host.

import std/[strutils, unicode]

type
  OverlayRect* = object
    x*, y*, w*, h*: int

  OverlayButton* = object
    label*: string
    actionId*: string
    primary*: bool

  OverlayPanel* = object
    title*: string
    body*: string
    buttons*: seq[OverlayButton]

  OverlayKind* = enum
    okConfirm
    okExplorer

  OverlayLayer* = object
    id*: string
    kind*: OverlayKind
    panel*: OverlayPanel
    title*: string
    dismissOnBackdrop*: bool
    dismissOnEscape*: bool

  OverlayStack* = ref object
    layers*: seq[OverlayLayer]

  OverlayHitKind* = enum
    ohNone
    ohBackdrop
    ohButton
    ohPanel

  OverlayHit* = object
    kind*: OverlayHitKind
    buttonIndex*: int
    actionId*: string

  ModalChromeMetrics* = object
    cellWidth*, cellHeight*: int
    pad*, buttonPadX*, buttonPadY*, buttonGap*: int
    margin*, minPanelWidth*, maxPanelWidth*: int
    titleBodyGap*, bodyButtonGap*: int

  ModalChromeLayout* = object
    backdrop*, panel*: OverlayRect
    titleY*, bodyY*, buttonY*: int
    bodyCols*, titleCols*: int
    buttons*: seq[OverlayRect]
    buttonActionIds*: seq[string]

  ExplorerChromeLayout* = object
    backdrop*, panel*: OverlayRect
    titleY*: int
    titleCols*: int
    treePane*, codePane*: OverlayRect

func defaultModalChromeMetrics*(cellWidth, cellHeight: int): ModalChromeMetrics =
  ModalChromeMetrics(
    cellWidth: max(1, cellWidth),
    cellHeight: max(1, cellHeight),
    pad: 16,
    buttonPadX: 12,
    buttonPadY: 6,
    buttonGap: 8,
    margin: 24,
    minPanelWidth: 280,
    maxPanelWidth: 480,
    titleBodyGap: 10,
    bodyButtonGap: 16,
  )

func defaultExplorerChromeMetrics*(cellWidth, cellHeight: int): ModalChromeMetrics =
  ModalChromeMetrics(
    cellWidth: max(1, cellWidth),
    cellHeight: max(1, cellHeight),
    pad: 14,
    buttonPadX: 12,
    buttonPadY: 6,
    buttonGap: 8,
    margin: 20,
    minPanelWidth: 640,
    maxPanelWidth: 1100,
    titleBodyGap: 10,
    bodyButtonGap: 0,
  )

func newOverlayStack*(): OverlayStack =
  OverlayStack(layers: @[])

func overlayIsEmpty*(stack: OverlayStack): bool =
  stack == nil or stack.layers.len == 0

func overlayCapturesInput*(stack: OverlayStack): bool =
  not overlayIsEmpty(stack)

func overlayTop*(stack: OverlayStack): OverlayLayer =
  if overlayIsEmpty(stack):
    OverlayLayer()
  else:
    stack.layers[^1]

proc overlayPushModal*(
  stack: OverlayStack;
  id: string;
  panel: OverlayPanel;
  dismissOnBackdrop = true;
  dismissOnEscape = true,
) =
  if stack == nil:
    return
  stack.layers.add OverlayLayer(
    id: id,
    kind: okConfirm,
    panel: panel,
    title: panel.title,
    dismissOnBackdrop: dismissOnBackdrop,
    dismissOnEscape: dismissOnEscape,
  )

proc overlayPushExplorer*(
  stack: OverlayStack;
  id: string;
  title: string;
  dismissOnBackdrop = true;
  dismissOnEscape = true,
) =
  if stack == nil:
    return
  stack.layers.add OverlayLayer(
    id: id,
    kind: okExplorer,
    title: title,
    dismissOnBackdrop: dismissOnBackdrop,
    dismissOnEscape: dismissOnEscape,
  )

proc overlayDismissTop*(stack: OverlayStack): bool =
  if overlayIsEmpty(stack):
    false
  else:
    stack.layers.setLen(stack.layers.len - 1)
    true

proc overlayClear*(stack: OverlayStack) =
  if stack != nil:
    stack.layers.setLen(0)

func pointInOverlayRect*(rect: OverlayRect; x, y: int): bool =
  rect.w > 0 and rect.h > 0 and
    x >= rect.x and x < rect.x + rect.w and
    y >= rect.y and y < rect.y + rect.h

func fitOverlayTextColumns*(contentWidth, cellWidth: int): int =
  if cellWidth <= 0:
    1
  else:
    max(1, contentWidth div cellWidth)

func estimateWrappedLines*(text: string; cols: int): int =
  if text.len == 0:
    1
  elif cols <= 0:
    1
  else:
    var lines = 0
    for paragraph in text.split('\n'):
      if paragraph.len == 0:
        inc lines
        continue
      var lineCols = 0
      for word in strutils.splitWhitespace(paragraph):
        let wordLen = runeLen(word)
        if lineCols == 0:
          lineCols = wordLen
        elif lineCols + 1 + wordLen <= cols:
          lineCols += 1 + wordLen
        else:
          inc lines
          lineCols = wordLen
      inc lines
    max(1, lines)

func buttonPixelWidth*(cellWidth: int; label: string; padX: int): int =
  runeLen(label) * max(1, cellWidth) + padX * 2

func computeModalChromeLayout*(
  bounds: OverlayRect;
  panel: OverlayPanel;
  metrics: ModalChromeMetrics;
): ModalChromeLayout =
  result.backdrop = bounds
  if bounds.w <= 0 or bounds.h <= 0:
    return
  let innerW = max(
    metrics.minPanelWidth,
    min(metrics.maxPanelWidth, bounds.w - metrics.margin * 2),
  )
  let textW = max(1, innerW - metrics.pad * 2)
  let bodyCols = fitOverlayTextColumns(textW, metrics.cellWidth)
  let titleCols = bodyCols
  let titleLines = if panel.title.len > 0: 1 else: 0
  let bodyLines = estimateWrappedLines(panel.body, bodyCols)
  let buttonH =
    if panel.buttons.len == 0:
      0
    else:
      metrics.cellHeight + metrics.buttonPadY * 2
  var buttonsW = 0
  if panel.buttons.len > 0:
    buttonsW = metrics.buttonGap * (panel.buttons.len - 1)
    for btn in panel.buttons:
      buttonsW += buttonPixelWidth(metrics.cellWidth, btn.label, metrics.buttonPadX)
  let contentH =
    titleLines * metrics.cellHeight +
    (if titleLines > 0 and bodyLines > 0: metrics.titleBodyGap else: 0) +
    bodyLines * metrics.cellHeight +
    (if buttonH > 0: metrics.bodyButtonGap + buttonH else: 0)
  let panelH = metrics.pad * 2 + contentH
  let panelW = innerW
  let panelX = bounds.x + max(0, (bounds.w - panelW) div 2)
  let panelY = bounds.y + max(0, (bounds.h - panelH) div 2)
  result.panel = OverlayRect(x: panelX, y: panelY, w: panelW, h: panelH)
  result.titleCols = titleCols
  result.bodyCols = bodyCols
  result.titleY = panelY + metrics.pad
  result.bodyY =
    result.titleY +
    titleLines * metrics.cellHeight +
    (if titleLines > 0 and bodyLines > 0: metrics.titleBodyGap else: 0)
  result.buttonY = panelY + panelH - metrics.pad - buttonH
  if panel.buttons.len > 0:
    var btnX = panelX + panelW - metrics.pad - buttonsW
    for btn in panel.buttons:
      let btnW = buttonPixelWidth(metrics.cellWidth, btn.label, metrics.buttonPadX)
      result.buttons.add OverlayRect(x: btnX, y: result.buttonY, w: btnW, h: buttonH)
      result.buttonActionIds.add btn.actionId
      btnX += btnW + metrics.buttonGap

func computeExplorerChromeLayout*(
  bounds: OverlayRect;
  title: string;
  metrics: ModalChromeMetrics;
): ExplorerChromeLayout =
  result.backdrop = bounds
  if bounds.w <= 0 or bounds.h <= 0:
    return
  let panelW = max(
    metrics.minPanelWidth,
    min(metrics.maxPanelWidth, bounds.w - metrics.margin * 2),
  )
  let panelH = max(320, bounds.h - metrics.margin * 2)
  let panelX = bounds.x + max(0, (bounds.w - panelW) div 2)
  let panelY = bounds.y + max(0, (bounds.h - panelH) div 2)
  result.panel = OverlayRect(x: panelX, y: panelY, w: panelW, h: panelH)
  result.titleCols = fitOverlayTextColumns(panelW - metrics.pad * 2, metrics.cellWidth)
  result.titleY = panelY + metrics.pad
  let bodyY = result.titleY + metrics.cellHeight + metrics.titleBodyGap
  let bodyH = max(0, panelY + panelH - metrics.pad - bodyY)
  let treeW = max(160, panelW * 38 div 100)
  result.treePane = OverlayRect(x: panelX + metrics.pad, y: bodyY, w: treeW, h: bodyH)
  result.codePane = OverlayRect(
    x: result.treePane.x + result.treePane.w + metrics.pad,
    y: bodyY,
    w: max(120, panelW - metrics.pad * 3 - treeW),
    h: bodyH,
  )

func overlayHitTestExplorer*(
  layout: ExplorerChromeLayout;
  x, y: int;
  dismissOnBackdrop: bool,
): OverlayHit =
  if pointInOverlayRect(layout.panel, x, y):
    return OverlayHit(kind: ohPanel)
  if dismissOnBackdrop and pointInOverlayRect(layout.backdrop, x, y):
    return OverlayHit(kind: ohBackdrop, actionId: "dismiss")
  OverlayHit(kind: ohNone)

func overlayHitTestModal*(
  layout: ModalChromeLayout;
  x, y: int;
  dismissOnBackdrop: bool,
): OverlayHit =
  for i, btn in layout.buttons:
    if pointInOverlayRect(btn, x, y):
      return OverlayHit(kind: ohButton, buttonIndex: i, actionId: layout.buttonActionIds[i])
  if pointInOverlayRect(layout.panel, x, y):
    return OverlayHit(kind: ohNone)
  if dismissOnBackdrop and pointInOverlayRect(layout.backdrop, x, y):
    return OverlayHit(kind: ohBackdrop, actionId: "dismiss")
  OverlayHit(kind: ohNone)
