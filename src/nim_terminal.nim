## Waymark terminal application.
##
## Main entry point: creates a window, loads a font, and runs the
## terminal pipeline with a Pixie-based renderer.

import staticglfw
import opengl
import pixie
import os
import std/[json, options, parsecfg, strutils]
import terminal
import gpu_renderer
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
from ../cg/frontend_glfw_input_nim/src/glfw_input_lib import toKeyCode, toMouseButton, toPrintableRune
import ../cg/universal_perf_monitor_nim/src/perf_monitor_lib
import ../cg/universal_shortcut_map_nim/src/shortcut_map_lib
import ../cg/frontend_glfw_window_nim/src/glfw_window_lib
import ../cg/universal_os_launcher_nim/src/os_launcher_lib
import ../cg/universal_tab_set_nim/src/tab_set_lib
import ../cg/universal_process_cwd_nim/src/process_cwd_lib
import ../cg/universal_path_candidates_nim/src/path_candidates_lib
import ../cg/universal_split_pane_tree_nim/src/split_pane_tree_lib as pane_tree
import ../cg/universal_resource_budget_nim/src/resource_budget_lib
import ../cg/universal_resource_ledger_nim/src/resource_ledger_lib
import ../cg/backend_system_clipboard_nim/src/system_clipboard_lib

const
  DefaultWindowTitle = "Waymark - Built with Nim"
  ConfigPath = "nim_terminal.cfg"
  DefaultFontPath = "resources/JetBrainsMono-Medium.otf"
  DefaultLogoPath = "logo.svg"
  DefaultFontSize = 20.0
  DefaultTitleBarHeight = 30
  DefaultTabBarHeight = 28
  DefaultWindowWidth = 1280
  DefaultWindowHeight = 720
  MinWindowWidth = 640
  MinWindowHeight = 360
  DefaultScrollback = 10000
  DefaultMaxPanes = 8
  DefaultDiagnosticsCapacity = 256
  DefaultGlyphAtlasSize = 2048
  MaxScrollback = 50000
  MaxGlyphAtlasSize = 4096
  ZoomContextRowsAbove = 2
  PaneBorderPx = 1
  PanePadXPx = 8
  PanePadYPx = 4
  DefaultFallbackFontPaths = [
    "/usr/share/fonts/google-noto/NotoSansSymbols2-Regular.ttf",
    "/usr/share/fonts/google-noto-vf/NotoSansSymbols[wght].ttf",
    "/usr/share/fonts/google-noto-emoji-fonts/NotoEmoji-Regular.ttf",
    "/usr/share/fonts/google-noto-color-emoji-fonts/Noto-COLRv1.ttf",
    "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
  ]

type
  PaneId = pane_tree.PaneId
  SplitPaneTree = pane_tree.SplitPaneTree
  PaneLayout = pane_tree.PaneLayout
  PaneRect = pane_tree.Rect

  TerminalSession = object
    id: PaneId
    terminal: Terminal
    cwd: string

  TerminalWorkspace = object
    id: TabId
    panes: SplitPaneTree
    sessions: seq[TerminalSession]

  TerminalConfig = object
    title: string
    shellProgram: string
    startDirectory: string
    fontPath: string
    fontSize: float
    fallbackFontPaths: seq[string]
    logoPath: string
    titleBarHeight: int
    tabBarHeight: int
    backgroundColor: string
    scrollback: int
    maxPanes: int
    diagnosticsCapacity: int
    glyphAtlasSize: int

