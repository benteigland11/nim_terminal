## Anchored popup menu model: item list, highlight state, and a layout solver
## that positions the popup near an anchor point while keeping it on screen.
##
## Pure logic — no rendering and no input backend. Feed it an anchor (usually a
## click or a widget rect corner) and the screen bounds; it returns a rect plus
## per-row geometry so the host can draw rows and hit-test the pointer. Works
## for context menus, dropdowns, and command popups. Sizing is in monospace
## cell units.

type
  MenuItem* = object
    id*: string
    label*: string
    enabled*: bool

  Menu* = object
    items*: seq[MenuItem]
    highlighted*: int   ## Highlighted row index, or -1 for none.

  MenuMetrics* = object
    rowHeight*: int     ## Pixel height of a single row.
    padX*: int          ## Horizontal padding inside the menu.
    padY*: int          ## Vertical padding above the first / below the last row.
    minWidth*: int      ## Lower bound on menu width.

  MenuRect* = object
    x*, y*, w*, h*: int

  MenuLayout* = object
    rect*: MenuRect
    rowHeight*: int
    firstRowY*: int
    padX*: int

func menuItem*(id, label: string; enabled = true): MenuItem =
  MenuItem(id: id, label: label, enabled: enabled)

func newMenu*(items: openArray[MenuItem]): Menu =
  Menu(items: @items, highlighted: -1)

func menuLen*(menu: Menu): int =
  menu.items.len

func defaultMenuMetrics*(cellHeight: int): MenuMetrics =
  MenuMetrics(rowHeight: cellHeight + 8, padX: 12, padY: 6, minWidth: 0)

func longestLabelLen*(items: openArray[MenuItem]): int =
  for item in items:
    if item.label.len > result:
      result = item.label.len

func menuWidth*(items: openArray[MenuItem]; cellWidth: int; metrics: MenuMetrics): int =
  max(metrics.minWidth, longestLabelLen(items) * max(0, cellWidth) + metrics.padX * 2)

func menuHeight*(itemCount: int; metrics: MenuMetrics): int =
  itemCount * metrics.rowHeight + metrics.padY * 2

func computeMenuLayout*(
    anchorX, anchorY, screenW, screenH: int;
    items: openArray[MenuItem];
    cellWidth: int;
    metrics: MenuMetrics): MenuLayout =
  ## Position a popup with its top-left near (anchorX, anchorY). If it would
  ## overflow the right edge it shifts left; if it would overflow the bottom it
  ## opens upward from the anchor. Always clamped to the screen.
  let w = menuWidth(items, cellWidth, metrics)
  let h = menuHeight(items.len, metrics)
  var x = anchorX
  if screenW > 0 and x + w > screenW:
    x = screenW - w
  if x < 0:
    x = 0
  var y = anchorY
  if screenH > 0 and y + h > screenH:
    ## Prefer opening above the anchor; fall back to clamping.
    y = if anchorY - h >= 0: anchorY - h else: max(0, screenH - h)
  if y < 0:
    y = 0
  MenuLayout(
    rect: MenuRect(x: x, y: y, w: w, h: h),
    rowHeight: metrics.rowHeight,
    firstRowY: y + metrics.padY,
    padX: metrics.padX,
  )

func pointInMenu*(layout: MenuLayout; x, y: int): bool =
  layout.rect.w > 0 and layout.rect.h > 0 and
    x >= layout.rect.x and x < layout.rect.x + layout.rect.w and
    y >= layout.rect.y and y < layout.rect.y + layout.rect.h

func menuRowBounds*(layout: MenuLayout; index: int): MenuRect =
  ## Pixel rect for row `index` (for drawing the highlight background).
  MenuRect(
    x: layout.rect.x,
    y: layout.firstRowY + index * layout.rowHeight,
    w: layout.rect.w,
    h: layout.rowHeight,
  )

func menuRowAt*(layout: MenuLayout; items: openArray[MenuItem]; x, y: int): int =
  ## Index of the row under the pointer, or -1 when outside or on a disabled
  ## row. Disabled rows are treated as non-selectable.
  if not pointInMenu(layout, x, y) or layout.rowHeight <= 0:
    return -1
  let rel = y - layout.firstRowY
  if rel < 0:
    return -1
  let index = rel div layout.rowHeight
  if index < 0 or index >= items.len:
    return -1
  if not items[index].enabled:
    return -1
  index

proc setHighlight*(menu: var Menu; index: int) =
  if index >= 0 and index < menu.items.len and menu.items[index].enabled:
    menu.highlighted = index
  else:
    menu.highlighted = -1

proc highlightAt*(menu: var Menu; layout: MenuLayout; x, y: int) =
  menu.setHighlight(menuRowAt(layout, menu.items, x, y))

func selectedItemId*(menu: Menu): string =
  if menu.highlighted >= 0 and menu.highlighted < menu.items.len:
    menu.items[menu.highlighted].id
  else:
    ""
