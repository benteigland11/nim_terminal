## Cartograph workspace surface state.
##
## Holds catalog scan results and selection for the Cartograph mode shell.
## Terminal panes remain owned by the host; this module tracks side-rail state.

import ../cg/data_widget_catalog_nim/src/widget_catalog_lib as widget_catalog
import ../cg/frontend_workspace_chrome_nim/src/workspace_chrome_lib as workspace_chrome
import ../cg/frontend_text_field_nim/src/text_field_lib as text_field

type
  CartographWorkspace* = ref object
    dirty*: bool
    catalog*: widget_catalog.WidgetCatalog
    visibleEntries*: seq[widget_catalog.CatalogEntry]  ## Catalog filtered by `search`.
    search*: text_field.TextField
    selectedIndex*: int      ## Index into `visibleEntries`.
    catalogScrollRow*: int

  CatalogScrollArea* = workspace_chrome.ScrollListArea
  CatalogListLayout* = workspace_chrome.ScrollListLayout

const DefaultCatalogRoot* = "cg"
const CatalogScrollArrowHeight* = workspace_chrome.ScrollListArrowHeight

proc catalogRowStride*(cellHeight: int): int =
  workspace_chrome.scrollListRowStride(cellHeight)

proc catalogRowHeight*(cellHeight: int): int =
  workspace_chrome.scrollListRowHeight(cellHeight)

proc pointInCatalogScrollArea*(x, y: int; area: CatalogScrollArea): bool =
  workspace_chrome.pointInScrollListArea(x, y, area)

proc computeCatalogListLayout*(
  catalogX, catalogY, catalogW, catalogH: int;
  cellHeight, cellWidth, pad, scrollRow, entryCount: int;
  sideInset = 4,
): CatalogListLayout =
  workspace_chrome.scrollListLayout(
    workspace_chrome.WorkspaceRect(x: catalogX, y: catalogY, w: catalogW, h: catalogH),
    cellHeight,
    cellWidth,
    pad,
    scrollRow,
    entryCount,
    sideInset,
  )

proc newCartographWorkspace*(): CartographWorkspace =
  CartographWorkspace(
    dirty: true,
    selectedIndex: -1,
    catalogScrollRow: 0,
    search: text_field.newTextField(),
    visibleEntries: @[],
  )

proc displayCatalog*(ws: CartographWorkspace): widget_catalog.WidgetCatalog =
  ## Catalog view actually shown to the user (respects the active search filter).
  if ws == nil:
    widget_catalog.WidgetCatalog()
  else:
    widget_catalog.WidgetCatalog(root: ws.catalog.root, entries: ws.visibleEntries)

proc markCartographDirty*(ws: CartographWorkspace) =
  if ws != nil:
    ws.dirty = true

proc clearCartographDirty*(ws: CartographWorkspace) =
  if ws != nil:
    ws.dirty = false

proc cartographNeedsRedraw*(ws: CartographWorkspace): bool =
  ws != nil and ws.dirty

proc catalogScrollMax*(ws: CartographWorkspace; visibleRows: int): int =
  if ws == nil or visibleRows <= 0:
    0
  else:
    max(0, ws.visibleEntries.len - visibleRows)

proc clampCartographCatalogScroll*(ws: CartographWorkspace; visibleRows: int) =
  if ws == nil:
    return
  ws.catalogScrollRow = max(0, min(ws.catalogScrollRow, catalogScrollMax(ws, visibleRows)))

proc ensureCartographSelectionVisible*(ws: CartographWorkspace; visibleRows: int) =
  if ws == nil or ws.selectedIndex < 0 or visibleRows <= 0:
    return
  if ws.selectedIndex < ws.catalogScrollRow:
    ws.catalogScrollRow = ws.selectedIndex
  elif ws.selectedIndex >= ws.catalogScrollRow + visibleRows:
    ws.catalogScrollRow = ws.selectedIndex - visibleRows + 1
  clampCartographCatalogScroll(ws, visibleRows)

proc scrollCartographCatalog*(ws: CartographWorkspace; deltaRows, visibleRows: int) =
  if ws == nil or deltaRows == 0:
    return
  ws.catalogScrollRow += deltaRows
  clampCartographCatalogScroll(ws, visibleRows)
  ws.dirty = true

proc applyCatalogFilter*(ws: CartographWorkspace; visibleRows = 0) =
  ## Recompute the visible entry list from the current search query, keeping
  ## the previously selected widget selected when it survives the filter.
  if ws == nil:
    return
  let prevDir =
    if ws.selectedIndex >= 0 and ws.selectedIndex < ws.visibleEntries.len:
      ws.visibleEntries[ws.selectedIndex].dirName
    else:
      ""
  ws.visibleEntries = ws.catalog.entries
  if ws.visibleEntries.len == 0:
    ws.selectedIndex = -1
    ws.catalogScrollRow = 0
  else:
    var newIndex = 0
    if prevDir.len > 0:
      for i, entry in ws.visibleEntries:
        if entry.dirName == prevDir:
          newIndex = i
          break
    ws.selectedIndex = newIndex
    if visibleRows > 0:
      ensureCartographSelectionVisible(ws, visibleRows)
    else:
      clampCartographCatalogScroll(ws, ws.visibleEntries.len)
  ws.dirty = true

proc refreshCartographCatalog*(ws: CartographWorkspace; root: string) =
  if ws == nil:
    return
  ws.catalog = widget_catalog.scanWidgetRoot(root)
  applyCatalogFilter(ws)

proc selectCartographEntry*(ws: CartographWorkspace; index: int; visibleRows = 0) =
  if ws == nil or ws.visibleEntries.len == 0:
    return
  ws.selectedIndex = max(0, min(index, ws.visibleEntries.len - 1))
  if visibleRows > 0:
    ensureCartographSelectionVisible(ws, visibleRows)
  ws.dirty = true

proc selectedCartographEntry*(ws: CartographWorkspace): widget_catalog.CatalogEntry =
  if ws == nil or ws.selectedIndex < 0 or ws.selectedIndex >= ws.visibleEntries.len:
    widget_catalog.CatalogEntry()
  else:
    ws.visibleEntries[ws.selectedIndex]