var
  config = TerminalConfig(
    title: DefaultWindowTitle,
    shellProgram: when defined(windows): "cmd.exe" else: getEnv("SHELL", "/bin/sh"),
    startDirectory: "~",
    fontPath: DefaultFontPath,
    fontSize: DefaultFontSize,
    fallbackFontPaths: @DefaultFallbackFontPaths,
    logoPath: DefaultLogoPath,
    titleBarHeight: DefaultTitleBarHeight,
    tabBarHeight: DefaultTabBarHeight,
    backgroundColor: "#050607",
    scrollback: DefaultScrollback,
    maxPanes: DefaultMaxPanes,
    diagnosticsCapacity: DefaultDiagnosticsCapacity,
    glyphAtlasSize: DefaultGlyphAtlasSize,
  )
  tabs = newTabSet()
  workspaces: seq[TerminalWorkspace] = @[]
  rend: GpuTerminalRenderer
  window: Window
  winWidth = DefaultWindowWidth
  winHeight = DefaultWindowHeight
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
  gpuSnapshotPath = getEnv("WAYMARK_GPU_SNAPSHOT_PATH", "")
  screenSnapshotPath = getEnv("WAYMARK_SCREEN_SNAPSHOT_PATH", "")
  resizeSnapshotPath = getEnv("WAYMARK_RESIZE_SNAPSHOT_PATH", "")
  lifecycleChaosCycles = 0
  keyTextFallback = false
  inputDebug = false

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
    let startDirectory = dict.getSectionValue("shell", "start_directory", result.startDirectory).strip()
    if startDirectory.len > 0:
      result.startDirectory = startDirectory

    result.fontSize = max(4.0, parseFloatOr(dict.getSectionValue("font", "size", $result.fontSize), result.fontSize))
    let fontCandidate = dict.getSectionValue("font", "primary", result.fontPath)
    result.fontPath = firstExistingPath([fontCandidate, result.fontPath], getCurrentDir()).get(result.fontPath)

    let configuredFallbacks = splitList(dict.getSectionValue("font", "fallbacks", ""))
    if configuredFallbacks.len > 0:
      result.fallbackFontPaths = configuredFallbacks

    result.titleBarHeight = max(24, parseIntOr(dict.getSectionValue("chrome", "title_bar_height", $result.titleBarHeight), result.titleBarHeight))
    result.tabBarHeight = max(22, parseIntOr(dict.getSectionValue("chrome", "tab_bar_height", $result.tabBarHeight), result.tabBarHeight))
    result.backgroundColor = dict.getSectionValue("theme", "background", result.backgroundColor)
    let requestedScrollback = max(100, parseIntOr(dict.getSectionValue("terminal", "scrollback", $result.scrollback), result.scrollback))
    result.scrollback = int(recommendedCap(resourceLimit("scrollback", DefaultScrollback, MaxScrollback), requestedScrollback.int64))
    result.maxPanes = max(1, parseIntOr(dict.getSectionValue("terminal", "max_panes", $result.maxPanes), result.maxPanes))
    result.diagnosticsCapacity = max(0, parseIntOr(dict.getSectionValue("diagnostics", "capacity", $result.diagnosticsCapacity), result.diagnosticsCapacity))
    let requestedAtlas = max(256, parseIntOr(dict.getSectionValue("resources", "glyph_atlas_size", $result.glyphAtlasSize), result.glyphAtlasSize))
    result.glyphAtlasSize = int(recommendedCap(resourceLimit("glyph_atlas", DefaultGlyphAtlasSize, MaxGlyphAtlasSize), requestedAtlas.int64))
  except CatchableError as e:
    echo "Config warning: ", e.msg

func castSet(s: cint): set[terminal.Modifier] =
  if (s and MOD_SHIFT) != 0: result.incl terminal.modShift
  if (s and MOD_ALT) != 0: result.incl terminal.modAlt
  if (s and MOD_CONTROL) != 0: result.incl terminal.modCtrl
  if (s and MOD_SUPER) != 0: result.incl terminal.modSuper

proc activeWorkspaceIndex(): int =
  if tabs.activeId.isNone: return -1
  let activeId = tabs.activeId.get()
  for i, workspace in workspaces:
    if workspace.id == activeId: return i
  -1

proc activeWorkspace(): ptr TerminalWorkspace =
  let idx = activeWorkspaceIndex()
  if idx < 0: nil else: addr workspaces[idx]

proc sessionIndex(workspace: TerminalWorkspace, paneId: PaneId): int =
  for i, session in workspace.sessions:
    if session.id == paneId: return i
  -1

proc activeSessionIndex(workspace: TerminalWorkspace): int =
  workspace.sessionIndex(workspace.panes.active)

proc activeTerm(): Terminal =
  let workspace = activeWorkspace()
  if workspace == nil: return nil
  let idx = workspace[].activeSessionIndex()
  if idx < 0: nil else: workspace[].sessions[idx].terminal

proc ensureCursorVisible(term: Terminal) =
  if term == nil: return
  term.viewport.ensureVisible(term.screen.absoluteCursorRow(), ZoomContextRowsAbove)
  term.damage.markAll()

proc sessionByPane(workspace: var TerminalWorkspace, paneId: PaneId): ptr TerminalSession =
  let idx = workspace.sessionIndex(paneId)
  if idx < 0: nil else: addr workspace.sessions[idx]

proc contentHeight(): int = max(1, winHeight - headerHeight)

proc paneInnerRect(area: PaneRect): PaneRect =
  let insetX = min(area.w div 3, PaneBorderPx + PanePadXPx)
  let insetY = min(area.h div 3, PaneBorderPx + PanePadYPx)
  pane_tree.rect(area.x + insetX, area.y + insetY, area.w - insetX * 2, area.h - insetY * 2)

