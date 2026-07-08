## Scrollable tree list layout and hit testing for indented rows.

import std/math

type
  TreePanelRect* = object
    x*, y*, w*, h*: int

  TreeRowView* = object
    depth*: int
    label*: string
    rowId*: int
    isBranch*: bool
    expanded*: bool

  ScrollTreeLayout* = object
    panel*: TreePanelRect
    listX*, listY*, contentW*, textCols*: int
    stride*, visibleRows*, scrollRow*, pad*, indentCols*: int
    scrollable*: bool
    showScrollUp*, showScrollDown*: bool
    scrollUp*, scrollDown*: TreePanelRect

  TreeRowHitKind* = enum
    trhNone
    trhBranchToggle
    trhRow

  TreeRowHit* = object
    kind*: TreeRowHitKind
    localRow*: int
    rowId*: int

func scrollTreeRowStride*(cellHeight: int): int =
  max(1, cellHeight + 4)

func pointInTreePanel*(rect: TreePanelRect; x, y: int): bool =
  rect.w > 0 and rect.h > 0 and
    x >= rect.x and x < rect.x + rect.w and
    y >= rect.y and y < rect.y + rect.h

func computeScrollTreeLayout*(
  panel: TreePanelRect;
  cellHeight, cellWidth: int;
  pad, scrollRow, rowCount: int;
  indentCols = 2,
): ScrollTreeLayout =
  result.panel = panel
  result.pad = pad
  result.indentCols = max(1, indentCols)
  result.stride = scrollTreeRowStride(cellHeight)
  if panel.w <= 0 or panel.h <= 0 or cellHeight <= 0 or rowCount <= 0:
    return
  result.listX = panel.x + pad
  result.listY = panel.y + pad
  result.contentW = max(0, panel.w - pad * 2)
  result.textCols = max(1, result.contentW div max(1, cellWidth))
  let listSpace = max(0, panel.y + panel.h - pad - result.listY)
  let maxRows = listSpace div result.stride
  result.visibleRows = maxRows
  if rowCount <= maxRows:
    result.scrollRow = 0
    return
  result.scrollable = true
  result.scrollRow = max(0, min(scrollRow, rowCount - maxRows))
  result.visibleRows = maxRows
  result.showScrollUp = result.scrollRow > 0
  result.showScrollDown = result.scrollRow + maxRows < rowCount
  let arrowH = max(14, cellHeight + 4)
  if result.showScrollUp:
    result.scrollUp = TreePanelRect(x: result.listX, y: result.listY, w: result.contentW, h: arrowH)
    result.listY += arrowH
  if result.showScrollDown:
    result.scrollDown = TreePanelRect(
      x: result.listX,
      y: panel.y + panel.h - pad - arrowH,
      w: result.contentW,
      h: arrowH,
    )

func treeRowLabelCols*(layout: ScrollTreeLayout; depth: int): int =
  max(1, layout.textCols - depth * layout.indentCols - 2)

func treeRowLabelX*(layout: ScrollTreeLayout; depth: int; cellWidth: int): int =
  layout.listX + depth * layout.indentCols * cellWidth + cellWidth

func treeRowY*(layout: ScrollTreeLayout; localRow: int): int =
  layout.listY + localRow * layout.stride

func treeRowHitTest*(
  layout: ScrollTreeLayout;
  rows: openArray[TreeRowView];
  x, y: int;
  cellWidth: int,
): TreeRowHit =
  if not pointInTreePanel(layout.panel, x, y):
    return TreeRowHit(kind: trhNone)
  if layout.showScrollUp and pointInTreePanel(layout.scrollUp, x, y):
    return TreeRowHit(kind: trhNone)
  if layout.showScrollDown and pointInTreePanel(layout.scrollDown, x, y):
    return TreeRowHit(kind: trhNone)
  if layout.visibleRows <= 0:
    return TreeRowHit(kind: trhNone)
  for local in 0 ..< min(layout.visibleRows, rows.len - layout.scrollRow):
    let rowIndex = layout.scrollRow + local
    if rowIndex >= rows.len:
      break
    let row = rows[rowIndex]
    let rowY = treeRowY(layout, local)
    if y < rowY or y >= rowY + layout.stride:
      continue
    let toggleX = layout.listX + row.depth * layout.indentCols * cellWidth
    if row.isBranch and x >= toggleX and x < toggleX + cellWidth:
      return TreeRowHit(kind: trhBranchToggle, localRow: rowIndex, rowId: row.rowId)
    return TreeRowHit(kind: trhRow, localRow: rowIndex, rowId: row.rowId)
  TreeRowHit(kind: trhNone)
