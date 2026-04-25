## Damage tracker: mark-and-sweep over an indexed range (rows, lines,
## cells — the widget is domain-agnostic). A caller marks indices dirty
## as mutations happen, then a consumer (usually a renderer) queries
## which are dirty, paints them, and calls `clear` to start a new cycle.
##
## The `fullRepaint` flag is a one-shot hint set by `resize` and by
## `markAll` — use it when individual row tracking is meaningless because
## the underlying geometry or context changed.

type
  Damage* = ref object
    dirty: seq[bool]
    full: bool
    extent: int

func newDamage*(size: int): Damage =
  ## Build a tracker sized for `size` indices, all initially clean.
  ## Negative sizes are clamped to zero.
  let n = max(0, size)
  Damage(dirty: newSeq[bool](n), full: false, extent: n)

func size*(d: Damage): int = d.extent
  ## Current tracked range. Equals the argument to the most recent
  ## `newDamage` or `resize` call.

func fullRepaint*(d: Damage): bool = d.full
  ## True when the whole range should be repainted regardless of
  ## individual index state. Cleared by `clear`.

func markRow*(d: Damage, index: int) =
  ## Mark a single index dirty. Out-of-range indices are ignored so
  ## callers don't need to bounds-check every upstream mutation.
  if index < 0 or index >= d.extent: return
  d.dirty[index] = true

func markRows*(d: Damage, first, last: int) =
  ## Mark an inclusive range `[first, last]` dirty. The range is
  ## clamped to `[0, size-1]`; if it's wholly outside the range or
  ## inverted after clamping, nothing is marked.
  if d.extent == 0: return
  let lo = max(0, first)
  let hi = min(d.extent - 1, last)
  if lo > hi: return
  for i in lo .. hi:
    d.dirty[i] = true

func markAll*(d: Damage) =
  if d.extent == 0: return
  for i in 0 ..< d.extent:
    d.dirty[i] = true
  d.full = true

func resize*(d: Damage, size: int) =
  ## Resize the tracked range. After resize the entire new range is
  ## considered dirty (`fullRepaint = true`) because index meaning may
  ## have changed (old row 5 is not new row 5 after a terminal reflow).
  let n = max(0, size)
  d.dirty = newSeq[bool](n)
  for i in 0 ..< n:
    d.dirty[i] = true
  d.extent = n
  d.full = true

func clear*(d: Damage) =
  ## Reset all dirty state. Call after the renderer has painted.
  for i in 0 ..< d.extent:
    d.dirty[i] = false
  d.full = false

func isDirty*(d: Damage, index: int): bool =
  ## Query a single index. Out-of-range indices return false.
  if index < 0 or index >= d.extent: return false
  d.dirty[index]

func anyDirty*(d: Damage): bool =
  ## True if at least one index is dirty or `fullRepaint` is set.
  if d.full: return true
  for v in d.dirty:
    if v: return true
  false

func dirtyRows*(d: Damage): seq[int] =
  ## Ascending list of dirty indices. Cheap for sparse workloads, still
  ## fine for dense: the walk is O(size), no allocations beyond the
  ## returned sequence.
  for i in 0 ..< d.extent:
    if d.dirty[i]: result.add i
