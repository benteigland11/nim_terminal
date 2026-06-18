## Small rendering relay contract.
##
## The widget owns the backend-neutral frame operations. Applications install
## concrete procedures for a windowing/rendering backend, then higher-level
## drawing code calls this contract instead of importing that backend directly.

type
  RenderColor* = object
    r*, g*, b*, a*: float32

  RenderSize* = object
    width*, height*: int

  RenderFrameRelays* = object
    setViewport*: proc (size: RenderSize) {.closure.}
    clear*: proc (color: RenderColor) {.closure.}
    flush*: proc () {.closure.}
    present*: proc () {.closure.}

  RenderRelays* = object
    frame*: RenderFrameRelays

func rgba*(r, g, b: float32; a: float32 = 1.0): RenderColor =
  RenderColor(r: r, g: g, b: b, a: a)

func rgba8*(r, g, b: uint8; a: uint8 = 255): RenderColor =
  rgba(
    r.float32 / 255.0,
    g.float32 / 255.0,
    b.float32 / 255.0,
    a.float32 / 255.0,
  )

func size2d*(width, height: int): RenderSize =
  RenderSize(width: max(0, width), height: max(0, height))

func noopRenderRelays*(): RenderRelays =
  RenderRelays()

proc setViewport*(relays: RenderRelays; size: RenderSize) =
  if relays.frame.setViewport != nil:
    relays.frame.setViewport(size)

proc clear*(relays: RenderRelays; color: RenderColor) =
  if relays.frame.clear != nil:
    relays.frame.clear(color)

proc flush*(relays: RenderRelays) =
  if relays.frame.flush != nil:
    relays.frame.flush()

proc present*(relays: RenderRelays) =
  if relays.frame.present != nil:
    relays.frame.present()

proc beginFrame*(relays: RenderRelays; size: RenderSize; clearColor: RenderColor) =
  relays.setViewport(size)
  relays.clear(clearColor)

proc endFrame*(relays: RenderRelays) =
  relays.flush()
  relays.present()
