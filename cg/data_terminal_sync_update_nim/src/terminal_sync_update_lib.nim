## Synchronized terminal update state.
##
## Terminal applications can bracket a burst of redraw bytes with a private
## mode so emulators can avoid presenting intermediate frames. This widget
## tracks that small state machine without owning rendering or I/O.

type
  SyncUpdateState* = object
    active*: bool
    beginCount*: int
    endCount*: int
    dirtyWhileActive*: bool

  SyncUpdateTransition* = object
    changed*: bool
    entered*: bool
    exited*: bool
    shouldPresent*: bool

func newSyncUpdateState*(): SyncUpdateState =
  SyncUpdateState()

func beginUpdate*(state: var SyncUpdateState): SyncUpdateTransition =
  inc state.beginCount
  if state.active:
    return SyncUpdateTransition()
  state.active = true
  state.dirtyWhileActive = false
  SyncUpdateTransition(changed: true, entered: true)

func endUpdate*(state: var SyncUpdateState): SyncUpdateTransition =
  inc state.endCount
  if not state.active:
    return SyncUpdateTransition()
  let hadDirty = state.dirtyWhileActive
  state.active = false
  state.dirtyWhileActive = false
  SyncUpdateTransition(
    changed: true,
    exited: true,
    shouldPresent: hadDirty,
  )

func setActive*(state: var SyncUpdateState, active: bool): SyncUpdateTransition =
  if active:
    beginUpdate(state)
  else:
    endUpdate(state)

func markDirty*(state: var SyncUpdateState) =
  if state.active:
    state.dirtyWhileActive = true

func shouldDeferPresent*(state: SyncUpdateState): bool =
  state.active
