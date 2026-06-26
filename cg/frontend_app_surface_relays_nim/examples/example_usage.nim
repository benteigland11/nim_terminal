## Example usage of App Surface Relays.

import app_surface_relays_lib

var drew = false
let stack = newAppSurfaceStack()
stack.registerSurface(SurfaceRelays(
  id: asPrimary,
  label: "Terminal",
  draw: proc () = discard,
))
stack.registerSurface(SurfaceRelays(
  id: asWorkspace,
  label: "Agent",
  activate: proc () = drew = false,
  draw: proc () = drew = true,
  needsRedraw: proc (): bool = not drew,
))

switchSurface(stack, asWorkspace)
drawActive(stack)
doAssert drew
doAssert parseAppSurfaceId("agent") == asWorkspace
