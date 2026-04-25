## Nim Terminal Prototype.
##
## Main entry point: creates a window, loads a font, and runs the
## terminal pipeline with a Pixie-based renderer.

import staticglfw
import opengl
import pixie
import os
import std/[options, strutils]
import terminal
import gpu_renderer
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
from ../cg/frontend_glfw_input_nim/src/glfw_input_lib import toKeyCode, toModifiers, toMouseButton
import ../cg/universal_perf_monitor_nim/src/perf_monitor_lib
import ../cg/universal_shortcut_map_nim/src/shortcut_map_lib
import ../cg/universal_os_launcher_nim/src/os_launcher_lib
import ../cg/universal_tab_set_nim/src/tab_set_lib

const
  WindowTitle = "Nim Terminal"
  FontPath = "resources/Inconsolata-Regular.ttf"
  ZoomContextRowsAbove = 2
  FallbackFontPaths = [
    "/home/Vinscen/.local/share/fonts/JetBrainsMonoNerd/JetBrainsMonoNerdFontMono-Regular.ttf",
    "/home/Vinscen/.local/share/fonts/JetBrainsMonoNerd/JetBrainsMonoNerdFont-Regular.ttf",
    "/usr/share/fonts/google-noto/NotoSansSymbols2-Regular.ttf",
    "/usr/share/fonts/google-noto-vf/NotoSansSymbols[wght].ttf",
    "/usr/share/fonts/google-noto-emoji-fonts/NotoEmoji-Regular.ttf",
    "/usr/share/fonts/google-noto-color-emoji-fonts/Noto-COLRv1.ttf",
    "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
  ]

type
  TerminalSession = object
    id: TabId
    terminal: Terminal

var
  tabs = newTabSet()
  sessions: seq[TerminalSession] = @[]
  rend: GpuTerminalRenderer
  window: Window
  winWidth = 1280
  winHeight = 720
  fontSize = 18.0
  font: Font
  headerHeight = 28
  fallbackTypefaces: seq[Typeface] = @[]

let shellCmd = when defined(windows): "cmd.exe" else: getEnv("SHELL", "/bin/sh")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func castSet(s: cint): set[terminal.Modifier] =
  if (s and MOD_SHIFT) != 0: result.incl terminal.modShift
  if (s and MOD_ALT) != 0: result.incl terminal.modAlt
  if (s and MOD_CONTROL) != 0: result.incl terminal.modCtrl
  if (s and MOD_SUPER) != 0: result.incl terminal.modSuper

proc activeSessionIndex(): int =
  if tabs.activeId.isNone: return -1
  let activeId = tabs.activeId.get()
  for i, session in sessions:
    if session.id == activeId: return i
  -1

proc activeTerm(): Terminal =
  let idx = activeSessionIndex()
  if idx < 0: nil else: sessions[idx].terminal

proc contentHeight(): int = max(1, winHeight - headerHeight)

proc terminalCols(): int =
  if rend == nil or rend.atlas == nil or rend.atlas.cellWidth <= 0: return 1
  max(1, winWidth div rend.atlas.cellWidth)

proc terminalRows(): int =
  if rend == nil or rend.atlas == nil or rend.atlas.cellHeight <= 0: return 1
  max(1, contentHeight() div rend.atlas.cellHeight)

func cwdLabel(path: string): string =
  let normalized = path.strip(chars = {'/', '\\'})
  if normalized.len == 0: return path
  let (_, tail) = splitPath(normalized)
  if tail.len == 0: path else: tail

proc shellArgsFor(cwd: string): seq[string] =
  when defined(windows):
    @[]
  else:
    @["-i"]

proc resizeTerminals() =
  if rend == nil or rend.atlas == nil: return
  let cols = terminalCols()
  let rows = terminalRows()
  for session in sessions:
    session.terminal.resize(cols, rows)
    session.terminal.damage.markAll()

type ZoomAnchor = object
  topAbsRow: int
  absRow: int
  viewportRow: int
  atBottom: bool

