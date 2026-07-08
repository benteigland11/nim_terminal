## Example usage of Scroll Tree.

import scroll_tree_lib

let panel = TreePanelRect(x: 0, y: 0, w: 240, h: 180)
let rows = @[
  TreeRowView(depth: 0, label: "src", rowId: 1, isBranch: true, expanded: true),
  TreeRowView(depth: 1, label: "main.nim", rowId: 2, isBranch: false, expanded: false),
]
let layout = computeScrollTreeLayout(panel, cellHeight = 14, cellWidth = 8, pad = 8, scrollRow = 0, rowCount = rows.len)
let hit = treeRowHitTest(layout, rows, layout.listX + 8, layout.listY + 2, cellWidth = 8)
assert hit.kind == trhRow