proc paneCols(area: PaneRect): int =
  if rend == nil or rend.atlas == nil or rend.atlas.cellWidth <= 0: return 1
  max(1, paneInnerRect(area).w div rend.atlas.cellWidth)

proc paneRows(area: PaneRect): int =
  if rend == nil or rend.atlas == nil or rend.atlas.cellHeight <= 0: return 1
  max(1, paneInnerRect(area).h div rend.atlas.cellHeight)

proc contentRect(): PaneRect =
  pane_tree.rect(0, headerHeight, winWidth, contentHeight())

proc activePaneLayouts(): seq[PaneLayout] =
  let idx = activeWorkspaceIndex()
  if idx < 0: return @[]
  workspaces[idx].panes.layouts(contentRect())

proc activeSessionRect(paneId: PaneId): Option[PaneRect] =
  for item in activePaneLayouts():
    if item.id == paneId:
      return some(paneInnerRect(item.rect))
  none(PaneRect)

proc focusPaneAt(x, y: int): ptr TerminalSession =
  let wi = activeWorkspaceIndex()
  if wi < 0: return nil
  let hit = workspaces[wi].panes.hitTest(contentRect(), x, y)
  if hit.isNone: return nil
  let previous = workspaces[wi].panes.active
  discard workspaces[wi].panes.activate(hit.get())
  if previous != hit.get():
    let oldIdx = workspaces[wi].sessionIndex(previous)
    if oldIdx >= 0: workspaces[wi].sessions[oldIdx].terminal.damage.markAll()
    let newIdx = workspaces[wi].sessionIndex(hit.get())
    if newIdx >= 0: ensureCursorVisible(workspaces[wi].sessions[newIdx].terminal)
  workspaces[wi].sessionByPane(hit.get())

proc clearSelectionsExcept(workspace: var TerminalWorkspace, paneId: PaneId) =
  for session in workspace.sessions.mitems:
    if session.id == paneId: continue
    if session.terminal.selection.isActive:
      session.terminal.selection.clear()
      session.terminal.damage.markAll()

proc updateChromeHeights() =
  titleBarHeight = config.titleBarHeight
  tabBarHeight = config.tabBarHeight
  headerHeight = titleBarHeight + tabBarHeight

proc chooseInitialWindowSize() =
  winWidth = DefaultWindowWidth
  winHeight = DefaultWindowHeight
  let monitor = getPrimaryMonitor()
  if monitor == nil:
    return
  let mode = getVideoMode(monitor)
  if mode == nil:
    return
  let maxWidth = max(MinWindowWidth, int(float(mode.width) * 0.92))
  let maxHeight = max(MinWindowHeight, int(float(mode.height) * 0.86))
  winWidth = min(DefaultWindowWidth, maxWidth)
  winHeight = min(DefaultWindowHeight, maxHeight)

proc refreshTabCwdLabels(): bool =
  when defined(windows):
    false
  else:
    for wi in 0 ..< workspaces.len:
      if workspaces[wi].sessions.len == 0: continue
      let activeIdx = workspaces[wi].activeSessionIndex()
      if activeIdx < 0: continue
      let cwd = processCwd(workspaces[wi].sessions[activeIdx].terminal.host.pid)
      if cwd.isNone or cwd.get() == workspaces[wi].sessions[activeIdx].cwd: continue
      workspaces[wi].sessions[activeIdx].cwd = cwd.get()
      let label = cwdLabel(cwd.get())
      if tabs.rename(workspaces[wi].id, label):
        result = true

proc activeSessionCwd(fallback = ""): string =
  let workspace = activeWorkspace()
  if workspace == nil:
    return if fallback.len > 0: fallback else: config.startDirectory
  let idx = workspace[].activeSessionIndex()
  if idx < 0:
    return if fallback.len > 0: fallback else: config.startDirectory
  when not defined(windows):
    let live = processCwd(workspace[].sessions[idx].terminal.host.pid)
    if live.isSome:
      workspace[].sessions[idx].cwd = live.get()
  workspace[].sessions[idx].cwd

