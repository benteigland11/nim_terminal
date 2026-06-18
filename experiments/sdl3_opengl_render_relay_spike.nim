## Experimental SDL3 + OpenGL render-relay adapter.
##
## This is the custom GPU escape hatch we need beside uirelays' stock SDL3
## renderer. SDL3 owns the cross-platform window/context/present mechanics,
## while Waymark-style rendering calls through the render relay contract.
##
## Compile from the repo root with:
##   nim c -d:sdl3 --nimcache:./.nimcache/sdl3_gl_spike experiments/sdl3_opengl_render_relay_spike.nim
##
## For an automated one-frame smoke:
##   WAYMARK_SDL3_GL_SPIKE_FRAMES=1 ./experiments/sdl3_opengl_render_relay_spike

when not defined(sdl3):
  {.fatal: "This spike is intentionally SDL3-only. Rebuild with -d:sdl3.".}

import opengl
import sdl3
import std/[math, os, strutils]
from ../cg/frontend_render_relays_nim/src/render_relays_lib as render_relay_lib import nil

type
  SdlGlSurface = ref object
    window: Window
    context: GLContext
    width: int
    height: int

func glColor(c: render_relay_lib.RenderColor): tuple[r, g, b, a: GLclampf] =
  (
    GLclampf(c.r),
    GLclampf(c.g),
    GLclampf(c.b),
    GLclampf(c.a),
  )

proc sdlError(message: string): string =
  message & ": " & $getError()

proc newSdlGlSurface(title: string; width, height: int): SdlGlSurface =
  if not init(INIT_VIDEO):
    raise newException(OSError, sdlError("SDL_Init failed"))

  discard gL_SetAttribute(GL_CONTEXT_MAJOR_VERSION, 2)
  discard gL_SetAttribute(GL_CONTEXT_MINOR_VERSION, 1)
  discard gL_SetAttribute(GL_DOUBLEBUFFER, 1)
  discard gL_SetAttribute(GL_DEPTH_SIZE, 0)
  discard gL_SetAttribute(GL_STENCIL_SIZE, 0)

  let flags = WINDOW_OPENGL or WINDOW_RESIZABLE or WINDOW_HIGH_PIXEL_DENSITY
  let window = createWindow(cstring(title), cint(width), cint(height), flags)
  if window == nil:
    quit(sdlError("SDL_CreateWindow failed"))

  let context = gL_CreateContext(window)
  if context == nil:
    destroyWindow(window)
    quit(sdlError("SDL_GL_CreateContext failed"))

  if not gL_MakeCurrent(window, context):
    discard gL_DestroyContext(context)
    destroyWindow(window)
    quit(sdlError("SDL_GL_MakeCurrent failed"))

  loadExtensions()
  discard gL_SetSwapInterval(1)

  result = SdlGlSurface(window: window, context: context, width: width, height: height)

proc close(surface: SdlGlSurface) =
  if surface == nil:
    return
  if surface.context != nil:
    discard gL_DestroyContext(surface.context)
    surface.context = nil
  if surface.window != nil:
    destroyWindow(surface.window)
    surface.window = nil
  sdl3.quit()

proc installRelays(surface: SdlGlSurface): render_relay_lib.RenderRelays =
  render_relay_lib.RenderRelays(
    frame: render_relay_lib.RenderFrameRelays(
      setViewport: proc (size: render_relay_lib.RenderSize) =
        surface.width = size.width
        surface.height = size.height
        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height)),
      clear: proc (color: render_relay_lib.RenderColor) =
        let c = glColor(color)
        glClearColor(c.r, c.g, c.b, c.a)
        glClear(GL_COLOR_BUFFER_BIT),
      flush: proc () =
        glFlush(),
      present: proc () =
        discard gL_SwapWindow(surface.window),
    )
  )

proc frameLimit(): int =
  parseInt(getEnv("WAYMARK_SDL3_GL_SPIKE_FRAMES", "0"))

proc drawSimpleGpuFrame(surface: SdlGlSurface; t: float32) =
  let pulse = (sin(t) + 1.0'f32) * 0.5'f32

  glDisable(GL_TEXTURE_2D)
  glBegin(GL_TRIANGLES)
  glColor4f(1.0, 0.82, 0.12, 1.0)
  glVertex2f(-0.65, -0.45)
  glColor4f(0.18, 0.90, 0.52, 1.0)
  glVertex2f(0.65, -0.45)
  glColor4f(0.35 + pulse * 0.45, 0.55, 1.0, 1.0)
  glVertex2f(0.0, 0.55)
  glEnd()

  glBegin(GL_LINE_LOOP)
  glColor4f(1.0, 0.82, 0.12, 1.0)
  glVertex2f(-0.92, -0.86)
  glVertex2f(0.92, -0.86)
  glVertex2f(0.92, 0.86)
  glVertex2f(-0.92, 0.86)
  glEnd()

proc main() =
  let surface = newSdlGlSurface("Waymark SDL3 OpenGL relay spike", 900, 560)
  let relays = installRelays(surface)
  let maxFrames = frameLimit()
  var frames = 0
  var running = true

  while running:
    var event: Event
    while pollEvent(event):
      let evType = uint32(event.common.`type`)
      if evType == uint32(EVENT_QUIT) or evType == uint32(EVENT_WINDOW_CLOSE_REQUESTED):
        running = false
      elif evType == uint32(EVENT_WINDOW_RESIZED) or evType == uint32(EVENT_WINDOW_PIXEL_SIZE_CHANGED):
        surface.width = max(1, event.window.data1)
        surface.height = max(1, event.window.data2)
      elif evType == uint32(EVENT_KEY_DOWN) and event.key.key == SDLK_ESCAPE:
        running = false

    render_relay_lib.beginFrame(
      relays,
      render_relay_lib.size2d(surface.width, surface.height),
      render_relay_lib.rgba8(5, 6, 7),
    )
    drawSimpleGpuFrame(surface, float32(frames) / 30.0)
    render_relay_lib.endFrame(relays)

    inc frames
    if maxFrames > 0 and frames >= maxFrames:
      running = false
    delay(16)

  surface.close()

main()
