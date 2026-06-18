import std/unittest
import ../src/window_relays_lib

suite "Window Relays":
  test "noop relays are safe":
    let relays = noopWindowRelays()
    check relays.getPosition() == point(0, 0)
    check relays.getWindowSize() == size2d(0, 0)
    check relays.getDrawableSize() == size2d(0, 0)
    check not relays.isMouseButtonDown(mbLeft)
    check not relays.shouldClose()
    relays.setPosition(point(10, 20))
    relays.setMinimumSize(size2d(80, 24))
    relays.requestClose()

  test "geometry relay forwards position and size":
    var saved = point(1, 2)
    var minSize = size2d(0, 0)
    let relays = WindowRelays(
      geometry: WindowGeometryRelays(
        getPosition: proc (): WindowPoint = saved,
        setPosition: proc (point: WindowPoint) =
          saved = point,
        getWindowSize: proc (): WindowSize = size2d(640, 480),
        getDrawableSize: proc (): WindowSize = size2d(1280, 960),
        setMinimumSize: proc (size: WindowSize) =
          minSize = size,
      )
    )
    check relays.getPosition() == point(1, 2)
    relays.setPosition(point(3, 4))
    check saved == point(3, 4)
    check relays.getWindowSize() == size2d(640, 480)
    check relays.getDrawableSize() == size2d(1280, 960)
    relays.setMinimumSize(size2d(100, 50))
    check minSize == size2d(100, 50)

  test "input and lifecycle relays forward state":
    var closeRequested = false
    let relays = WindowRelays(
      input: WindowInputRelays(
        isMouseButtonDown: proc (button: MouseButton): bool =
          button == mbLeft,
      ),
      lifecycle: WindowLifecycleRelays(
        shouldClose: proc (): bool = closeRequested,
        requestClose: proc () =
          closeRequested = true,
      )
    )
    check relays.isMouseButtonDown(mbLeft)
    check not relays.isMouseButtonDown(mbRight)
    check not relays.shouldClose()
    relays.requestClose()
    check relays.shouldClose()
