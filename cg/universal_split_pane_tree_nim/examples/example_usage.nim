## Example usage of Split Pane Tree.

import split_pane_tree_lib
import std/options

var tree = newSplitPaneTree()
discard tree.splitActive(saHorizontal)
let visible = tree.layouts(rect(0, 0, 120, 30))
doAssert visible.len == 2
doAssert tree.hitTest(rect(0, 0, 120, 30), 90, 5).isSome