proc validSessionCwd(candidate: string): string =
  let expanded = expandTilde(candidate.strip())
  if expanded.len > 0 and dirExists(expanded):
    return expanded
  let current = getCurrentDir()
  if current.len > 0 and dirExists(current):
    return current
  let home = getHomeDir()
  if home.len > 0 and dirExists(home):
    return home
  when defined(windows):
    let userProfile = getEnv("USERPROFILE", "")
    if userProfile.len > 0 and dirExists(userProfile):
      return userProfile
    let homeDrive = getEnv("HOMEDRIVE", "")
    let homePath = getEnv("HOMEPATH", "")
    if homeDrive.len > 0 and homePath.len > 0 and dirExists(homeDrive & homePath):
      return homeDrive & homePath
    let temp = getEnv("TEMP", "")
    if temp.len > 0 and dirExists(temp):
      return temp
    if dirExists("C:\\"):
      return "C:\\"
  ""

proc startupSessionCwd(): string =
  validSessionCwd(config.startDirectory)

proc shellArgsFor(cwd: string): seq[string] =
  when defined(windows):
    @[]
  else:
    @["-i"]

proc applyConfiguredTheme(term: Terminal) =
  let background = parseColor(config.backgroundColor)
  if background.isSome:
    let c = background.get()
    term.screen.theme.background = PaletteColor(r: c.r, g: c.g, b: c.b)
    term.damage.markAll()

proc captureResizeAnchors(): seq[ViewAnchor] =
  for workspace in workspaces:
    let layouts = workspace.panes.layouts(contentRect())
    for item in layouts:
      let idx = workspace.sessionIndex(item.id)
      if idx < 0: continue
      let term = workspace.sessions[idx].terminal
      result.add term.viewport.captureResizeAnchor(term.screen.absoluteCursorRow())

proc resizeTerminalViewsPreservingView(anchors: seq[ViewAnchor] = @[]) =
  if rend == nil or rend.atlas == nil: return
  var anchorIdx = 0
  for workspace in workspaces.mitems:
    let layouts = workspace.panes.layouts(contentRect())
    for item in layouts:
      let idx = workspace.sessionIndex(item.id)
      if idx < 0: continue
      let anchor =
        if anchorIdx < anchors.len:
          anchors[anchorIdx]
        else:
          workspace.sessions[idx].terminal.viewport.captureResizeAnchor(workspace.sessions[idx].terminal.screen.absoluteCursorRow())
      inc anchorIdx
      let cols = paneCols(item.rect)
      let rows = paneRows(item.rect)
      workspace.sessions[idx].terminal.host.resize(cols, rows)
      workspace.sessions[idx].terminal.screen.resizePreserveBottom(cols, rows, preserveCursorRowWhenShort = false)
      workspace.sessions[idx].terminal.damage.resize(rows)
      workspace.sessions[idx].terminal.drag.height = rows
      workspace.sessions[idx].terminal.viewport.restoreAnchor(
        totalRows = workspace.sessions[idx].terminal.screen.totalRows,
        height = rows,
        anchor = anchor,
        contextRowsAbove = ZoomContextRowsAbove,
        pinBottom = false,
      )
      if item.id == workspace.panes.active:
        workspace.sessions[idx].terminal.viewport.ensureVisible(
          workspace.sessions[idx].terminal.screen.absoluteCursorRow(),
          ZoomContextRowsAbove,
        )
      workspace.sessions[idx].terminal.damage.markAll()

proc resizeTerminals() =
  resizeTerminalViewsPreservingView(captureResizeAnchors())

proc paneBudgetAllows(workspace: TerminalWorkspace, requested = 1): bool =
  let decision = decide(
    resourceLimit("panes", max(1, config.maxPanes - 1).int64, config.maxPanes.int64),
    resourceUsage("panes", workspace.sessions.len.int64, requested.int64),
  )
  decision.allowed

proc newSession(paneId: PaneId, area: PaneRect, cwd: string): TerminalSession =
  let sessionCwd = validSessionCwd(cwd)
  if screenSnapshotPath.len > 0:
    try:
      writeFile(screenSnapshotPath & ".launch",
        "program=" & config.shellProgram & "\n" &
        "cwd=" & sessionCwd & "\n" &
        "cols=" & $paneCols(area) & "\n" &
        "rows=" & $paneRows(area) & "\n")
    except CatchableError:
      discard
  let term = newTerminal(
    config.shellProgram,
    shellArgsFor(sessionCwd),
    cwd = sessionCwd,
    cols = paneCols(area),
    rows = paneRows(area),
    scrollback = config.scrollback,
    diagnosticsCapacity = config.diagnosticsCapacity,
  )
  applyConfiguredTheme(term)
  TerminalSession(id: paneId, terminal: term, cwd: sessionCwd)

