## Example usage of Terminal Sync Update.

import terminal_sync_update_lib

var state = newSyncUpdateState()

let entered = state.beginUpdate()
doAssert entered.entered
doAssert state.shouldDeferPresent()

state.markDirty()
let exited = state.endUpdate()
doAssert exited.shouldPresent
doAssert not state.shouldDeferPresent()