proc resizeTerminalViewsPreservingView(anchors: seq[ZoomAnchor]) =
  if rend == nil or rend.atlas == nil: return
  let rows = terminalRows()
  for i, session in sessions:
    let anchor = if i < anchors.len: anchors[i] else: ZoomAnchor(topAbsRow: -1, absRow: -1, viewportRow: 0, atBottom: true)
    session.terminal.damage.resize(rows)
    session.terminal.viewport.height = rows
    session.terminal.viewport.updateBufferHeight(session.terminal.screen.totalRows, false)
    if anchor.absRow >= 0:
      let maxContextAbove = min(ZoomContextRowsAbove, anchor.absRow)
      let cursorViewportIfTopPreserved = anchor.absRow - anchor.topAbsRow
      let preferredTop =
        if anchor.topAbsRow >= 0 and cursorViewportIfTopPreserved >= maxContextAbove and cursorViewportIfTopPreserved < rows:
          anchor.topAbsRow
        else:
          anchor.absRow - maxContextAbove
      let desiredOffset = session.terminal.screen.totalRows - rows - preferredTop
      session.terminal.viewport.scrollOffset = max(0, min(session.terminal.viewport.maxScroll, desiredOffset))
    else:
      session.terminal.viewport.scrollToBottom()
    session.terminal.damage.markAll()

proc addTerminalTab() =
  let cwd = getCurrentDir()
  let label = cwdLabel(cwd)
  let id = tabs.addTab(label)
  let term = newTerminal(shellCmd, shellArgsFor(cwd), cwd = cwd, cols = terminalCols(), rows = terminalRows())
  sessions.add TerminalSession(id: id, terminal: term)
  resizeTerminals()

proc tabWidthPx(): int =
  let plusWidth = max(32, headerHeight)
  let tabAreaWidth = max(0, winWidth - plusWidth)
  if tabs.tabs.len == 0: tabAreaWidth else: max(12, tabAreaWidth div max(1, tabs.tabs.len))

proc tabAreaWidthPx(): int =
  let plusWidth = max(32, headerHeight)
  max(0, winWidth - plusWidth)

proc tabAt(x: int): Option[TabId] =
  let tabAreaWidth = tabAreaWidthPx()
  if x < 0 or x >= tabAreaWidth or tabs.tabs.len == 0: return none(TabId)
  let idx = x div tabWidthPx()
  if idx < 0 or idx >= tabs.tabs.len: none(TabId) else: some(tabs.tabs[idx].id)

proc closeTabAt(x: int): Option[TabId] =
  let tabAreaWidth = tabAreaWidthPx()
  if x < 0 or x >= tabAreaWidth or tabs.tabs.len <= 1: return none(TabId)
  let tabWidth = tabWidthPx()
  let idx = x div tabWidth
  if idx < 0 or idx >= tabs.tabs.len: return none(TabId)
  let tabX = idx * tabWidth
  let w = min(tabWidth, tabAreaWidth - tabX)
  if w < 44: return none(TabId)
  let closeSize = max(10, min(headerHeight - 10, 16))
  let closeX = tabX + w - closeSize - 6
  if x >= closeX and x < closeX + closeSize:
    some(tabs.tabs[idx].id)
  else:
    none(TabId)

proc removeTerminalTab(id: TabId) =
  if sessions.len <= 1: return
  for i, session in sessions:
    if session.id == id:
      session.terminal.close()
      sessions.delete(i)
      discard tabs.close(id)
      let term = activeTerm()
      if term != nil: term.damage.markAll()
      return

proc inPlusButton(x: int): bool =
  let plusWidth = max(32, headerHeight)
  x >= max(0, winWidth - plusWidth)

proc viewportRowFromY(y: cdouble): int =
  (int(y) - headerHeight) div rend.atlas.cellHeight

proc loadFallbackTypefaces(): seq[Typeface] =
  for path in FallbackFontPaths:
    if not fileExists(path): continue
    try:
      result.add readTypeface(path)
    except CatchableError:
      discard

proc applyFontFallbacks(atlas: GlyphAtlas) =
  if fallbackTypefaces.len > 0:
    atlas.setFallbackTypefaces(fallbackTypefaces)

func modifiedCharRune(key: cint, mods: set[terminal.Modifier]): Option[uint32] =
  let shifted = terminal.modShift in mods
  case key
  of KEY_SPACE: some(uint32(' '))
  of KEY_A .. KEY_Z:
    some(uint32((if shifted: ord('A') else: ord('a')) + (key - KEY_A)))
  of KEY_0 .. KEY_9:
    if shifted:
      case key
      of KEY_0: some(uint32(')'))
      of KEY_1: some(uint32('!'))
      of KEY_2: some(uint32('@'))
      of KEY_3: some(uint32('#'))
      of KEY_4: some(uint32('$'))
      of KEY_5: some(uint32('%'))
      of KEY_6: some(uint32('^'))
      of KEY_7: some(uint32('&'))
      of KEY_8: some(uint32('*'))
      of KEY_9: some(uint32('('))
      else: none(uint32)
    else:
      some(uint32(ord('0') + (key - KEY_0)))
  of KEY_APOSTROPHE: some(uint32(if shifted: '"' else: '\''))
  of KEY_COMMA: some(uint32(if shifted: '<' else: ','))
  of KEY_MINUS: some(uint32(if shifted: '_' else: '-'))
  of KEY_PERIOD: some(uint32(if shifted: '>' else: '.'))
  of KEY_SLASH: some(uint32(if shifted: '?' else: '/'))
  of KEY_SEMICOLON: some(uint32(if shifted: ':' else: ';'))
  of KEY_EQUAL: some(uint32(if shifted: '+' else: '='))
  of KEY_LEFT_BRACKET: some(uint32(if shifted: '{' else: '['))
  of KEY_BACKSLASH: some(uint32(if shifted: '|' else: '\\'))
  of KEY_RIGHT_BRACKET: some(uint32(if shifted: '}' else: ']'))
  of KEY_GRAVE_ACCENT: some(uint32(if shifted: '~' else: '`'))
  else: none(uint32)

