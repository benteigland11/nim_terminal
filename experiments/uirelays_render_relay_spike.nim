## Experimental uirelays render-relay adapter.
##
## This is deliberately not part of the production Waymark launch path. It
## proves that a uirelays backend can install the same frame-level relay shape
## that the GLFW/OpenGL path now uses.
##
## Compile from the repo root with:
##   nim c -d:sdl3 --path:/home/Vinscen/Nim/uirelays/src experiments/uirelays_render_relay_spike.nim
##
## For an automated one-frame smoke:
##   WAYMARK_UIRELAYS_SPIKE_FRAMES=1 ./experiments/uirelays_render_relay_spike

import std/[os, strutils]
import uirelays as ui
from ../cg/frontend_render_relays_nim/src/render_relays_lib as render_relay_lib import nil

when not defined(sdl3):
  {.fatal: "This spike is intentionally SDL3-only. Rebuild with -d:sdl3.".}

type
  SpikeState = object
    width: int
    height: int
    mouseX: int
    mouseY: int
    wheelY: int
    typed: string
    focused: bool

func clampByte(value: float32): uint8 =
  uint8(max(0, min(255, int(value * 255.0))))

func toUiColor(color: render_relay_lib.RenderColor): ui.Color =
  ui.color(
    clampByte(color.r),
    clampByte(color.g),
    clampByte(color.b),
    clampByte(color.a),
  )

proc installUirelaysFrameRelays(state: ptr SpikeState): render_relay_lib.RenderRelays =
  render_relay_lib.RenderRelays(
    frame: render_relay_lib.RenderFrameRelays(
      setViewport: proc (size: render_relay_lib.RenderSize) =
        state.width = size.width
        state.height = size.height,
      clear: proc (color: render_relay_lib.RenderColor) =
        ui.fillRect(ui.rect(0, 0, state.width, state.height), toUiColor(color)),
      flush: proc () =
        discard,
      present: proc () =
        ui.refresh(),
    )
  )

proc appendTextInput(target: var string; input: array[4, char]) =
  for ch in input:
    if ch == '\0':
      break
    target.add ch

proc configuredFrameLimit(): int =
  parseInt(getEnv("WAYMARK_UIRELAYS_SPIKE_FRAMES", "0"))

proc main() =
  let layout = ui.createWindow(800, 520)
  var state = SpikeState(width: layout.width, height: layout.height, focused: true)
  let relays = installUirelaysFrameRelays(addr state)

  var metrics: ui.FontMetrics
  let font = ui.openFont("", 18, metrics)
  ui.setWindowTitle("Waymark uirelays render-relay spike")

  let frameLimit = configuredFrameLimit()
  var frames = 0
  var running = true
  while running:
    var event: ui.Event
    while ui.pollEvent(event, {ui.WantTextInput}):
      case event.kind
      of ui.QuitEvent, ui.WindowCloseEvent:
        running = false
      of ui.WindowResizeEvent:
        state.width = event.x
        state.height = event.y
      of ui.WindowFocusGainedEvent:
        state.focused = true
      of ui.WindowFocusLostEvent:
        state.focused = false
      of ui.MouseMoveEvent:
        state.mouseX = event.x
        state.mouseY = event.y
      of ui.MouseWheelEvent:
        state.wheelY += event.y
      of ui.TextInputEvent:
        state.typed.appendTextInput(event.text)
        if state.typed.len > 40:
          state.typed = state.typed[^40 .. ^1]
      of ui.KeyDownEvent:
        if event.key == ui.KeyEsc:
          running = false
        elif event.key == ui.KeyC and ui.CtrlPressed in event.mods:
          ui.putClipboardText("Waymark uirelays clipboard smoke")
        elif event.key == ui.KeyV and ui.CtrlPressed in event.mods:
          state.typed.add ui.getClipboardText()
      else:
        discard

    render_relay_lib.beginFrame(
      relays,
      render_relay_lib.size2d(state.width, state.height),
      render_relay_lib.rgba8(5, 6, 7),
    )

    ui.fillRect(ui.rect(0, 0, state.width, 34), ui.color(33, 38, 43))
    ui.fillRect(ui.rect(0, 34, state.width, 1), ui.color(250, 210, 40))
    discard ui.drawText(font, 12, 8, "Waymark uirelays relay spike", ui.color(235, 241, 245), ui.color(33, 38, 43))

    let status =
      "size=" & $state.width & "x" & $state.height &
      " mouse=" & $state.mouseX & "," & $state.mouseY &
      " wheel=" & $state.wheelY &
      " focus=" & $state.focused
    discard ui.drawText(font, 18, 74, status, ui.color(205, 214, 220), ui.color(5, 6, 7))
    discard ui.drawText(font, 18, 112, "type text, Ctrl+C copies, Ctrl+V pastes, Esc exits", ui.color(150, 158, 168), ui.color(5, 6, 7))
    discard ui.drawText(font, 18, 150, "typed: " & state.typed, ui.color(250, 210, 40), ui.color(5, 6, 7))

    render_relay_lib.endFrame(relays)

    inc frames
    if frameLimit > 0 and frames >= frameLimit:
      running = false
    ui.sleep(16)

  if font != ui.Font(0):
    ui.closeFont(font)
  ui.shutdown()

main()
