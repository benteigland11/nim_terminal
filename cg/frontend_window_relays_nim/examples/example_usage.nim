import window_relays_lib

var position = point(100, 200)
var closed = false

let relays = WindowRelays(
  geometry: WindowGeometryRelays(
    getPosition: proc (): WindowPoint = position,
    setPosition: proc (next: WindowPoint) =
      position = next,
    getWindowSize: proc (): WindowSize = size2d(800, 600),
    getDrawableSize: proc (): WindowSize = size2d(1600, 1200),
  ),
  lifecycle: WindowLifecycleRelays(
    shouldClose: proc (): bool = closed,
    requestClose: proc () =
      closed = true,
  ),
)

relays.setPosition(point(120, 240))
doAssert relays.getPosition() == point(120, 240)
doAssert relays.getDrawableSize().isPositive
relays.requestClose()
doAssert relays.shouldClose()
