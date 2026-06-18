import render_relays_lib

var presented = false
var relays = RenderRelays()

relays.frame.setViewport = proc (size: RenderSize) =
  doAssert size == size2d(640, 480)

relays.frame.clear = proc (color: RenderColor) =
  doAssert color.a == 1.0

relays.frame.flush = proc () =
  discard

relays.frame.present = proc () =
  presented = true

relays.beginFrame(size2d(640, 480), rgba8(8, 10, 12))
relays.endFrame()

doAssert presented
