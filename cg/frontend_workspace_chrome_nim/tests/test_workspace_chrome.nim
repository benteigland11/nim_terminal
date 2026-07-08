import std/unittest
import workspace_chrome_lib

suite "workspace chrome":
  test "threeColumnRegions reserves center minimum":
    let bounds = WorkspaceRect(x: 0, y: 40, w: 800, h: 600)
    let regions = threeColumnRegions(bounds, catalogWidth = 220, inspectorWidth = 280)
    check regions.catalog.w == 220
    check regions.inspector.w == 280
    check regions.center.w == 300
    check regions.center.x == 220
    check regions.center.y == 40

  test "clampRail shrinks rails when space is tight":
    let bounds = WorkspaceRect(x: 0, y: 0, w: 300, h: 200)
    let regions = threeColumnRegions(bounds, catalogWidth = 220, inspectorWidth = 280, minCenterWidth = 120)
    check regions.center.w >= 120
    check regions.catalog.w + regions.center.w + regions.inspector.w == 300

  test "actionBarRegion sits on bottom edge":
    let bounds = WorkspaceRect(x: 10, y: 20, w: 400, h: 300)
    let bar = actionBarRegion(bounds, height = 36)
    check bar.h == 36
    check bar.y == 284
    let content = contentAboveActionBar(bounds, actionBarHeight = 36)
    check content.h == 264

  test "actionBarRegionTop sits on top edge":
    let bounds = WorkspaceRect(x: 10, y: 20, w: 400, h: 300)
    let bar = actionBarRegionTop(bounds, height = 36)
    check bar.h == 36
    check bar.y == 20
    let content = contentBelowActionBar(bounds, actionBarHeight = 36)
    check content.y == 56
    check content.h == 264

  test "stackedSidebarRegions puts catalog above inspector on the right":
    let bounds = WorkspaceRect(x: 0, y: 32, w: 1280, h: 688)
    let regions = stackedSidebarRegions(bounds, sidebarWidth = 300, catalogHeight = 320)
    check regions.center.w == 980
    check regions.center.x == 0
    check regions.catalog.x == 980
    check regions.inspector.x == 980
    check regions.catalog.h == 320
    check regions.inspector.y == 32 + 320
    check regions.catalog.h + regions.inspector.h == 688

  test "sidebarCatalogRegions caps catalog height without inspector":
    let bounds = WorkspaceRect(x: 0, y: 32, w: 1280, h: 688)
    let regions = sidebarCatalogRegions(bounds, sidebarWidth = 300, catalogHeight = 320)
    check regions.center.w == 980
    check regions.catalog.x == 980
    check regions.catalog.h == 320
    check regions.inspector.h == 0

  test "insetRect shrinks bounds on each edge":
    let inner = insetRect(WorkspaceRect(x: 10, y: 20, w: 100, h: 80), top = 5, right = 8, bottom = 7, left = 6)
    check inner.x == 16
    check inner.y == 25
    check inner.w == 86
    check inner.h == 68

  test "scrollListLayout anchors list content inside panel":
    let panel = WorkspaceRect(x: 980, y: 32, w: 300, h: 320)
    let layout = scrollListLayout(panel, cellHeight = 14, cellWidth = 8, pad = 10, scrollRow = 2, entryCount = 20)
    check layout.scrollable
    check layout.contentX == panel.x + 4
    check layout.contentW == panel.w - 8
    check layout.textCols == layout.contentW div 8
    check layout.showScrollUp
    check layout.showScrollDown
    check layout.scrollUp.x == layout.contentX
    check layout.scrollUp.w == layout.contentW
    check layout.listY == layout.titleY + 14 + 8 + layout.scrollArrowH
    check layout.stride == 14 * 2 + 10
    check layout.scrollDown.y == panel.y + panel.h - 10 - layout.scrollArrowH
    check layout.scrollDown.h == layout.scrollArrowH

  test "scrollListLayout reserves top slot before first scroll":
    let panel = WorkspaceRect(x: 980, y: 32, w: 300, h: 320)
    let atTop = scrollListLayout(panel, cellHeight = 14, cellWidth = 8, pad = 10, scrollRow = 0, entryCount = 20)
    let scrolled = scrollListLayout(panel, cellHeight = 14, cellWidth = 8, pad = 10, scrollRow = 1, entryCount = 20)
    check atTop.scrollable
    check not atTop.showScrollUp
    check scrolled.showScrollUp
    check atTop.listY == scrolled.listY
    check atTop.visibleRows == scrolled.visibleRows
    check atTop.scrollUp.y == scrolled.scrollUp.y