proc rebuildAtlas() =
  var anchors: seq[ZoomAnchor] = @[]
  for session in sessions:
    let absCursor = session.terminal.screen.totalRows - session.terminal.screen.rows + session.terminal.screen.cursor.row
    let cursorViewport = session.terminal.viewport.bufferToViewport(absCursor)
    let topAbs = session.terminal.viewport.viewportToBuffer(0)
    anchors.add ZoomAnchor(
      topAbsRow: topAbs,
      absRow: absCursor,
      viewportRow: if cursorViewport >= 0: cursorViewport else: max(0, session.terminal.viewport.height - 1),
      atBottom: session.terminal.viewport.isAtBottom,
    )
  font = readFont(FontPath)
  font.size = fontSize
  font.paint.color = color(1, 1, 1, 1)
  let atlas = newGlyphAtlas(font, fontSize)
  applyFontFallbacks(atlas)
  rend = newGpuTerminalRenderer(atlas)
  headerHeight = max(24, rend.atlas.cellHeight + 8)
  resizeTerminalViewsPreservingView(anchors)

# ---------------------------------------------------------------------------
# GLFW Callbacks
# ---------------------------------------------------------------------------

proc onChar(win: Window, codepoint: cuint) {.cdecl.} =
  let term = activeTerm()
  if term == nil: return
  discard term.sendKey(keyChar(uint32(codepoint)))
  term.damage.markAll()

proc onKey(win: Window, key, scancode, action, mods: cint) {.cdecl.} =
  if action == PRESS or action == REPEAT:
    let term = activeTerm()
    if term == nil: return
    let m = castSet(mods)

    if terminal.modCtrl in m and key == KEY_T:
      addTerminalTab()
      return
    if terminal.modCtrl in m and key == KEY_TAB:
      if terminal.modShift in m: discard tabs.activatePrevious()
      else: discard tabs.activateNext()
      let term = activeTerm()
      if term != nil: term.damage.markAll()
      return

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
          window.setClipboardString(cstring(text))
        return
      of "paste":
        let text = window.getClipboardString()
        if text != nil: discard term.sendPaste($text)
        return
      of "zoom-in": fontSize += 1.0; rebuildAtlas(); return
      of "zoom-out": fontSize = max(4.0, fontSize - 1.0); rebuildAtlas(); return
      else: discard

    # GLFW's char callback does not reliably emit Ctrl/Alt character
    # combinations. Send those from the key callback so Ctrl+C, Ctrl+D,
    # Alt+letter, etc. reach the child process.
    if terminal.modCtrl in m or terminal.modAlt in m:
      let ch = modifiedCharRune(key, m)
      if ch.isSome:
        discard term.sendKey(keyChar(ch.get(), m))
        term.damage.markAll()
        return

    # 3. Standard keys
    let tk = toKeyCode(key).int
    if tk != 0 and tk != 1: # 0 = kNone, 1 = kChar
      discard term.sendKey(terminal.key(cast[terminal.KeyCode](tk), m))
      term.damage.markAll()