proc addTerminalTab() =
  let cwd =
    if workspaces.len == 0:
      startupSessionCwd()
    else:
      validSessionCwd(activeSessionCwd())
  let label = cwdLabel(cwd)
  let id = tabs.addTab(label)
  var workspace = TerminalWorkspace(id: id, panes: pane_tree.newSplitPaneTree(), sessions: @[])
  workspace.sessions.add newSession(workspace.panes.active, contentRect(), cwd)
  workspaces.add workspace
  resizeTerminals()

proc splitActivePane() =
  let workspace = activeWorkspace()
  if workspace == nil: return
  if not workspace[].paneBudgetAllows(): return
  let sourcePane = workspace[].panes.active
  let cwd = validSessionCwd(activeSessionCwd())
  let fresh = workspace[].panes.splitActiveAppend()
  let layouts = workspace[].panes.layouts(contentRect())
  var area = contentRect()
  for item in layouts:
    if item.id == fresh:
      area = item.rect
      break
  workspace[].sessions.add newSession(fresh, area, cwd)
  discard workspace[].panes.activate(sourcePane)
  resizeTerminals()
  let sourceIdx = workspace[].sessionIndex(sourcePane)
  if sourceIdx >= 0: workspace[].sessions[sourceIdx].terminal.damage.markAll()
  let freshIdx = workspace[].sessionIndex(fresh)
  if freshIdx >= 0: workspace[].sessions[freshIdx].terminal.damage.markAll()

proc closeActivePane() =
  let workspace = activeWorkspace()
  if workspace == nil or workspace[].sessions.len <= 1: return
  let paneId = workspace[].panes.active
  let idx = workspace[].sessionIndex(paneId)
  if idx < 0: return
  if not workspace[].panes.close(paneId): return
  workspace[].sessions[idx].terminal.close()
  workspace[].sessions.delete(idx)
  resizeTerminals()
  let term = activeTerm()
  if term != nil: term.damage.markAll()

proc removeTerminalTab(id: TabId) =
  if workspaces.len <= 1: return
  for i, workspace in workspaces:
    if workspace.id == id:
      for session in workspace.sessions:
        session.terminal.close()
      workspaces.delete(i)
      discard tabs.close(id)
      let term = activeTerm()
      if term != nil: term.damage.markAll()
      return

proc inTitleBar(y: int): bool =
  y >= 0 and y < titleBarHeight

proc inTabBar(y: int): bool =
  y >= titleBarHeight and y < headerHeight

proc localCol(area: PaneRect, x: cdouble): int =
  max(0, (int(x) - area.x) div rend.atlas.cellWidth)

proc localRow(area: PaneRect, y: cdouble): int =
  max(0, (int(y) - area.y) div rend.atlas.cellHeight)

proc activeWorkspaceDirty(): bool =
  let wi = activeWorkspaceIndex()
  if wi < 0: return false
  for session in workspaces[wi].sessions:
    if session.terminal.damage.anyDirty: return true
  false

proc drawActiveWorkspace() =
  let wi = activeWorkspaceIndex()
  if wi < 0: return
  let activeIdx = workspaces[wi].activeSessionIndex()
  if activeIdx < 0: return
  let bg = workspaces[wi].sessions[activeIdx].terminal.screen.theme.background
  glClearColor(bg.r.float32 / 255.0, bg.g.float32 / 255.0, bg.b.float32 / 255.0, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)
  let layouts = workspaces[wi].panes.layouts(contentRect())
  for item in layouts:
    let idx = workspaces[wi].sessionIndex(item.id)
    if idx < 0: continue
    rend.drawPaneBackground(workspaces[wi].sessions[idx].terminal, item.rect.x, item.rect.y, item.rect.w, item.rect.h, winWidth, winHeight)
    let inner = paneInnerRect(item.rect)
    rend.drawInRect(
      workspaces[wi].sessions[idx].terminal,
      winWidth,
      winHeight,
      inner.x,
      inner.y,
      inner.w,
      inner.h,
      showCursor = item.id == workspaces[wi].panes.active,
    )
  if workspaces[wi].panes.len > 1:
    for item in layouts:
      rend.drawPaneBorder(item.rect.x, item.rect.y, item.rect.w, item.rect.h, winWidth, winHeight, item.id == workspaces[wi].panes.active)

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
  result = newGlyphAtlas(targetFont, size, atlasSize = config.glyphAtlasSize)
  applyFontFallbacks(result)

proc rebuildAtlas() =
  let anchors = captureResizeAnchors()
  let atlas = makeAtlas(fontSize, font)
  let chromeAtlas = makeAtlas(config.fontSize, chromeFont)
  if rend != nil:
    rend.dispose()
  rend = newGpuTerminalRenderer(atlas, chromeAtlas)
  rend.loadLogoTexture(config.logoPath)
  updateChromeHeights()
  resizeTerminalViewsPreservingView(anchors)

