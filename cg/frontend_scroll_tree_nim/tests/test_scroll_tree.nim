import std/unittest
import scroll_tree_lib

suite "scroll tree":
  test "computes layout and hit tests rows":
    let panel = TreePanelRect(x: 10, y: 20, w: 200, h: 120)
    let rows = @[
      TreeRowView(depth: 0, label: "root", rowId: 0, isBranch: true, expanded: true),
      TreeRowView(depth: 1, label: "child.nim", rowId: 1, isBranch: false, expanded: false),
    ]
    let layout = computeScrollTreeLayout(panel, 14, 8, pad = 8, scrollRow = 0, rowCount = rows.len)
    check layout.visibleRows > 0
    let rowHit = treeRowHitTest(layout, rows, treeRowLabelX(layout, 1, 8), treeRowY(layout, 1) + 2, 8)
    check rowHit.kind == trhRow
    check rowHit.rowId == 1

  test "detects branch toggle hit":
    let panel = TreePanelRect(x: 0, y: 0, w: 160, h: 80)
    let rows = @[
      TreeRowView(depth: 0, label: "pkg", rowId: 0, isBranch: true, expanded: false),
    ]
    let layout = computeScrollTreeLayout(panel, 14, 8, pad = 8, scrollRow = 0, rowCount = rows.len)
    let toggleHit = treeRowHitTest(layout, rows, layout.listX + 2, layout.listY + 2, 8)
    check toggleHit.kind == trhBranchToggle
