## Keyboard focus and tab-order manager over a fixed set of named targets.
##
## Pure state: the host registers an ordered list of focusable region ids and
## asks the ring which one currently owns the keyboard. Cycling wraps in tab
## order. A ring may also be "unfocused" (no target), which is useful when a
## default surface — like a live terminal — should receive input unless the
## user explicitly focuses a chrome region.

type
  FocusRing* = object
    targets: seq[string]
    index: int   ## Current target index, or -1 when nothing is focused.

func newFocusRing*(targets: openArray[string]; focused = ""): FocusRing =
  result.targets = @targets
  result.index = -1
  if focused.len > 0:
    for i, id in result.targets:
      if id == focused:
        result.index = i
        break

func targets*(ring: FocusRing): seq[string] =
  ring.targets

func hasFocus*(ring: FocusRing): bool =
  ## True when some target is focused (i.e. not the "unfocused" state).
  ring.index >= 0 and ring.index < ring.targets.len

func current*(ring: FocusRing): string =
  ## The focused target id, or "" when unfocused.
  if ring.hasFocus():
    ring.targets[ring.index]
  else:
    ""

func isFocused*(ring: FocusRing; id: string): bool =
  ring.hasFocus() and ring.targets[ring.index] == id

proc focus*(ring: var FocusRing; id: string): bool =
  ## Focus a specific target by id. Returns false if the id is unknown.
  for i, target in ring.targets:
    if target == id:
      ring.index = i
      return true
  false

proc clearFocus*(ring: var FocusRing) =
  ring.index = -1

proc focusFirst*(ring: var FocusRing) =
  ring.index = if ring.targets.len > 0: 0 else: -1

proc focusNext*(ring: var FocusRing) =
  ## Advance to the next target in tab order, wrapping. From the unfocused
  ## state this focuses the first target.
  if ring.targets.len == 0:
    ring.index = -1
    return
  ring.index = (ring.index + 1) mod ring.targets.len

proc focusPrev*(ring: var FocusRing) =
  ## Step to the previous target in tab order, wrapping. From the unfocused
  ## state this focuses the last target.
  if ring.targets.len == 0:
    ring.index = -1
    return
  if ring.index <= 0:
    ring.index = ring.targets.len - 1
  else:
    dec ring.index