proc snapshotToJson(s: ResourceSnapshot): JsonNode =
  result = %*{
    "total_live_bytes": s.totalLiveBytes,
    "total_peak_bytes": s.totalPeakBytes,
    "leak_count": s.leakCount(),
    "anomaly_count": s.anomalies.len,
    "has_leaks": s.hasLeaks(),
  }
  result["stats"] = newJArray()
  for row in s.stats:
    result["stats"].add %*{
      "kind": row.kind,
      "live_count": row.liveCount,
      "peak_count": row.peakCount,
      "live_bytes": row.liveBytes,
      "peak_bytes": row.peakBytes,
      "creates": row.creates,
      "updates": row.updates,
      "deletes": row.deletes,
    }
  result["live"] = newJArray()
  for rec in s.live:
    result["live"].add %*{
      "kind": rec.kind,
      "id": rec.id,
      "label": rec.label,
      "bytes": rec.bytes,
    }
  result["anomalies"] = newJArray()
  for anomaly in s.anomalies:
    result["anomalies"].add %*{
      "kind": $anomaly.kind,
      "resource_kind": anomaly.resourceKind,
      "id": anomaly.id,
      "label": anomaly.label,
      "detail": anomaly.detail,
    }

proc writeGpuSnapshot() =
  if gpuSnapshotPath.len == 0 or rend == nil: return
  try:
    writeFile(gpuSnapshotPath, $snapshotToJson(rend.gpuSnapshot()))
  except CatchableError:
    discard

proc writeScreenSnapshot(term: Terminal) =
  if screenSnapshotPath.len == 0 or term == nil: return
  try:
    var lines: seq[string] = @[]
    lines.add "closed=" & $term.host.closed
    lines.add "eof=" & $term.host.eof
    lines.add "cursor=" & $term.screen.cursor.row & "," & $term.screen.cursor.col
    lines.add "rows=" & $term.screen.rows & " cols=" & $term.screen.cols
    for i in 0 ..< min(term.screen.rows, 20):
      lines.add $i & ": " & term.screen.lineText(i)
    writeFile(screenSnapshotPath, lines.join("\n"))
  except CatchableError:
    discard

proc copyToClipboard(text: string) =
  let copied = copyText(text)
  if not copied.success:
    window.setClipboardString(cstring(text))

proc closeAllWorkspaces() =
  for workspace in workspaces:
    for session in workspace.sessions:
      session.terminal.close()
  workspaces.setLen(0)
  tabs = newTabSet()

proc renderOnce() =
  drawActiveWorkspace()
  rend.drawChrome(tabs, winWidth, winHeight, titleBarHeight, tabBarHeight, config.title)
  swapBuffers(window)
  writeGpuSnapshot()

proc runLifecycleChaos(cycles: int) =
  if cycles <= 0: return
  var maxTabs = 0
  var maxPanes = 0
  for i in 0 ..< cycles:
    case i mod 8
    of 0:
      addTerminalTab()
    of 1, 2:
      splitActivePane()
    of 3:
      closeActivePane()
    of 4:
      if tabs.activeId.isSome and tabs.tabs.len > 1:
        removeTerminalTab(tabs.activeId.get())
    of 5:
      fontSize += 1.0
      rebuildAtlas()
    of 6:
      fontSize = max(4.0, fontSize - 1.0)
      rebuildAtlas()
    else:
      winWidth = if winWidth == 1280: 960 else: 1280
      winHeight = if winHeight == 720: 640 else: 720
      glViewport(0, 0, cint(winWidth), cint(winHeight))
      resizeTerminals()

    maxTabs = max(maxTabs, tabs.tabs.len)
    let workspace = activeWorkspace()
    if workspace != nil:
      maxPanes = max(maxPanes, workspace[].sessions.len)
      for session in workspace[].sessions.mitems:
        session.terminal.damage.markAll()
    renderOnce()
    pollEvents()

  let snap = rend.gpuSnapshot()
  echo "[chaos] cycles=", cycles,
       " max_tabs=", maxTabs,
       " max_panes=", maxPanes,
       " gpu_live_bytes=", snap.totalLiveBytes,
       " gpu_peak_bytes=", snap.totalPeakBytes,
       " live_resources=", snap.leakCount(),
       " anomalies=", snap.anomalies.len

# ---------------------------------------------------------------------------
# GLFW Callbacks
# ---------------------------------------------------------------------------

