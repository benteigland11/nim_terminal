## Nim Terminal Prototype.
##
## Main entry point: creates a window, loads a font, and runs the
## terminal pipeline with a Pixie-based renderer.

import staticglfw
import opengl
import pixie
import os
import std/[options, parsecfg, strutils]
import terminal
import gpu_renderer
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
from ../cg/frontend_glfw_input_nim/src/glfw_input_lib import toKeyCode, toMouseButton, toPrintableRune
import ../cg/universal_perf_monitor_nim/src/perf_monitor_lib
import ../cg/universal_shortcut_map_nim/src/shortcut_map_lib
import ../cg/universal_os_launcher_nim/src/os_launcher_lib
import ../cg/universal_tab_set_nim/src/tab_set_lib
import ../cg/universal_process_cwd_nim/src/process_cwd_lib
import ../cg/universal_path_candidates_nim/src/path_candidates_lib

const
  DefaultWindowTitle = "Nim Terminal"
  ConfigPath = "nim_terminal.cfg"
  DefaultFontPath = "resources/Inconsolata-Regular.ttf"
  DefaultLogoPath = "logo.png"
  DefaultFontSize = 20.0
  DefaultTitleBarHeight = 30
  DefaultTabBarHeight = 28
  DefaultScrollback = 10000
  ZoomContextRowsAbove = 2
  DefaultFallbackFontPaths = [
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
    cwd: string

  TerminalConfig = object
    title: string
    shellProgram: string
    fontPath: string
    fontSize: float
    fallbackFontPaths: seq[string]
    logoPath: string
    titleBarHeight: int
    tabBarHeight: int
    backgroundColor: string
    scrollback: int

var
  config = TerminalConfig(
    title: DefaultWindowTitle,
    shellProgram: when defined(windows): "cmd.exe" else: getEnv("SHELL", "/bin/sh"),
    fontPath: DefaultFontPath,
    fontSize: DefaultFontSize,
    fallbackFontPaths: @DefaultFallbackFontPaths,
    logoPath: DefaultLogoPath,
    titleBarHeight: DefaultTitleBarHeight,
    tabBarHeight: DefaultTabBarHeight,
    backgroundColor: "#050607",
    scrollback: DefaultScrollback,
  )
  tabs = newTabSet()
  sessions: seq[TerminalSession] = @[]
  rend: GpuTerminalRenderer
  window: Window
  winWidth = 1280
  winHeight = 720
  fontSize = DefaultFontSize
  font: Font
  chromeFont: Font
  titleBarHeight = DefaultTitleBarHeight
  tabBarHeight = DefaultTabBarHeight
  headerHeight = titleBarHeight + tabBarHeight
  draggingWindow = false
  dragStartMouseX = 0.0
  dragStartMouseY = 0.0
  dragStartGlobalX = 0.0
  dragStartGlobalY = 0.0
  dragStartWinX: cint = 0
  dragStartWinY: cint = 0
  fallbackTypefaces: seq[Typeface] = @[]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func splitList(value: string): seq[string] =
  for item in value.split(','):
    let trimmed = item.strip()
    if trimmed.len > 0:
      result.add trimmed

proc parseFloatOr(value: string, fallback: float): float =
  try:
    result = parseFloat(value)
  except ValueError:
    result = fallback

proc parseIntOr(value: string, fallback: int): int =
  try:
    result = parseInt(value)
  except ValueError:
    result = fallback

proc loadTerminalConfig(path = ConfigPath): TerminalConfig =
  result = config
  if not fileExists(path):
    return
  try:
    let dict = loadConfig(path)
    result.title = dict.getSectionValue("app", "title", result.title)
    result.logoPath = resolveCandidatePath(dict.getSectionValue("app", "logo", result.logoPath), getCurrentDir())

    let shell = dict.getSectionValue("shell", "program", result.shellProgram).strip()
    if shell.len > 0:
      result.shellProgram = shell

    result.fontSize = max(4.0, parseFloatOr(dict.getSectionValue("font", "size", $result.fontSize), result.fontSize))
    let fontCandidate = dict.getSectionValue("font", "primary", result.fontPath)
    result.fontPath = firstExistingPath([fontCandidate, result.fontPath], getCurrentDir()).get(result.fontPath)

    let configuredFallbacks = splitList(dict.getSectionValue("font", "fallbacks", ""))
    if configuredFallbacks.len > 0:
      result.fallbackFontPaths = configuredFallbacks

    result.titleBarHeight = max(24, parseIntOr(dict.getSectionValue("chrome", "title_bar_height", $result.titleBarHeight), result.titleBarHeight))
    result.tabBarHeight = max(22, parseIntOr(dict.getSectionValue("chrome", "tab_bar_height", $result.tabBarHeight), result.tabBarHeight))
    result.backgroundColor = dict.getSectionValue("theme", "background", result.backgroundColor)
    result.scrollback = max(100, parseIntOr(dict.getSectionValue("terminal", "scrollback", $result.scrollback), result.scrollback))
  except CatchableError as e:
    echo "Config warning: ", e.msg

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

proc updateChromeHeights() =
  titleBarHeight = config.titleBarHeight
  tabBarHeight = config.tabBarHeight
  headerHeight = titleBarHeight + tabBarHeight

proc refreshTabCwdLabels(): bool =
  for i in 0 ..< sessions.len:
    let cwd = processCwd(sessions[i].terminal.host.pid)
    if cwd.isNone or cwd.get() == sessions[i].cwd: continue
    sessions[i].cwd = cwd.get()
    let label = cwdLabel(cwd.get())
    if tabs.rename(sessions[i].id, label):
      result = true

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

proc applyConfiguredTheme(term: Terminal) =
  let background = parseColor(config.backgroundColor)
  if background.isSome:
    let c = background.get()
    term.screen.theme.background = PaletteColor(r: c.r, g: c.g, b: c.b)
    term.damage.markAll()

type ZoomAnchor = object
  topAbsRow: int
  absRow: int
  viewportRow: int
  atBottom: bool

proc resizeTerminalViewsPreservingView(anchors: seq[ZoomAnchor]) =
  if rend == nil or rend.atlas == nil: return
  let cols = terminalCols()
  let rows = terminalRows()
  for i, session in sessions:
    let anchor = if i < anchors.len: anchors[i] else: ZoomAnchor(topAbsRow: -1, absRow: -1, viewportRow: 0, atBottom: true)
    session.terminal.resizeView(cols, rows)
    session.terminal.viewport.restoreAnchor(
      totalRows = session.terminal.screen.totalRows,
      height = rows,
      anchor = ViewAnchor(
        topRow: anchor.topAbsRow,
        targetRow: anchor.absRow,
        targetViewportRow: anchor.viewportRow,
        atBottom: anchor.atBottom,
      ),
      contextRowsAbove = ZoomContextRowsAbove,
    )
    session.terminal.damage.markAll()

proc addTerminalTab() =
  let cwd = getCurrentDir()
  let label = cwdLabel(cwd)
  let id = tabs.addTab(label)
  let term = newTerminal(config.shellProgram, shellArgsFor(cwd), cwd = cwd, cols = terminalCols(), rows = terminalRows(), scrollback = config.scrollback)
  applyConfiguredTheme(term)
  sessions.add TerminalSession(id: id, terminal: term, cwd: cwd)
  resizeTerminals()

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

proc inTitleBar(y: int): bool =
  y >= 0 and y < titleBarHeight

proc inTabBar(y: int): bool =
  y >= titleBarHeight and y < headerHeight

proc viewportRowFromY(y: cdouble): int =
  (int(y) - headerHeight) div rend.atlas.cellHeight

proc loadFallbackTypefaces(): seq[Typeface] =
  for path in config.fallbackFontPaths:
    let resolved = resolveCandidatePath(path, getCurrentDir())
    if not fileExists(resolved): continue
    try:
      result.add readTypeface(resolved)
    except CatchableError:
      discard

proc applyFontFallbacks(atlas: GlyphAtlas) =
  if fallbackTypefaces.len > 0:
    atlas.setFallbackTypefaces(fallbackTypefaces)

proc makeAtlas(size: float, targetFont: var Font): GlyphAtlas =
  targetFont = readFont(config.fontPath)
  targetFont.size = size
  targetFont.paint.color = color(1, 1, 1, 1)
  result = newGlyphAtlas(targetFont, size)
  applyFontFallbacks(result)

proc rebuildAtlas() =
  var anchors: seq[ZoomAnchor] = @[]
  for session in sessions:
    let absCursor = session.terminal.screen.absoluteCursorRow()
    let cursorViewport = session.terminal.viewport.bufferToViewport(absCursor)
    let topAbs = session.terminal.viewport.viewportToBuffer(0)
    anchors.add ZoomAnchor(
      topAbsRow: topAbs,
      absRow: absCursor,
      viewportRow: if cursorViewport >= 0: cursorViewport else: max(0, session.terminal.viewport.height - 1),
      atBottom: session.terminal.viewport.isAtBottom,
    )
  let atlas = makeAtlas(fontSize, font)
  let chromeAtlas = makeAtlas(config.fontSize, chromeFont)
  rend = newGpuTerminalRenderer(atlas, chromeAtlas)
  rend.loadLogoTexture(config.logoPath)
  updateChromeHeights()
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
      let ch = toPrintableRune(key, mods)
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
  if button == MOUSE_BUTTON_LEFT and action == RELEASE:
    draggingWindow = false

  if button == MOUSE_BUTTON_LEFT and action == PRESS and inTitleBar(int(y)):
    draggingWindow = true
    dragStartMouseX = x
    dragStartMouseY = y
    getWindowPos(win, addr dragStartWinX, addr dragStartWinY)
    dragStartGlobalX = float(dragStartWinX) + x
    dragStartGlobalY = float(dragStartWinY) + y
    let term = activeTerm()
    if term != nil and term.activeLink.isSome:
      term.activeLink = none(ActiveLink)
      term.damage.markAll()
    return

  if button == MOUSE_BUTTON_LEFT and action == PRESS and inTabBar(int(y)):
    let closeId = tabs.closeTabAtX(int(x), winWidth, tabBarHeight)
    if closeId.isSome:
      removeTerminalTab(closeId.get())
      return
    if plusButtonAtX(int(x), winWidth, tabBarHeight):
      addTerminalTab()
      return
    let tabId = tabs.tabAtX(int(x), winWidth, tabBarHeight)
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
  if draggingWindow:
    var currentWinX, currentWinY: cint
    getWindowPos(win, addr currentWinX, addr currentWinY)
    let currentGlobalX = float(currentWinX) + x
    let currentGlobalY = float(currentWinY) + y
    setWindowPos(
      win,
      dragStartWinX + cint(currentGlobalX - dragStartGlobalX),
      dragStartWinY + cint(currentGlobalY - dragStartGlobalY),
    )
    return

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

    if not term.inputMode.shouldIntercept() and term.inputMode.trackingWantsMotion():
      let leftDown = getMouseButton(window, MOUSE_BUTTON_LEFT) == PRESS
      let kind =
        if leftDown and term.inputMode.trackingWantsDrag(): meDrag
        else: meMove
      discard term.sendMouse(mouse(kind, mbLeft, row, col, castSet(0)))

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

config = loadTerminalConfig()
fontSize = config.fontSize

if init() == 0: quit("Failed to init GLFW")
windowHint(CONTEXT_VERSION_MAJOR, 2); windowHint(CONTEXT_VERSION_MINOR, 1)
window = createWindow(cint(winWidth), cint(winHeight), cstring(config.title), nil, nil)
if window == nil: quit("Failed to create window")
makeContextCurrent(window); loadExtensions()

fallbackTypefaces = loadFallbackTypefaces()
let atlas = makeAtlas(fontSize, font)
let chromeAtlas = makeAtlas(config.fontSize, chromeFont)
rend = newGpuTerminalRenderer(atlas, chromeAtlas)
rend.loadLogoTexture(config.logoPath)
updateChromeHeights()
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
  let tabLabelsChanged = refreshTabCwdLabels()
  let changed = n > 0 or atlas.isDirty or term.damage.anyDirty or tabLabelsChanged
  if changed:
    rend.draw(term, winWidth, winHeight, headerHeight)
    rend.drawChrome(tabs, winWidth, winHeight, titleBarHeight, tabBarHeight, config.title)
    swapBuffers(window)
  pollEvents(); perf.endFrame()
  if perf.shouldReport(2.0):
    let s = perf.takeReport()
    echo "FPS: ", s.fps, " Latency: ", s.avgLatencyMs, " ms"
  if not changed: os.sleep(1)

terminate()
