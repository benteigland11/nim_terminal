## Nim Terminal Prototype.
##
## Main entry point: creates a window, loads a font, and runs the
## terminal pipeline with a Pixie-based renderer.

import staticglfw
import opengl
import pixie
import os
import std/options
import terminal
import gpu_renderer
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
from ../cg/frontend_glfw_input_nim/src/glfw_input_lib import toKeyCode, toModifiers, toMouseButton
import ../cg/universal_perf_monitor_nim/src/perf_monitor_lib
import ../cg/universal_shortcut_map_nim/src/shortcut_map_lib

const
  WindowTitle = "Nim Terminal"
  FontPath = "/usr/share/fonts/liberation-mono-fonts/LiberationMono-Regular.ttf"

var 
  term: Terminal
  rend: GpuTerminalRenderer
  window: Window
  winWidth = 1280
  winHeight = 720
  fontSize = 14.0
  font: Font

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func castSet(s: cint): set[terminal.Modifier] =
  if (s and MOD_SHIFT) != 0: result.incl terminal.modShift
  if (s and MOD_ALT) != 0: result.incl terminal.modAlt
  if (s and MOD_CONTROL) != 0: result.incl terminal.modCtrl
  if (s and MOD_SUPER) != 0: result.incl terminal.modSuper

proc rebuildAtlas() =
  font = readFont(FontPath)
  font.size = fontSize
  font.paint.color = color(1, 1, 1, 1)
  let atlas = newGlyphAtlas(font, fontSize)
  rend = newGpuTerminalRenderer(atlas)
  let cols = winWidth div rend.atlas.cellWidth
  let rows = winHeight div rend.atlas.cellHeight
  if cols > 0 and rows > 0: term.resize(cols, rows)
  term.damage.markAll()

# ---------------------------------------------------------------------------
# GLFW Callbacks
# ---------------------------------------------------------------------------

proc onChar(win: Window, codepoint: cuint) {.cdecl.} =
  discard term.sendKey(keyChar(uint32(codepoint)))
  term.damage.markAll()

proc onKey(win: Window, key, scancode, action, mods: cint) {.cdecl.} =
  if action == PRESS or action == REPEAT:
    let m = castSet(mods)
    
    # 1. Map GLFW key to ShortcutMap.KeyCode
    var sk: shortcut_map_lib.KeyCode
    case key
    of KEY_EQUAL: sk = shortcut_map_lib.kEqual
    of KEY_MINUS: sk = shortcut_map_lib.kMinus
    of KEY_KP_ADD: sk = shortcut_map_lib.kPlus
    of KEY_KP_SUBTRACT: sk = shortcut_map_lib.kMinus
    else:
      if key >= 32 and key <= 126: sk = shortcut_map_lib.key(char(key))
      else: sk = shortcut_map_lib.kNone
    
    # 2. Lookup high-level actions
    let actionName = term.shortcuts.lookup(sk, cast[set[shortcut_map_lib.Modifier]](m))
    if actionName.isSome:
      case actionName.get()
      of "copy":
        if term.selection.isActive:
          let text = term.selection.extractText(term.screen.cols) do (r: int) -> seq[CellData]:
            let row = term.screen.absoluteRowAt(r)
            var res = newSeq[CellData](row.len)
            for i, c in row: res[i] = CellData(rune: c.rune, width: int(c.width))
            res
          window.setClipboardString(text)
        return
      of "paste":
        let text = window.getClipboardString()
        if text != nil: discard term.sendPaste($text)
        return
      of "zoom-in": fontSize += 1.0; rebuildAtlas(); return
      of "zoom-out": fontSize = max(4.0, fontSize - 1.0); rebuildAtlas(); return
      else: discard

    # 3. Standard keys
    let tk = toKeyCode(key).int
    if tk != 0 and tk != 1: # 0 = kNone, 1 = kChar
      discard term.sendKey(terminal.key(cast[terminal.KeyCode](tk), m))
      term.damage.markAll()