proc onChar(win: Window, codepoint: cuint) {.cdecl.} =
  if keyTextFallback: return
  let term = activeTerm()
  if term == nil: return
  let sent = term.sendKey(keyChar(uint32(codepoint)))
  if inputDebug: echo "[input] char codepoint=", codepoint, " queued=", sent
  term.damage.markAll()

proc onKey(win: Window, key, scancode, action, mods: cint) {.cdecl.} =
  if action == PRESS or action == REPEAT:
    let term = activeTerm()
    if term == nil: return
    let m = castSet(mods)
    if inputDebug: echo "[input] key key=", key, " action=", action, " mods=", mods

    if terminal.modCtrl in m and terminal.modShift in m and key == KEY_T:
      addTerminalTab()
      return
    if terminal.modCtrl in m and terminal.modShift in m and key == KEY_ENTER:
      splitActivePane()
      return
    if terminal.modCtrl in m and terminal.modShift in m and key == KEY_W:
      closeActivePane()
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
          copyToClipboard(text)
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
        let sent = term.sendKey(keyChar(ch.get(), m))
        if inputDebug: echo "[input] modified printable codepoint=", ch.get(), " queued=", sent
        term.damage.markAll()
        return
    elif keyTextFallback:
      let ch = toPrintableRune(key, mods)
      if ch.isSome:
        let sent = term.sendKey(keyChar(ch.get(), m))
        if inputDebug: echo "[input] fallback printable codepoint=", ch.get(), " queued=", sent
        term.damage.markAll()
        return

    # 3. Standard keys
    let tk = toKeyCode(key).int
    if tk != 0 and tk != 1: # 0 = kNone, 1 = kChar
      let sent = term.sendKey(terminal.key(cast[terminal.KeyCode](tk), m))
      if inputDebug: echo "[input] special key=", tk, " queued=", sent
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

  if int(y) < headerHeight: return
  let session = focusPaneAt(int(x), int(y))
  if session == nil: return
  let term = session[].terminal
  let area = activeSessionRect(session[].id)
  if area.isNone: return
  let col = localCol(area.get(), x); let row = localRow(area.get(), y)
  let absRow = term.viewport.viewportToBuffer(row)
  if term.inputMode.shouldIntercept(castSet(mods)):
    if button == MOUSE_BUTTON_LEFT:
      let isDown = action == PRESS

      # Handle link clicking
      if not isDown and term.activeLink.isSome:
        launchUri(term.activeLink.get().link.text)
        return

      term.drag.update(absRow, col, isDown)
      if isDown:
        let wi = activeWorkspaceIndex()
        if wi >= 0: clearSelectionsExcept(workspaces[wi], session[].id)
        term.selection.start(point(absRow, col))
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

  if int(y) < headerHeight:
    let term = activeTerm()
    if term == nil: return
    if term.activeLink.isSome:
      term.activeLink = none(ActiveLink)
      term.damage.markAll()
    return
  let wi = activeWorkspaceIndex()
  if wi < 0: return
  let activeId = workspaces[wi].panes.active
  let sessionIdx = workspaces[wi].sessionIndex(activeId)
  if sessionIdx < 0: return
  let term = workspaces[wi].sessions[sessionIdx].terminal
  let area = activeSessionRect(activeId)
  if area.isNone: return
  let col = localCol(area.get(), x); let row = localRow(area.get(), y)
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
  var x, y: cdouble; getCursorPos(win, addr x, addr y)
  let session = if int(y) >= headerHeight: focusPaneAt(int(x), int(y)) else: nil
  let term = if session == nil: activeTerm() else: session[].terminal
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

proc resizeToFramebuffer(win: Window, fallbackWidth, fallbackHeight: cint) =
  var fbWidth, fbHeight: cint
  var windowWidth, windowHeight: cint
  getFramebufferSize(win, addr fbWidth, addr fbHeight)
  getWindowSize(win, addr windowWidth, addr windowHeight)
  let report = chooseDrawableSize(
    framebuffer = size2d(int(fbWidth), int(fbHeight)),
    window = size2d(int(windowWidth), int(windowHeight)),
    fallback = size2d(int(fallbackWidth), int(fallbackHeight)),
  )
  if not report.chosen.isPositive:
    return
  let actualWidth = cint(report.chosen.width)
  let actualHeight = cint(report.chosen.height)
  let changedSize = report.changedFrom(size2d(winWidth, winHeight))
  if changedSize:
    winWidth = report.chosen.width
    winHeight = report.chosen.height
    if rend != nil and rend.atlas != nil:
      resizeTerminals()
  glViewport(0, 0, actualWidth, actualHeight)
  if resizeSnapshotPath.len > 0:
    try:
      let content = contentRect()
      let layouts = activePaneLayouts()
      let firstPane =
        if layouts.len > 0: layouts[0].rect
        else: pane_tree.rect(0, 0, 0, 0)
      let inner = paneInnerRect(firstPane)
      writeFile(resizeSnapshotPath,
        formatSizeDiagnostics(report) &
        "content=" & $content.w & "x" & $content.h & "\n" &
        "pane=" & $firstPane.w & "x" & $firstPane.h & "\n" &
        "inner=" & $inner.w & "x" & $inner.h & "\n" &
        "grid=" & $paneCols(firstPane) & "x" & $paneRows(firstPane) & "\n")
    except CatchableError:
      discard

