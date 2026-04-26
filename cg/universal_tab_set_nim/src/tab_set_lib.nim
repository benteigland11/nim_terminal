## Generic tab state manager.
##
## Maintains a stable-id ordered set of tabs with one active tab.
## The widget owns only tab metadata and activation rules; callers own
## the resources associated with each tab id.

import std/options

type
  TabId* = distinct int

  Tab* = object
    id*: TabId
    label*: string

  TabSet* = object
    tabs*: seq[Tab]
    activeId*: Option[TabId]
    nextId: int

func `$`*(id: TabId): string = $int(id)
func `==`*(a, b: TabId): bool = int(a) == int(b)
func intValue*(id: TabId): int = int(id)

func newTabSet*(): TabSet =
  TabSet(tabs: @[], activeId: none(TabId), nextId: 1)

func len*(set: TabSet): int = set.tabs.len
func isEmpty*(set: TabSet): bool = set.tabs.len == 0

func indexOf*(set: TabSet, id: TabId): int =
  for i, tab in set.tabs:
    if tab.id == id:
      return i
  -1

func contains*(set: TabSet, id: TabId): bool = set.indexOf(id) >= 0

func activeIndex*(set: TabSet): int =
  if set.activeId.isNone:
    return -1
  set.indexOf(set.activeId.get())

func activeTab*(set: TabSet): Option[Tab] =
  let idx = set.activeIndex()
  if idx < 0:
    none(Tab)
  else:
    some(set.tabs[idx])

proc addTab*(set: var TabSet, label: string, activate: bool = true): TabId =
  result = TabId(set.nextId)
  inc set.nextId
  set.tabs.add Tab(id: result, label: label)
  if activate or set.activeId.isNone:
    set.activeId = some(result)

proc activate*(set: var TabSet, id: TabId): bool =
  if not set.contains(id):
    return false
  set.activeId = some(id)
  true

proc rename*(set: var TabSet, id: TabId, label: string): bool =
  let idx = set.indexOf(id)
  if idx < 0:
    return false
  set.tabs[idx].label = label
  true

proc close*(set: var TabSet, id: TabId): bool =
  let idx = set.indexOf(id)
  if idx < 0:
    return false

  let wasActive = set.activeId.isSome and set.activeId.get() == id
  set.tabs.delete(idx)

  if set.tabs.len == 0:
    set.activeId = none(TabId)
  elif wasActive:
    let nextIdx = min(idx, set.tabs.len - 1)
    set.activeId = some(set.tabs[nextIdx].id)

  true

proc activateNext*(set: var TabSet): bool =
  if set.tabs.len == 0:
    return false
  let idx = set.activeIndex()
  let nextIdx = if idx < 0: 0 else: (idx + 1) mod set.tabs.len
  set.activeId = some(set.tabs[nextIdx].id)
  true

proc activatePrevious*(set: var TabSet): bool =
  if set.tabs.len == 0:
    return false
  let idx = set.activeIndex()
  let prevIdx = if idx <= 0: set.tabs.len - 1 else: idx - 1
  set.activeId = some(set.tabs[prevIdx].id)
  true

# ---------------------------------------------------------------------------
# Tab Strip Hit Testing
# ---------------------------------------------------------------------------

func plusButtonWidth*(tabBarHeight: int, minPlusWidth = 32): int =
  max(minPlusWidth, tabBarHeight)

func tabAreaWidth*(totalWidth, tabBarHeight: int, minPlusWidth = 32): int =
  max(0, totalWidth - plusButtonWidth(tabBarHeight, minPlusWidth))

func tabWidth*(set: TabSet, totalWidth, tabBarHeight: int, minPlusWidth = 32, minTabWidth = 12): int =
  let areaWidth = tabAreaWidth(totalWidth, tabBarHeight, minPlusWidth)
  if set.tabs.len == 0:
    areaWidth
  else:
    max(minTabWidth, areaWidth div max(1, set.tabs.len))

func tabAtX*(set: TabSet, x, totalWidth, tabBarHeight: int): Option[TabId] =
  let areaWidth = tabAreaWidth(totalWidth, tabBarHeight)
  if x < 0 or x >= areaWidth or set.tabs.len == 0:
    return none(TabId)
  let idx = x div set.tabWidth(totalWidth, tabBarHeight)
  if idx < 0 or idx >= set.tabs.len:
    none(TabId)
  else:
    some(set.tabs[idx].id)

func closeTabAtX*(set: TabSet, x, totalWidth, tabBarHeight: int): Option[TabId] =
  let areaWidth = tabAreaWidth(totalWidth, tabBarHeight)
  if x < 0 or x >= areaWidth or set.tabs.len <= 1:
    return none(TabId)
  let width = set.tabWidth(totalWidth, tabBarHeight)
  let idx = x div width
  if idx < 0 or idx >= set.tabs.len:
    return none(TabId)
  let tabX = idx * width
  let w = min(width, areaWidth - tabX)
  if w < 44:
    return none(TabId)
  let closeSize = max(10, min(tabBarHeight - 10, 16))
  let closeX = tabX + w - closeSize - 6
  if x >= closeX and x < closeX + closeSize:
    some(set.tabs[idx].id)
  else:
    none(TabId)

func plusButtonAtX*(x, totalWidth, tabBarHeight: int): bool =
  let width = plusButtonWidth(tabBarHeight)
  x >= max(0, totalWidth - width)
