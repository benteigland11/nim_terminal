## Application surface relay contract.
##
## Lets a host application swap between major UI surfaces (for example a
## terminal view and a workspace view) while keeping windowing, GPU, and
## render relays shared. Each surface installs activate, tick, draw, and
## redraw hooks at the application boundary.

import std/strutils

type
  AppSurfaceId* = enum
    asPrimary = "primary"
    asWorkspace = "workspace"

  SurfaceToggleRect* = object
    x*, y*, width*, height*: int

  SurfaceRelays* = object
    id*: AppSurfaceId
    label*: string
    activate*: proc () {.closure.}
    deactivate*: proc () {.closure.}
    tick*: proc (): int {.closure.}
    draw*: proc () {.closure.}
    needsRedraw*: proc (): bool {.closure.}

  AppSurfaceStack* = ref object
    active*: AppSurfaceId
    surfaces*: seq[SurfaceRelays]

func newAppSurfaceStack*(initial = asPrimary): AppSurfaceStack =
  AppSurfaceStack(active: initial, surfaces: @[])

proc registerSurface*(stack: AppSurfaceStack; relays: SurfaceRelays) =
  for i, surface in stack.surfaces:
    if surface.id == relays.id:
      stack.surfaces[i] = relays
      return
  stack.surfaces.add relays

func findSurface*(stack: AppSurfaceStack; id: AppSurfaceId): SurfaceRelays =
  for surface in stack.surfaces:
    if surface.id == id:
      return surface
  SurfaceRelays(id: id)

func activeSurface*(stack: AppSurfaceStack): SurfaceRelays =
  stack.findSurface(stack.active)

proc switchSurface*(stack: AppSurfaceStack; id: AppSurfaceId) =
  if stack.active == id:
    return
  let previous = stack.findSurface(stack.active)
  if previous.deactivate != nil:
    previous.deactivate()
  stack.active = id
  let next = stack.findSurface(id)
  if next.activate != nil:
    next.activate()

proc tickActive*(stack: AppSurfaceStack): int =
  let surface = stack.activeSurface()
  if surface.tick != nil:
    surface.tick()
  else:
    0

proc drawActive*(stack: AppSurfaceStack) =
  let surface = stack.activeSurface()
  if surface.draw != nil:
    surface.draw()

proc activeNeedsRedraw*(stack: AppSurfaceStack): bool =
  let surface = stack.activeSurface()
  if surface.needsRedraw != nil:
    surface.needsRedraw()
  else:
    false

func parseAppSurfaceId*(value: string; fallback = asPrimary): AppSurfaceId =
  case value.strip().toLowerAscii()
  of "workspace", "agent", "power", "power_user", "power-user":
    asWorkspace
  of "primary", "terminal", "standard", "base", "default":
    asPrimary
  else:
    fallback

func surfaceToggleRect*(winWidth, titleBarHeight: int): SurfaceToggleRect =
  let width = max(88, min(132, winWidth div 5))
  let height = max(18, titleBarHeight - 8)
  SurfaceToggleRect(
    x: max(0, winWidth - width - 10),
    y: max(2, (titleBarHeight - height) div 2),
    width: width,
    height: height,
  )

func surfaceToggleHitTest*(x, y, winWidth, titleBarHeight: int): bool =
  let rect = surfaceToggleRect(winWidth, titleBarHeight)
  x >= rect.x and x < rect.x + rect.width and
    y >= rect.y and y < rect.y + rect.height

func workspaceHeaderHeight*(titleBarHeight, tabBarHeight: int; surface: AppSurfaceId): int =
  case surface
  of asPrimary:
    titleBarHeight + tabBarHeight
  of asWorkspace:
    titleBarHeight
