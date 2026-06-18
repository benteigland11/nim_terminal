## Backend-neutral window operation relay contract.
##
## Applications install concrete procedures for their windowing backend, then
## core UI logic can query position, size, close state, and pointer state
## without importing SDL, GLFW, WinAPI, X11, or another specific toolkit.

type
  WindowPoint* = object
    x*, y*: int

  WindowSize* = object
    width*, height*: int

  MouseButton* = enum
    mbLeft
    mbMiddle
    mbRight

  WindowGeometryRelays* = object
    getPosition*: proc (): WindowPoint {.closure.}
    setPosition*: proc (point: WindowPoint) {.closure.}
    getWindowSize*: proc (): WindowSize {.closure.}
    getDrawableSize*: proc (): WindowSize {.closure.}
    setMinimumSize*: proc (size: WindowSize) {.closure.}

  WindowInputRelays* = object
    isMouseButtonDown*: proc (button: MouseButton): bool {.closure.}

  WindowLifecycleRelays* = object
    shouldClose*: proc (): bool {.closure.}
    requestClose*: proc () {.closure.}

  WindowRelays* = object
    geometry*: WindowGeometryRelays
    input*: WindowInputRelays
    lifecycle*: WindowLifecycleRelays

func point*(x, y: int): WindowPoint =
  WindowPoint(x: x, y: y)

func size2d*(width, height: int): WindowSize =
  WindowSize(width: max(0, width), height: max(0, height))

func isPositive*(size: WindowSize): bool =
  size.width > 0 and size.height > 0

func noopWindowRelays*(): WindowRelays =
  WindowRelays()

proc getPosition*(relays: WindowRelays): WindowPoint =
  if relays.geometry.getPosition == nil:
    return point(0, 0)
  relays.geometry.getPosition()

proc setPosition*(relays: WindowRelays; position: WindowPoint) =
  if relays.geometry.setPosition != nil:
    relays.geometry.setPosition(position)

proc getWindowSize*(relays: WindowRelays): WindowSize =
  if relays.geometry.getWindowSize == nil:
    return size2d(0, 0)
  relays.geometry.getWindowSize()

proc getDrawableSize*(relays: WindowRelays): WindowSize =
  if relays.geometry.getDrawableSize == nil:
    return relays.getWindowSize()
  relays.geometry.getDrawableSize()

proc setMinimumSize*(relays: WindowRelays; size: WindowSize) =
  if relays.geometry.setMinimumSize != nil and size.isPositive:
    relays.geometry.setMinimumSize(size)

proc isMouseButtonDown*(relays: WindowRelays; button: MouseButton): bool =
  if relays.input.isMouseButtonDown == nil:
    return false
  relays.input.isMouseButtonDown(button)

proc shouldClose*(relays: WindowRelays): bool =
  if relays.lifecycle.shouldClose == nil:
    return false
  relays.lifecycle.shouldClose()

proc requestClose*(relays: WindowRelays) =
  if relays.lifecycle.requestClose != nil:
    relays.lifecycle.requestClose()