proc onMouseButton(win: Window, button, action, mods: cint) {.cdecl.} =
  var x, y: cdouble; getCursorPos(win, addr x, addr y)
  let col = int(x) div rend.atlas.cellWidth; let row = int(y) div rend.atlas.cellHeight
  let absRow = term.viewport.viewportToBuffer(row)
  if term.inputMode.shouldIntercept(castSet(mods)):
    if button == MOUSE_BUTTON_LEFT:
      let isDown = action == PRESS
      term.drag.update(absRow, col, isDown)
      if isDown: term.selection.start(point(absRow, col))
      term.damage.markAll()
  else:
    let tmb = toMouseButton(button).int
    discard term.sendMouse(mouse(if action == PRESS: mePress else: meRelease, cast[terminal.MouseButton](tmb), row, col, castSet(mods)))

proc onCursorPos(win: Window, x, y: cdouble) {.cdecl.} =
  let col = int(x) div rend.atlas.cellWidth; let row = int(y) div rend.atlas.cellHeight
  let absRow = term.viewport.viewportToBuffer(row)
  if term.drag.state != dsIdle:
    term.drag.update(absRow, col, true); term.selection.update(point(absRow, col))
    if term.drag.state == dsOutsideTop: term.viewport.scrollUp(1)
    elif term.drag.state == dsOutsideBottom: term.viewport.scrollDown(1)
    term.refreshViewport(false); term.damage.markAll()

proc onScroll(win: Window, xoffset, yoffset: cdouble) {.cdecl.} =
  let ctrlDown = (getKey(window, KEY_LEFT_CONTROL) == PRESS or getKey(window, KEY_RIGHT_CONTROL) == PRESS)
  if ctrlDown:
    if yoffset > 0: fontSize += 1.0
    elif yoffset < 0: fontSize = max(4.0, fontSize - 1.0)
    rebuildAtlas()
  else:
    if yoffset > 0: term.viewport.scrollUp(3)
    elif yoffset < 0: term.viewport.scrollDown(3)
  term.refreshViewport(false); term.damage.markAll()

proc onResize(win: Window, width, height: cint) {.cdecl.} =
  winWidth = int(width); winHeight = int(height)
  if rend != nil and rend.atlas != nil:
    let cols = winWidth div rend.atlas.cellWidth; let rows = winHeight div rend.atlas.cellHeight
    if cols > 0 and rows > 0: term.resize(cols, rows); glViewport(0, 0, width, height)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if init() == 0: quit("Failed to init GLFW")
windowHint(CONTEXT_VERSION_MAJOR, 2); windowHint(CONTEXT_VERSION_MINOR, 1)
window = createWindow(cint(winWidth), cint(winHeight), WindowTitle, nil, nil)
if window == nil: quit("Failed to create window")
makeContextCurrent(window); loadExtensions()

font = readFont(FontPath); font.size = fontSize; font.paint.color = color(1, 1, 1, 1)
let atlas = newGlyphAtlas(font, fontSize)
term = newTerminal("/bin/sh", ["-i"]); rend = newGpuTerminalRenderer(atlas)

discard window.setCharCallback(onChar); discard window.setKeyCallback(onKey)
discard window.setMouseButtonCallback(onMouseButton); discard window.setCursorPosCallback(onCursorPos)
discard window.setScrollCallback(onScroll); discard window.setFramebufferSizeCallback(onResize)

onResize(window, cint(winWidth), cint(winHeight))

let perf = newPerfMonitor()
while windowShouldClose(window) == 0:
  perf.beginFrame()
  let n = term.step()
  if n > 0: term.refreshViewport(stickToBottom = true)
  if atlas.isDirty: rend.updateAtlasTexture()
  let changed = n > 0 or atlas.isDirty or term.damage.anyDirty
  if changed: (rend.draw(term, winWidth, winHeight); swapBuffers(window))
  pollEvents(); perf.endFrame()
  if perf.shouldReport(2.0):
    let s = perf.takeReport()
    echo "FPS: ", s.fps, " Latency: ", s.avgLatencyMs, " ms"
  if not changed: os.sleep(1)

terminate()
