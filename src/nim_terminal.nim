## Nim Terminal Prototype.
##
## Main entry point: creates a window, loads a font, and runs the
## terminal pipeline with a Pixie-based renderer.

import staticglfw
import opengl
import pixie
import os
import terminal
import gpu_renderer
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
from ../cg/frontend_glfw_input_nim/src/glfw_input_lib import toKeyCode, toModifiers

const
  WindowTitle = "Nim Terminal"
  DefaultFontSize = 14.0
  FontPath = "/usr/share/fonts/liberation-mono-fonts/LiberationMono-Regular.ttf"

var 
  term: Terminal
  rend: GpuTerminalRenderer
  window: Window
  winWidth = 1280
  winHeight = 720

# ---------------------------------------------------------------------------
# GLFW Callbacks
# ---------------------------------------------------------------------------

proc onChar(win: Window, codepoint: cuint) {.cdecl.} =
  discard term.sendKey(keyChar(uint32(codepoint)))

proc onKey(win: Window, key, scancode, action, mods: cint) {.cdecl.} =
  if action == PRESS or action == REPEAT:
    let k = toKeyCode(key).int.KeyCode
    if k != kNone and k != kChar:
      let m = cast[set[Modifier]](toModifiers(mods))
      discard term.sendKey(key(k, m))

proc onResize(win: Window, width, height: cint) {.cdecl.} =
  winWidth = int(width)
  winHeight = int(height)
  let cols = winWidth div rend.atlas.cellWidth
  let rows = winHeight div rend.atlas.cellHeight
  if cols > 0 and rows > 0:
    term.resize(cols, rows)
    glViewport(0, 0, width, height)

proc onScroll(win: Window, xoffset, yoffset: cdouble) {.cdecl.} =
  if yoffset > 0:
    term.viewport.scrollUp(3)
  elif yoffset < 0:
    term.viewport.scrollDown(3)
  term.damage.markAll()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if init() == 0:
  quit("Failed to init GLFW")

windowHint(CONTEXT_VERSION_MAJOR, 2)
windowHint(CONTEXT_VERSION_MINOR, 1)

window = createWindow(cint(winWidth), cint(winHeight), WindowTitle, nil, nil)
if window == nil:
  quit("Failed to create window")

makeContextCurrent(window)
loadExtensions()

# Setup Terminal logic
let font = readFont(FontPath)
font.paint.color = color(1, 1, 1, 1) # White text
let atlas = newGlyphAtlas(font, DefaultFontSize)
term = newTerminal("/bin/sh", ["-i"])
rend = newGpuTerminalRenderer(atlas)

# Set callbacks
discard window.setCharCallback(onChar)
discard window.setKeyCallback(onKey)
discard window.setFramebufferSizeCallback(onResize)
discard window.setScrollCallback(onScroll)

# Initial resize
onResize(window, cint(winWidth), cint(winHeight))

while windowShouldClose(window) == 0:
  # 1. Process PTY data
  let n = term.step()
  if n > 0:
    term.refreshViewport(stickToBottom = true)
  
  # 2. Update atlas if needed (new glyphs rendered)
  let atlasChanged = atlas.isDirty
  if atlasChanged:
    rend.updateAtlasTexture()

  # 3. Render ONLY if something changed
  if n > 0 or atlasChanged or term.damage.anyDirty:
    rend.draw(term, winWidth, winHeight)
    swapBuffers(window)
  else:
    # Idle - don't burn CPU
    os.sleep(1)
  
  pollEvents()

terminate()
