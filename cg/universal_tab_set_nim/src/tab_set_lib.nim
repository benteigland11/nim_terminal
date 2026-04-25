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
