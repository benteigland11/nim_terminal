## Compute rectangular regions for a three-column workspace shell.
##
## Given outer bounds and side-rail widths, returns non-overlapping
## catalog, center, and inspector regions with a minimum center width.

import std/math

type
  WorkspaceRect* = object
    x*, y*, w*, h*: int

  ThreeColumnRegions* = object
    catalog*, center*, inspector*: WorkspaceRect

func clampRail*(requested, available, minCenter: int): int =
  if available <= minCenter:
    0
  else:
    min(requested, available - minCenter)

func threeColumnRegions*(
    bounds: WorkspaceRect;
    catalogWidth: int;
    inspectorWidth: int;
    minCenterWidth = 120,
): ThreeColumnRegions =
  let available = max(0, bounds.w)
  let minCenter = max(1, minCenterWidth)
  let catW = clampRail(catalogWidth, available, minCenter)
  let remaining = max(0, available - catW)
  let insW = clampRail(inspectorWidth, remaining, minCenter)
  let centerW = max(0, available - catW - insW)
  result.catalog = WorkspaceRect(x: bounds.x, y: bounds.y, w: catW, h: bounds.h)
  result.center = WorkspaceRect(
    x: bounds.x + catW,
    y: bounds.y,
    w: centerW,
    h: bounds.h,
  )
  result.inspector = WorkspaceRect(
    x: bounds.x + catW + centerW,
    y: bounds.y,
    w: insW,
    h: bounds.h,
  )

func stackedSidebarRegions*(
    bounds: WorkspaceRect;
    sidebarWidth: int;
    catalogHeight: int;
    minCenterWidth = 320,
): ThreeColumnRegions =
  ## Terminal on the left; catalog and inspector stacked on the right sidebar.
  let available = max(0, bounds.w)
  let minCenter = max(1, minCenterWidth)
  let sideW = clampRail(sidebarWidth, available, minCenter)
  let centerW = max(0, available - sideW)
  let sideX = bounds.x + centerW
  let minInspectorH = 120
  let catH = max(80, min(catalogHeight, max(80, bounds.h - minInspectorH)))
  result.center = WorkspaceRect(x: bounds.x, y: bounds.y, w: centerW, h: bounds.h)
  result.catalog = WorkspaceRect(x: sideX, y: bounds.y, w: sideW, h: catH)
  result.inspector = WorkspaceRect(
    x: sideX,
    y: bounds.y + catH,
    w: sideW,
    h: max(0, bounds.h - catH),
  )

func sidebarCatalogRegions*(
    bounds: WorkspaceRect;
    sidebarWidth: int;
    catalogHeight: int;
    minCenterWidth = 320,
): ThreeColumnRegions =
  ## Terminal on the left; capped-height widget catalog on the right.
  let available = max(0, bounds.w)
  let minCenter = max(1, minCenterWidth)
  let sideW = clampRail(sidebarWidth, available, minCenter)
  let centerW = max(0, available - sideW)
  let sideX = bounds.x + centerW
  let catH = max(80, min(catalogHeight, bounds.h))
  result.center = WorkspaceRect(x: bounds.x, y: bounds.y, w: centerW, h: bounds.h)
  result.catalog = WorkspaceRect(x: sideX, y: bounds.y, w: sideW, h: catH)
  result.inspector = WorkspaceRect(x: sideX, y: bounds.y + catH, w: sideW, h: 0)

func actionBarRegion*(bounds: WorkspaceRect; height: int): WorkspaceRect =
  let barH = max(0, min(height, bounds.h))
  WorkspaceRect(x: bounds.x, y: bounds.y + bounds.h - barH, w: bounds.w, h: barH)

func contentAboveActionBar*(bounds: WorkspaceRect; actionBarHeight: int): WorkspaceRect =
  let barH = max(0, min(actionBarHeight, bounds.h))
  WorkspaceRect(x: bounds.x, y: bounds.y, w: bounds.w, h: max(0, bounds.h - barH))

func actionBarRegionTop*(bounds: WorkspaceRect; height: int): WorkspaceRect =
  let barH = max(0, min(height, bounds.h))
  WorkspaceRect(x: bounds.x, y: bounds.y, w: bounds.w, h: barH)

