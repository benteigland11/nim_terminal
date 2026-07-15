import std/unittest
import terminal_sync_update_lib

suite "Terminal Sync Update":
  test "begin enters active update":
    var state = newSyncUpdateState()
    let transition = state.beginUpdate()
    check state.active
    check transition.changed
    check transition.entered
    check not transition.exited
    check state.beginCount == 1

  test "duplicate begin is idempotent for presentation state":
    var state = newSyncUpdateState()
    discard state.beginUpdate()
    let transition = state.beginUpdate()
    check state.active
    check not transition.changed
    check state.beginCount == 2

  test "end exits and requests present only when dirty":
    var state = newSyncUpdateState()
    discard state.beginUpdate()
    state.markDirty()
    let transition = state.endUpdate()
    check not state.active
    check transition.changed
    check transition.exited
    check transition.shouldPresent
    check state.endCount == 1

  test "clean end does not request present":
    var state = newSyncUpdateState()
    discard state.beginUpdate()
    let transition = state.endUpdate()
    check transition.changed
    check not transition.shouldPresent

  test "end without begin is ignored":
    var state = newSyncUpdateState()
    let transition = state.endUpdate()
    check not transition.changed
    check state.endCount == 1

  test "set active dispatches to begin and end":
    var state = newSyncUpdateState()
    check state.setActive(true).entered
    check state.setActive(false).exited

  test "force end times out a stuck bracket":
    var state = newSyncUpdateState()
    discard state.beginUpdate()
    state.markDirty()
    state.noteBeginTime(1.0)
    let early = state.forceEndIfTimedOut(1.1, maxSec = 0.25)
    check state.active
    check not early.changed
    let late = state.forceEndIfTimedOut(1.5, maxSec = 0.25)
    check not state.active
    check late.exited
    check late.shouldPresent
