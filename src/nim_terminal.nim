## Nim Terminal Prototype.
##
## Main entry point: creates a window, loads a font, and runs the
## terminal pipeline with a Pixie-based renderer.

import staticglfw
import opengl
import pixie
import terminal
import renderer
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
from ../cg/frontend_glfw_input_nim/src/glfw_input_lib import toKeyCode, toModifiers

const
  WindowTitle = "Nim Terminal"
  DefaultFontSize = 14.0
  FontPath = "/usr/share/fonts/liberation-mono-fonts/LiberationMono-Regular.ttf"

var 
  term: Terminal
  rend: TerminalRenderer
  window: Window
  texId: uint32

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
  let cols = int(width) div rend.atlas.cellWidth
  let rows = int(height) div rend.atlas.cellHeight
  if cols > 0 and rows > 0:
    term.resize(cols, rows)
    rend.surface = newImage(int(width), int(height))
    glViewport(0, 0, width, height)

# ---------------------------------------------------------------------------
# Initialization
# ---------------------------------------------------------------------------

proc initGL() =
  loadExtensions()
  glClearColor(0, 0, 0, 1)
  glEnable(GL_TEXTURE_2D)
  glGenTextures(1, addr texId)
  glBindTexture(GL_TEXTURE_2D, texId)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)

proc updateTexture(img: Image) =
  glBindTexture(GL_TEXTURE_2D, texId)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, cint(img.width), cint(img.height),
               0, GL_RGBA, GL_UNSIGNED_BYTE, addr img.data[0])

proc drawScreen() =
  glClear(GL_COLOR_BUFFER_BIT)
  glBegin(GL_QUADS)
  glTexCoord2f(0, 0); glVertex2f(-1,  1)
  glTexCoord2f(1, 0); glVertex2f( 1,  1)
  glTexCoord2f(1, 1); glVertex2f( 1, -1)
  glTexCoord2f(0, 1); glVertex2f(-1, -1)
  glEnd()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if init() == 0:
  quit("Failed to init GLFW")

windowHint(CONTEXT_VERSION_MAJOR, 2)
windowHint(CONTEXT_VERSION_MINOR, 1)

window = createWindow(1280, 720, WindowTitle, nil, nil)
if window == nil:
  quit("Failed to create window")

makeContextCurrent(window)
initGL()

# Setup Terminal logic
let font = readFont(FontPath)
font.paint.color = color(1, 1, 1, 1) # White text
let atlas = newGlyphAtlas(font, DefaultFontSize)
term = newTerminal("/bin/sh", ["-i"])
rend = newTerminalRenderer(atlas, 1280, 720)

# Initial resize
onResize(window, 1280, 720)

# Set callbacks
discard window.setCharCallback(onChar)
discard window.setKeyCallback(onKey)
discard window.setFramebufferSizeCallback(onResize)

while windowShouldClose(window) == 0:
  # 1. Process PTY data
  discard term.step()
  
  if term.damage.anyDirty:
    # 2. Render to Pixie image
    rend.draw(term)
    
    # 3. Blit to OpenGL
    updateTexture(rend.surface)
    drawScreen()
    swapBuffers(window)
  
  pollEvents()

terminate()
