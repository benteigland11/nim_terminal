## Example usage of Menu.

import menu_lib

# A right-click context menu with two actions.
var menu = newMenu(@[
  menuItem("inspect", "Inspect"),
  menuItem("copy-id", "Copy id"),
])

let metrics = defaultMenuMetrics(cellHeight = 16)

# The user right-clicked at (420, 300) on an 1280x720 screen.
let layout = computeMenuLayout(420, 300, 1280, 720, menu.items, cellWidth = 8, metrics)
assert layout.rect.w > 0

# Which row is under a later left-click?
let row = menuRowAt(layout, menu.items, 430, layout.firstRowY + 1)
assert row == 0

menu.setHighlight(row)
assert menu.selectedItemId() == "inspect"
