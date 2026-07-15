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
    ## Wall-clock seconds when the current bracket started (0 if inactive).
    ## Hosts set this via `noteBeginTime` so a stuck bracket cannot freeze present.
    activeSince*: float

  SyncUpdateTransition* = object
    changed*: bool
    entered*: bool
    exited*: bool
    shouldPresent*: bool

const DefaultSyncUpdateMaxSec* = 0.25

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
  state.activeSince = 0.0
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

func noteBeginTime*(state: var SyncUpdateState, nowSec: float) =
  ## Record when the active bracket started (call on enter).
  if state.active and state.activeSince == 0.0:
    state.activeSince = nowSec

func forceEndIfTimedOut*(
    state: var SyncUpdateState,
    nowSec: float,
    maxSec: float = DefaultSyncUpdateMaxSec,
): SyncUpdateTransition =
  ## End a stuck synchronized-update bracket so present is not deferred forever.
  if not state.active:
    return SyncUpdateTransition()
  if state.activeSince <= 0.0:
    state.activeSince = nowSec
    return SyncUpdateTransition()
  if nowSec - state.activeSince < maxSec:
    return SyncUpdateTransition()
  endUpdate(state)

func shouldDeferPresent*(state: SyncUpdateState): bool =
  state.active
