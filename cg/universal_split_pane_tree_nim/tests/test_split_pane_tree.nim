import std/[options, unittest]
import split_pane_tree_lib

suite "Split Pane Tree":
  test "new tree starts with one active leaf":
    let tree = newSplitPaneTree()
    check tree.len == 1
    check tree.active == paneId(1)
    check tree.contains(paneId(1))

  test "split active creates second leaf and allocates right side":
    var tree = newSplitPaneTree()
    let second = tree.splitActive(saHorizontal)
    check second == paneId(2)
    check tree.active == second
    check tree.len == 2

    let items = tree.layouts(rect(0, 0, 100, 20))
    check items.len == 2
    check items[0].id == paneId(1)
    check items[0].rect == rect(0, 0, 50, 20)
    check items[1].id == paneId(2)
    check items[1].rect == rect(50, 0, 50, 20)

  test "vertical split divides height":
    var tree = newSplitPaneTree()
    discard tree.splitActive(saVertical, 0.25)
    let items = tree.layouts(rect(0, 0, 80, 40))
    check items[0].rect == rect(0, 0, 80, 10)
    check items[1].rect == rect(0, 10, 80, 30)

  test "append policy creates side-by-side, then stacked, then side-by-side":
    var tree = newSplitPaneTree()
    check tree.nextAppendAxis() == saHorizontal

    let second = tree.splitActiveAppend()
    check second == paneId(2)
    check tree.nextAppendAxis() == saVertical

    let third = tree.splitActiveAppend()
    check third == paneId(3)
    check tree.nextAppendAxis() == saHorizontal

    let fourth = tree.splitActiveAppend()
    check fourth == paneId(4)

    let items = tree.layouts(rect(0, 0, 100, 40))
    check items.len == 4
    check items[0].id == paneId(1)
    check items[0].rect == rect(0, 0, 50, 40)
    check items[1].id == paneId(2)
    check items[1].rect == rect(50, 0, 50, 20)
    check items[2].id == paneId(3)
    check items[2].rect == rect(50, 20, 25, 20)
    check items[3].id == paneId(4)
    check items[3].rect == rect(75, 20, 25, 20)

  test "hit testing finds leaf by rectangle":
    var tree = newSplitPaneTree()
    let second = tree.splitActive(saHorizontal)
    let area = rect(0, 0, 100, 20)
    check tree.hitTest(area, 10, 5).get() == paneId(1)
    check tree.hitTest(area, 60, 5).get() == second
    check tree.hitTest(area, 100, 5).isNone

  test "close collapses sibling and preserves last leaf":
    var tree = newSplitPaneTree()
    let second = tree.splitActive(saHorizontal)
    check tree.close(second)
    check tree.len == 1
    check tree.active == paneId(1)
    check not tree.close(paneId(1))

  test "activate rejects unknown leaf":
    var tree = newSplitPaneTree()
    check not tree.activate(paneId(99))
    check tree.activate(paneId(1))