proc onResize(win: Window, width, height: cint) {.cdecl.} =
  resizeToFramebuffer(win, width, height)

proc syncFramebufferSize(): bool =
  if window == nil:
    return false
  var fbWidth, fbHeight: cint
  var windowWidth, windowHeight: cint
  getFramebufferSize(window, addr fbWidth, addr fbHeight)
  getWindowSize(window, addr windowWidth, addr windowHeight)
  let report = chooseDrawableSize(
    framebuffer = size2d(int(fbWidth), int(fbHeight)),
    window = size2d(int(windowWidth), int(windowHeight)),
    fallback = size2d(0, 0),
  )
  if not report.chosen.isPositive:
    return false
  if not report.changedFrom(size2d(winWidth, winHeight)):
    return false
  resizeToFramebuffer(window, cint(report.chosen.width), cint(report.chosen.height))
  true

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

config = loadTerminalConfig()
fontSize = config.fontSize
lifecycleChaosCycles = parseIntOr(getEnv("WAYMARK_LIFECYCLE_CHAOS_CYCLES", "0"), 0)
keyTextFallback =
  getEnv("WAYMARK_KEY_TEXT_FALLBACK", "0") == "1"
inputDebug = getEnv("WAYMARK_INPUT_DEBUG", "0") == "1"

if init() == 0: quit("Failed to init GLFW")
windowHint(CONTEXT_VERSION_MAJOR, 2); windowHint(CONTEXT_VERSION_MINOR, 1)
chooseInitialWindowSize()
window = createWindow(cint(winWidth), cint(winHeight), cstring(config.title), nil, nil)
if window == nil: quit("Failed to create window")
setWindowSizeLimits(window, cint(MinWindowWidth), cint(MinWindowHeight), DONT_CARE, DONT_CARE)
focusWindow(window)
makeContextCurrent(window); loadExtensions()
var fbWidth, fbHeight: cint
getFramebufferSize(window, addr fbWidth, addr fbHeight)
if fbWidth > 0 and fbHeight > 0:
  winWidth = int(fbWidth)
  winHeight = int(fbHeight)
  glViewport(0, 0, fbWidth, fbHeight)

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
discard window.setWindowSizeCallback(onResize)

onResize(window, cint(winWidth), cint(winHeight))
writeGpuSnapshot()

if lifecycleChaosCycles > 0:
  runLifecycleChaos(lifecycleChaosCycles)
  closeAllWorkspaces()
  if rend != nil:
    rend.dispose()
    writeGpuSnapshot()
  terminate()
  quit(0)

let perf = newPerfMonitor()
while windowShouldClose(window) == 0:
  perf.beginFrame()
  let resized = syncFramebufferSize()
  var n = 0
  for workspace in workspaces.mitems:
    for session in workspace.sessions.mitems:
      let readCount = session.terminal.step()
      if readCount > 0:
        session.terminal.refreshViewport(stickToBottom = true)
      n += readCount
  let term = activeTerm()
  if term == nil: break
  if atlas.isDirty: rend.updateAtlasTexture()
  let tabLabelsChanged = refreshTabCwdLabels()
  let changed = resized or n > 0 or atlas.isDirty or activeWorkspaceDirty() or tabLabelsChanged
  if changed:
    drawActiveWorkspace()
    rend.drawChrome(tabs, winWidth, winHeight, titleBarHeight, tabBarHeight, config.title)
    swapBuffers(window)
    writeGpuSnapshot()
    writeScreenSnapshot(term)
  pollEvents(); perf.endFrame()
  if perf.shouldReport(2.0):
    let s = perf.takeReport()
    echo "FPS: ", s.fps, " Latency: ", s.avgLatencyMs, " ms"
  if not changed: os.sleep(1)

if rend != nil:
  rend.dispose()
  writeGpuSnapshot()
terminate()
