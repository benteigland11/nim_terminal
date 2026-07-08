import std/unittest
import menu_lib

let sample = @[
  menuItem("open", "Open"),
  menuItem("copy", "Copy id"),
  menuItem("delete", "Delete", enabled = false),
]

suite "menu":
  test "sizing":
    let metrics = defaultMenuMetrics(16)
    check longestLabelLen(sample) == "Copy id".len
    check menuWidth(sample, 8, metrics) == "Copy id".len * 8 + metrics.padX * 2
    check menuHeight(sample.len, metrics) == sample.len * metrics.rowHeight + metrics.padY * 2

  test "layout positions at anchor when it fits":
    let metrics = defaultMenuMetrics(16)
    let layout = computeMenuLayout(100, 50, 1000, 800, sample, 8, metrics)
    check layout.rect.x == 100
    check layout.rect.y == 50
    check layout.firstRowY == 50 + metrics.padY

  test "layout shifts left and up near edges":
    let metrics = defaultMenuMetrics(16)
    let w = menuWidth(sample, 8, metrics)
    let h = menuHeight(sample.len, metrics)
    let layout = computeMenuLayout(995, 795, 1000, 800, sample, 8, metrics)
    check layout.rect.x == 1000 - w
    check layout.rect.y == 795 - h

  test "row hit testing skips disabled rows":
    let metrics = defaultMenuMetrics(16)
    let layout = computeMenuLayout(0, 0, 1000, 800, sample, 8, metrics)
    let row0Y = layout.firstRowY + 1
    check menuRowAt(layout, sample, 5, row0Y) == 0
    let disabledY = layout.firstRowY + 2 * layout.rowHeight + 1
    check menuRowAt(layout, sample, 5, disabledY) == -1
    check menuRowAt(layout, sample, 5000, row0Y) == -1

  test "highlight tracks enabled rows":
    var menu = newMenu(sample)
    let layout = computeMenuLayout(0, 0, 1000, 800, sample, 8, defaultMenuMetrics(16))
    menu.highlightAt(layout, 5, layout.firstRowY + 1)
    check menu.highlighted == 0
    check menu.selectedItemId() == "open"
    menu.setHighlight(2)
    check menu.highlighted == -1
