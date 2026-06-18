import std/unittest
import render_relays_lib

suite "Render Relays":
  test "size clamps negative dimensions":
    check size2d(-10, 5) == RenderSize(width: 0, height: 5)
    check size2d(12, -1) == RenderSize(width: 12, height: 0)

  test "rgba8 normalizes channels":
    let c = rgba8(255, 128, 0, 64)
    check c.r == 1.0
    check c.g > 0.50 and c.g < 0.51
    check c.b == 0.0
    check c.a > 0.25 and c.a < 0.26

  test "noop relays are safe to call":
    let relays = noopRenderRelays()
    relays.beginFrame(size2d(80, 24), rgba(0, 0, 0))
    relays.endFrame()

  test "begin and end frame call installed relays in order":
    var calls: seq[string] = @[]
    var seenSize = size2d(0, 0)
    var seenColor = rgba(0, 0, 0, 0)
    var relays = RenderRelays()
    relays.frame.setViewport = proc (size: RenderSize) =
      calls.add "viewport"
      seenSize = size
    relays.frame.clear = proc (color: RenderColor) =
      calls.add "clear"
      seenColor = color
    relays.frame.flush = proc () =
      calls.add "flush"
    relays.frame.present = proc () =
      calls.add "present"

    relays.beginFrame(size2d(100, 40), rgba8(10, 20, 30))
    relays.endFrame()

    check calls == @["viewport", "clear", "flush", "present"]
    check seenSize == size2d(100, 40)
    check seenColor.r > 0.03 and seenColor.r < 0.04
    check seenColor.g > 0.07 and seenColor.g < 0.08
    check seenColor.b > 0.11 and seenColor.b < 0.12