func contentBelowActionBar*(bounds: WorkspaceRect; actionBarHeight: int): WorkspaceRect =
  let barH = max(0, min(actionBarHeight, bounds.h))
  WorkspaceRect(x: bounds.x, y: bounds.y + barH, w: bounds.w, h: max(0, bounds.h - barH))

func insetRect*(
  bounds: WorkspaceRect;
  top, right, bottom, left: int,
): WorkspaceRect =
  ## Shrink `bounds` by fixed edge insets. Negative results clamp to zero.
  WorkspaceRect(
    x: bounds.x + left,
    y: bounds.y + top,
    w: max(0, bounds.w - left - right),
    h: max(0, bounds.h - top - bottom),
  )

func fitTextColumns*(contentWidth, cellWidth: int): int =
  if cellWidth <= 0:
    1
  else:
    max(1, contentWidth div cellWidth)

const ScrollListArrowHeight* = 18

type
  ScrollListArea* = object
    x*, y*, w*, h*: int

  ScrollListLayout* = object
    panel*: WorkspaceRect
    contentX*, contentW*, textCols*: int
    titleY*, listY*, stride*, visibleRows*, pad*, scrollArrowH*: int
    scrollable*: bool
    showScrollUp*, showScrollDown*: bool
    scrollUp*, scrollDown*: ScrollListArea

proc pointInScrollListArea*(x, y: int; area: ScrollListArea): bool =
  area.w > 0 and area.h > 0 and
    x >= area.x and x < area.x + area.w and
    y >= area.y and y < area.y + area.h

func scrollListRowStride*(cellHeight: int): int =
  ## Height of one two-line catalog row: title, subtitle, and entry spacing.
  cellHeight * 2 + 10

proc scrollListRowHeight*(cellHeight: int): int =
  ## Visible content height inside a row slot (both text lines).
  cellHeight * 2 + 2

proc scrollListLayout*(
  panel: WorkspaceRect;
  cellHeight, cellWidth: int;
  pad, scrollRow, entryCount: int;
  sideInset = 4,
): ScrollListLayout =
  ## Lay out a titled, optionally scrollable list anchored inside `panel`.
  ##
  ## Title pins to the top inset; the bottom scroll arrow pins to the panel
  ## bottom inset; rows fill the space between. When scrollable, the top arrow
  ## slot is always reserved so the list does not shift when scrolling down.
  ## `showScrollUp` controls whether the arrow is drawn and clickable.
  result.panel = panel
  result.pad = pad
  result.scrollArrowH = max(ScrollListArrowHeight, cellHeight + 6)
  if panel.w <= 0 or panel.h <= 0 or cellHeight <= 0:
    return
  result.contentX = panel.x + sideInset
  result.contentW = max(0, panel.w - sideInset * 2)
  result.textCols = fitTextColumns(result.contentW, cellWidth)
  result.titleY = panel.y + pad
  let baseListY = result.titleY + cellHeight + 8
  let panelBottom = panel.y + panel.h - pad
  result.stride = scrollListRowStride(cellHeight)
  if result.stride <= 0 or entryCount <= 0:
    result.listY = baseListY
    return
  let fullListSpace = max(0, panelBottom - baseListY)
  let maxRowsNoArrows = fullListSpace div result.stride
  if entryCount <= maxRowsNoArrows and entryCount <= 3:
    result.listY = baseListY
    result.visibleRows = maxRowsNoArrows
    return
  result.scrollable = true
  let listY = baseListY + result.scrollArrowH
  let listBottom = panelBottom - result.scrollArrowH
  let listSpace = max(0, listBottom - listY)
  result.visibleRows = listSpace div result.stride
  result.showScrollUp = scrollRow > 0
  result.showScrollDown = scrollRow + result.visibleRows < entryCount
  result.listY = listY
  result.scrollUp = ScrollListArea(
    x: result.contentX, y: baseListY, w: result.contentW, h: result.scrollArrowH,
  )
  result.scrollDown = ScrollListArea(
    x: result.contentX,
    y: listBottom,
    w: result.contentW,
    h: result.scrollArrowH,
  )
