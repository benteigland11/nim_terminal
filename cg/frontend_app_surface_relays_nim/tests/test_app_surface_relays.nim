import std/unittest
import app_surface_relays_lib

suite "app surface relays":
  test "switch surface calls lifecycle hooks":
    var events: seq[string] = @[]
    let stack = newAppSurfaceStack()
    stack.registerSurface(SurfaceRelays(
      id: asPrimary,
      label: "Terminal",
      activate: proc () = events.add("primary:on"),
      deactivate: proc () = events.add("primary:off"),
    ))
    stack.registerSurface(SurfaceRelays(
      id: asWorkspace,
      label: "Agent",
      activate: proc () = events.add("workspace:on"),
      deactivate: proc () = events.add("workspace:off"),
    ))

    switchSurface(stack, asWorkspace)
    check stack.active == asWorkspace
    check events == @["primary:off", "workspace:on"]

    switchSurface(stack, asWorkspace)
    check events.len == 2

  test "toggle rect hit testing":
    let rect = surfaceToggleRect(640, 30)
    check rect.width > 0
    check surfaceToggleHitTest(rect.x + 1, rect.y + 1, 640, 30)
    check not surfaceToggleHitTest(0, 0, 640, 30)

  test "workspace header is shorter than primary header":
    check workspaceHeaderHeight(30, 28, asPrimary) == 58
    check workspaceHeaderHeight(30, 28, asWorkspace) == 30
