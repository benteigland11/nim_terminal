## Split-pane tree layout manager.
##
## Stores a binary split tree whose leaves are caller-owned item ids. The widget
## owns only layout, focus, split, close/collapse, rectangle allocation, and
## hit-testing logic.

import std/options

type
  PaneId* = distinct int

  SplitAxis* = enum
    saHorizontal ## Children divide width: first on the left, second on the right.
    saVertical   ## Children divide height: first on top, second on bottom.

  Rect* = object
    x*, y*, w*, h*: int

  PaneNodeKind = enum
    pnkLeaf
    pnkSplit

  PaneNode = ref object
    case kind: PaneNodeKind
    of pnkLeaf:
      id: PaneId
    of pnkSplit:
      axis: SplitAxis
      ratio: float
      first: PaneNode
      second: PaneNode

  PaneLayout* = object
    id*: PaneId
    rect*: Rect

  SplitPaneTree* = object
    root: PaneNode
    active*: PaneId
    nextId: int

func paneId*(value: int): PaneId = PaneId(value)
func intValue*(id: PaneId): int = int(id)
func `$`*(id: PaneId): string = $int(id)
func `==`*(a, b: PaneId): bool = int(a) == int(b)

func rect*(x, y, w, h: int): Rect =
  Rect(x: x, y: y, w: max(0, w), h: max(0, h))

func contains*(r: Rect, x, y: int): bool =
  x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h

func newLeaf(id: PaneId): PaneNode =
  PaneNode(kind: pnkLeaf, id: id)

func newSplit(axis: SplitAxis, ratio: float, first, second: PaneNode): PaneNode =
  PaneNode(kind: pnkSplit, axis: axis, ratio: max(0.05, min(0.95, ratio)), first: first, second: second)

func newSplitPaneTree*(): SplitPaneTree =
  let first = paneId(1)
  SplitPaneTree(root: newLeaf(first), active: first, nextId: 2)

func len(n: PaneNode): int =
  if n == nil: return 0
  case n.kind
  of pnkLeaf: 1
  of pnkSplit: len(n.first) + len(n.second)

func len*(t: SplitPaneTree): int = len(t.root)

func contains(n: PaneNode, id: PaneId): bool =
  if n == nil: return false
  case n.kind
  of pnkLeaf: n.id == id
  of pnkSplit: contains(n.first, id) or contains(n.second, id)

func contains*(t: SplitPaneTree, id: PaneId): bool = contains(t.root, id)

func firstLeaf(n: PaneNode): Option[PaneId] =
  if n == nil: return none(PaneId)
  case n.kind
  of pnkLeaf: some(n.id)
  of pnkSplit:
    let left = firstLeaf(n.first)
    if left.isSome: left else: firstLeaf(n.second)

func firstLeaf*(t: SplitPaneTree): Option[PaneId] = firstLeaf(t.root)

proc splitNode(n: var PaneNode, target, fresh: PaneId, axis: SplitAxis, ratio: float): bool =
  if n == nil: return false
  case n.kind
  of pnkLeaf:
    if n.id != target: return false
    n = newSplit(axis, ratio, newLeaf(target), newLeaf(fresh))
    true
  of pnkSplit:
    if splitNode(n.first, target, fresh, axis, ratio): true
    else: splitNode(n.second, target, fresh, axis, ratio)

proc splitActive*(t: var SplitPaneTree, axis: SplitAxis, ratio = 0.5): PaneId =
  ## Split the active leaf and return the newly-created leaf id.
  result = paneId(t.nextId)
  inc t.nextId
  if not splitNode(t.root, t.active, result, axis, ratio):
    t.root = newLeaf(result)
  t.active = result

proc normalizeAxis(n: PaneNode, axis: SplitAxis) =
  if n == nil or n.kind != pnkSplit: return
  normalizeAxis(n.first, axis)
  normalizeAxis(n.second, axis)
  if n.axis == axis:
    n.ratio = float(len(n.first)) / float(len(n))

func nextAppendAxis*(t: SplitPaneTree): SplitAxis =
  ## Choose the next split direction for append-style pane creation.
  ##
  ## The first append makes a top/bottom split so one pane can stay full width.
  ## Later appends split the active pane side-by-side inside that row.
  if t.len <= 1: saVertical else: saHorizontal

proc splitActiveAppend*(t: var SplitPaneTree, ratio = 0.5): PaneId =
  ## Split the active leaf using the widget's default append policy.
  let axis = t.nextAppendAxis()
  result = t.splitActive(axis, ratio)
  if axis == saHorizontal:
    normalizeAxis(t.root, axis)

proc activate*(t: var SplitPaneTree, id: PaneId): bool =
  if not t.contains(id): return false
  t.active = id
  true

proc closeNode(n: var PaneNode, target: PaneId, replacementActive: var Option[PaneId]): bool =
  if n == nil: return false
  case n.kind
  of pnkLeaf:
    false
  of pnkSplit:
    if n.first.kind == pnkLeaf and n.first.id == target:
      replacementActive = firstLeaf(n.second)
      n = n.second
      return true
    if n.second.kind == pnkLeaf and n.second.id == target:
      replacementActive = firstLeaf(n.first)
      n = n.first
      return true
    closeNode(n.first, target, replacementActive) or closeNode(n.second, target, replacementActive)

proc close*(t: var SplitPaneTree, id: PaneId): bool =
  ## Close a leaf and collapse its sibling upward. The last leaf is retained.
  if t.len <= 1 or not t.contains(id): return false
  var replacement = none(PaneId)
  result = closeNode(t.root, id, replacement)
  if result and t.active == id:
    t.active = if replacement.isSome: replacement.get() else: t.firstLeaf().get(paneId(1))

func splitRect(r: Rect, axis: SplitAxis, ratio: float): tuple[first, second: Rect] =
  let clamped = max(0.05, min(0.95, ratio))
  case axis
  of saHorizontal:
    let firstW = max(1, min(r.w - 1, int(float(r.w) * clamped)))
    (rect(r.x, r.y, firstW, r.h), rect(r.x + firstW, r.y, r.w - firstW, r.h))
  of saVertical:
    let firstH = max(1, min(r.h - 1, int(float(r.h) * clamped)))
    (rect(r.x, r.y, r.w, firstH), rect(r.x, r.y + firstH, r.w, r.h - firstH))

proc collectLayouts(n: PaneNode, area: Rect, result: var seq[PaneLayout]) =
  if n == nil or area.w <= 0 or area.h <= 0: return
  case n.kind
  of pnkLeaf:
    result.add PaneLayout(id: n.id, rect: area)
  of pnkSplit:
    let parts = splitRect(area, n.axis, n.ratio)
    collectLayouts(n.first, parts.first, result)
    collectLayouts(n.second, parts.second, result)

func layouts*(t: SplitPaneTree, area: Rect): seq[PaneLayout] =
  collectLayouts(t.root, area, result)

func hitTest*(t: SplitPaneTree, area: Rect, x, y: int): Option[PaneId] =
  for item in t.layouts(area):
    if item.rect.contains(x, y):
      return some(item.id)
  none(PaneId)