proc onMouseButton(win: Window, button, action, mods: cint) {.cdecl.} =
  var x, y: cdouble; getCursorPos(win, addr x, addr y)
  if button == MOUSE_BUTTON_LEFT and action == PRESS and int(y) < headerHeight:
    let closeId = closeTabAt(int(x))
    if closeId.isSome:
      removeTerminalTab(closeId.get())
      return
    if inPlusButton(int(x)):
      addTerminalTab()
      return
    let tabId = tabAt(int(x))
    if tabId.isSome:
      discard tabs.activate(tabId.get())
      let term = activeTerm()
      if term != nil: term.damage.markAll()
      return

  let term = activeTerm()
  if term == nil: return
  if int(y) < headerHeight: return
  let col = int(x) div rend.atlas.cellWidth; let row = viewportRowFromY(y)
  let absRow = term.viewport.viewportToBuffer(row)
  if term.inputMode.shouldIntercept(castSet(mods)):
    if button == MOUSE_BUTTON_LEFT:
      let isDown = action == PRESS

      # Handle link clicking
      if not isDown and term.activeLink.isSome:
        launchUri(term.activeLink.get().link.text)
        return

      term.drag.update(absRow, col, isDown)
      if isDown: term.selection.start(point(absRow, col))
      term.damage.markAll()
  else:
    let tmb = toMouseButton(button).int
    if tmb != 0 and tmb != 1: # kNone=0, kChar=1
      discard term.sendMouse(mouse(if action == PRESS: mePress else: meRelease, cast[terminal.MouseButton](tmb), row, col, castSet(mods)))

proc onCursorPos(win: Window, x, y: cdouble) {.cdecl.} =
  let term = activeTerm()
  if term == nil: return
  if int(y) < headerHeight:
    if term.activeLink.isSome:
      term.activeLink = none(ActiveLink)
      term.damage.markAll()
    return
  let col = int(x) div rend.atlas.cellWidth; let row = viewportRowFromY(y)
  let absRow = term.viewport.viewportToBuffer(row)
  if absRow < 0: return

  if term.drag.state != dsIdle:
    term.drag.update(absRow, col, true); term.selection.update(point(absRow, col))
    if term.drag.state == dsOutsideTop: term.viewport.scrollUp(1)
    elif term.drag.state == dsOutsideBottom: term.viewport.scrollDown(1)
    term.refreshViewport(false); term.damage.markAll()
  else:
    # Update active link hover state
    let lineStr = term.screen.absoluteLineText(absRow)
    let links = detectLinks(lineStr)
    var newActive = none(ActiveLink)
    for l in links:
      let sc = term.screen.colOfByteIndex(absRow, l.startIdx)
      let ec = term.screen.colOfByteIndex(absRow, l.endIdx)
      if col >= sc and col < ec:
        newActive = some(ActiveLink(link: l, row: absRow, startCol: sc, endCol: ec))
        break
    if newActive != term.activeLink:
      term.activeLink = newActive
      term.damage.markAll()

proc onScroll(win: Window, xoffset, yoffset: cdouble) {.cdecl.} =
  let term = activeTerm()
  if term == nil: return
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
    resizeTerminals()
    glViewport(0, 0, width, height)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if init() == 0: quit("Failed to init GLFW")
windowHint(CONTEXT_VERSION_MAJOR, 2); windowHint(CONTEXT_VERSION_MINOR, 1)
window = createWindow(cint(winWidth), cint(winHeight), WindowTitle, nil, nil)
if window == nil: quit("Failed to create window")
makeContextCurrent(window); loadExtensions()

font = readFont(FontPath); font.size = fontSize; font.paint.color = color(1, 1, 1, 1)
fallbackTypefaces = loadFallbackTypefaces()
let atlas = newGlyphAtlas(font, fontSize)
applyFontFallbacks(atlas)
rend = newGpuTerminalRenderer(atlas)
headerHeight = max(24, rend.atlas.cellHeight + 8)
addTerminalTab()

discard window.setCharCallback(onChar); discard window.setKeyCallback(onKey)
discard window.setMouseButtonCallback(onMouseButton); discard window.setCursorPosCallback(onCursorPos)
discard window.setScrollCallback(onScroll); discard window.setFramebufferSizeCallback(onResize)

onResize(window, cint(winWidth), cint(winHeight))

let perf = newPerfMonitor()
while windowShouldClose(window) == 0:
  perf.beginFrame()
  var n = 0
  for session in sessions:
    let readCount = session.terminal.step()
    if readCount > 0:
      session.terminal.refreshViewport(stickToBottom = true)
    n += readCount
  let term = activeTerm()
  if term == nil: break
  if atlas.isDirty: rend.updateAtlasTexture()
  let changed = n > 0 or atlas.isDirty or term.damage.anyDirty
  if changed:
    rend.draw(term, winWidth, winHeight, headerHeight)
    rend.drawChrome(tabs, winWidth, winHeight, headerHeight)
    swapBuffers(window)
  pollEvents(); perf.endFrame()
  if perf.shouldReport(2.0):
    let s = perf.takeReport()
    echo "FPS: ", s.fps, " Latency: ", s.avgLatencyMs, " ms"
  if not changed: os.sleep(1)

terminate()
