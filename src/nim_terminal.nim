## Waymark terminal application.
##
## Main entry point: creates a window, loads a font, and runs the
## terminal pipeline with a Pixie-based renderer.

when defined(waymarkSdl3):
  import sdl3 as sdl
else:
  import staticglfw
import opengl
import pixie
import os
import std/[algorithm, json, options, osproc, parsecfg, streams, strutils, times, unicode]
import terminal
import gpu_renderer
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
when not defined(waymarkSdl3):
  from ../cg/frontend_glfw_input_nim/src/glfw_input_lib import toKeyCode, toMouseButton, toPrintableRune
import ../cg/universal_perf_monitor_nim/src/perf_monitor_lib
import ../cg/universal_shortcut_map_nim/src/shortcut_map_lib
import ../cg/frontend_glfw_window_nim/src/glfw_window_lib
from ../cg/frontend_render_relays_nim/src/render_relays_lib as render_relay_lib import nil
from ../cg/frontend_window_relays_nim/src/window_relays_lib as window_relay_lib import nil
from ../cg/frontend_gpu_relays_nim/src/gpu_relays_lib as gpu_relay_lib import nil
from ../cg/frontend_opengl_gpu_driver_nim/src/opengl_gpu_driver_lib as opengl_gpu_driver_lib import nil
import ../cg/universal_os_launcher_nim/src/os_launcher_lib
import ../cg/universal_tab_set_nim/src/tab_set_lib
import ../cg/universal_process_cwd_nim/src/process_cwd_lib
import ../cg/universal_title_resolver_nim/src/title_resolver_lib
import ../cg/universal_path_candidates_nim/src/path_candidates_lib
import ../cg/universal_split_pane_tree_nim/src/split_pane_tree_lib as pane_tree
import ../cg/universal_resource_budget_nim/src/resource_budget_lib
import ../cg/universal_resource_ledger_nim/src/resource_ledger_lib
from ../cg/universal_clipboard_provider_nim/src/clipboard_provider_lib as clipboard_provider_lib import nil
from ../cg/backend_system_clipboard_nim/src/system_clipboard_lib as system_clipboard_lib import nil
import ../cg/data_terminal_scroll_policy_nim/src/terminal_scroll_policy_lib
import ../cg/data_terminal_profile_nim/src/terminal_profile_lib
import ../cg/frontend_app_surface_relays_nim/src/app_surface_relays_lib
import ../cg/frontend_workspace_chrome_nim/src/workspace_chrome_lib
import ../cg/frontend_overlay_stack_nim/src/overlay_stack_lib as overlay_lib
import cartograph_surface
import overlay_surface
import inspect_surface
import ../cg/frontend_text_field_nim/src/text_field_lib as text_field
import ../cg/frontend_focus_ring_nim/src/focus_ring_lib as focus_ring
import ../cg/frontend_menu_nim/src/menu_lib as menu_lib
import ../cg/frontend_scrollbar_nim/src/scrollbar_lib as scrollbar_lib
import ../cg/frontend_toast_nim/src/toast_lib as toast_lib

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
  CartographSidebarWidth = 300
  CartographCatalogHeightMax = 360
  CartographActionBarHeight = 36
  CartographCatalogFooterHeight = 36
  CartographRailPad = 10
  CatalogScrollbarWidth = 6
  DefaultCatalogPollSec = 1.0
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
    title: TitleState

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
    altScreenScrollback: AltScreenScrollbackMode
    altWheelPolicy: AltWheelPolicy
    normalWheelPolicy: NormalWheelPolicy
    meaningfulHistoryRows: int
    profileMode: ProfileMode
    shortcutPreset: ShortcutPreset
    chrome: set[ChromeFeature]

var
  appProfile: TerminalProfileState
  surfaceStack: AppSurfaceStack = newAppSurfaceStack()
  overlayStack: overlay_lib.OverlayStack = overlay_lib.newOverlayStack()
  inspectSession: InspectSession = newInspectSession()
  cartographWorkspace: CartographWorkspace
  cartographFocus: focus_ring.FocusRing = focus_ring.newFocusRing(["search"])
  catalogMenu: menu_lib.Menu = menu_lib.newMenu(@[
    menu_lib.menuItem("inspect", "Inspect"),
    menu_lib.menuItem("copy-id", "Copy id"),
  ])
  catalogMenuOpen = false
  catalogMenuAnchorX = 0
  catalogMenuAnchorY = 0
  catalogScrollDrag: scrollbar_lib.ScrollbarDrag
  appToasts: toast_lib.ToastQueue = toast_lib.newToastQueue()
  activeSearchProcess: Process = nil
  activeSearchQuery = ""
  catalogRootPath = DefaultCatalogRoot
  lastCatalogScanCwd = ""
  lastCatalogPollTime = 0.0
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
    altScreenScrollback: assPassive,
    altWheelPolicy: awpTerminal,
    normalWheelPolicy: nwpTerminal,
    meaningfulHistoryRows: DefaultMeaningfulHistoryRows,
    profileMode: pmStandard,
    shortcutPreset: spStandard,
    chrome: {},
  )
  tabs = newTabSet()
  workspaces: seq[TerminalWorkspace] = @[]
  rend: GpuTerminalRenderer
  frameRelays: render_relay_lib.RenderRelays
  windowRelays: window_relay_lib.WindowRelays
  gpuRelays: gpu_relay_lib.GpuRelays
  glTriangleDriver: opengl_gpu_driver_lib.OpenGlTriangleDriver
  glVertexScratch: seq[opengl_gpu_driver_lib.TexturedVertex] = @[]
  clipboardProviders: seq[clipboard_provider_lib.ClipboardProvider] = @[]
  clipboardPolicy = clipboard_provider_lib.defaultClipboardPolicy()
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
  # Last cell a mouse report was sent for. xterm only emits motion when the
  # pointer crosses into a new character cell; tracking this lets us suppress
  # per-pixel motion floods that would otherwise turn a click into a drag.
  lastMouseReportRow = -1
  lastMouseReportCol = -1

when defined(waymarkSdl3):
  var
    glContext: sdl.GLContext
    appShouldClose = false

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

proc applyProfileSnapshot(cfg: var TerminalConfig; snap: TerminalProfileSnapshot) =
  cfg.profileMode = snap.mode
  cfg.maxPanes = snap.maxPanes
  cfg.diagnosticsCapacity = snap.diagnosticsCapacity
  cfg.meaningfulHistoryRows = snap.meaningfulHistoryRows
  cfg.shortcutPreset = snap.shortcutPreset
  cfg.chrome = snap.chrome
  cfg.altScreenScrollback = parseAltScreenScrollbackMode(
    snap.altScreenScrollback,
    cfg.altScreenScrollback,
  )
  cfg.altWheelPolicy = parseAltWheelPolicy(snap.altWheelPolicy, cfg.altWheelPolicy)
  cfg.normalWheelPolicy = parseNormalWheelPolicy(snap.normalWheelPolicy, cfg.normalWheelPolicy)
  cfg.scrollback = snap.scrollback

proc reapplyActiveProfile() =
  applyProfileSnapshot(config, snapshot(appProfile))

proc refreshSessionShortcutMaps() =
  let preset = config.shortcutPreset
  for workspace in workspaces:
    for session in workspace.sessions:
      session.terminal.shortcuts = newShortcutMap()
      populateShortcutMap(session.terminal.shortcuts, preset)

proc loadTerminalConfig(path = ConfigPath): TerminalConfig =
  result = config
  var dict: Config
  var hasFile = fileExists(path)
  if hasFile:
    try:
      dict = loadConfig(path)
    except CatchableError as e:
      echo "Config warning: ", e.msg
      hasFile = false

  proc lookup(section, key: string): string =
    if hasFile:
      dict.getSectionValue(section, key)
    else:
      ""

  if hasFile:
    try:
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
      let requestedAtlas = max(256, parseIntOr(dict.getSectionValue("resources", "glyph_atlas_size", $result.glyphAtlasSize), result.glyphAtlasSize))
      result.glyphAtlasSize = int(recommendedCap(resourceLimit("glyph_atlas", DefaultGlyphAtlasSize, MaxGlyphAtlasSize), requestedAtlas.int64))
    except CatchableError as e:
      echo "Config warning: ", e.msg

  appProfile = resolveTerminalProfile(lookup, getEnv("WAYMARK_MODE", ""))
  applyProfileSnapshot(result, snapshot(appProfile))
  result.scrollback = int(recommendedCap(
    resourceLimit("scrollback", DefaultScrollback, MaxScrollback),
    result.scrollback.int64,
  ))

func appSurfaceConfigValue(id: AppSurfaceId): string =
  case id
  of asPrimary: "primary"
  of asWorkspace: "workspace"

proc persistActiveSurface(path = ConfigPath) =
  var dict: Config
  if fileExists(path):
    try:
      dict = loadConfig(path)
    except CatchableError:
      dict = Config()
  else:
    dict = Config()
  dict.setSectionKey("surface", "default", appSurfaceConfigValue(surfaceStack.active))
  try:
    writeConfig(dict, path)
  except CatchableError as e:
    echo "Config warning: could not save surface state: ", e.msg

proc configFileBaseDir(): string =
  if fileExists(ConfigPath):
    splitFile(absolutePath(ConfigPath)).dir
  else:
    getCurrentDir()

proc catalogPollIntervalSec(): float =
  block:
    let raw = getEnv("WAYMARK_CATALOG_POLL_SEC", $DefaultCatalogPollSec)
    try:
      max(0.5, parseFloat(raw))
    except CatchableError:
      DefaultCatalogPollSec

proc resolveCatalogRoot(primaryCwd: string = ""): string =
  let envRoot = getEnv("WAYMARK_CATALOG_ROOT", "").strip()
  if envRoot.len > 0:
    let resolved = absolutePath(resolveCandidatePath(envRoot, getCurrentDir()))
    if dirExists(resolved):
      return resolved
  let baseDir = if primaryCwd.len > 0: expandTilde(primaryCwd.strip()) else: getCurrentDir()
  absolutePath(resolveCandidatePath(DefaultCatalogRoot, baseDir))

func toChildWheelEncoding(kind: ScrollInputKind): ChildWheelEncoding =
  case kind
  of sikMouseWheel: cweMouseWheel
  of sikCursorKeys: cweCursorKeys
  of sikNone: cweNone

when not defined(waymarkSdl3):
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

proc pollActiveShellCwd(): string =
  let workspace = activeWorkspace()
  if workspace == nil:
    return ""
  let idx = workspace[].activeSessionIndex()
  if idx < 0:
    return ""
  when not defined(windows):
    let live = processCwd(workspace[].sessions[idx].terminal.host.pid)
    if live.isSome:
      workspace[].sessions[idx].cwd = live.get()
      return live.get()
  workspace[].sessions[idx].cwd

proc activeWorkspaceSyncUpdateActive(): bool =
  let workspace = activeWorkspace()
  if workspace == nil: return false
  for session in workspace[].sessions:
    if session.terminal != nil and session.terminal.synchronizedUpdateActive():
      return true
  false

proc sessionByPane(workspace: var TerminalWorkspace, paneId: PaneId): ptr TerminalSession =
  let idx = workspace.sessionIndex(paneId)
  if idx < 0: nil else: addr workspace.sessions[idx]

proc tabLabelForWorkspace(workspace: TerminalWorkspace): string =
  let activeIdx = workspace.activeSessionIndex()
  if activeIdx < 0:
    ""
  else:
    workspace.sessions[activeIdx].title.resolve()

proc refreshWorkspaceTabLabel(wi: int): bool =
  if wi < 0 or wi >= workspaces.len or workspaces[wi].sessions.len == 0:
    return false
  let activeIdx = workspaces[wi].activeSessionIndex()
  if activeIdx < 0:
    return false

  var changed = false
  let session = addr workspaces[wi].sessions[activeIdx]

  # 1. Update CWD
  when not defined(windows):
    let liveCwd = processCwd(session.terminal.host.pid)
    if liveCwd.isSome:
      session.cwd = liveCwd.get()
      if session.title.updateCwd(liveCwd.get()):
        changed = true

    # 2. Update Program Name
    let prog = processName(session.terminal.host.pid)
    if prog.isSome:
      if session.title.updateProgramName(prog.get()):
        changed = true

  # 3. Update OSC Title
  if session.title.updateOscTitle(session.terminal.screen.title):
    changed = true

  let label = tabLabelForWorkspace(workspaces[wi])
  if label.len == 0:
    return false
  let tabId = workspaces[wi].id
  let tabIdx = tabs.indexOf(tabId)
  if tabIdx < 0: return false

  if tabs.tabs[tabIdx].label != label:
    result = tabs.rename(tabId, label)
  else:
    result = false

proc chromeHeaderHeight(): int =
  workspaceHeaderHeight(titleBarHeight, tabBarHeight, surfaceStack.active)

proc contentHeight(): int = max(1, winHeight - chromeHeaderHeight())

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

proc fullContentRect(): pane_tree.Rect =
  pane_tree.rect(0, chromeHeaderHeight(), winWidth, contentHeight())

proc cartographCatalogFooterHeight(): int

proc cartographRegions(): ThreeColumnRegions =
  let full = fullContentRect()
  let bounds = WorkspaceRect(x: full.x, y: full.y, w: full.w, h: full.h)
  var catalogH = min(CartographCatalogHeightMax, max(160, bounds.h * 42 div 100))
  if cartographWorkspace != nil and rend != nil and rend.chromeAtlas != nil:
    let entryCount = cartographWorkspace.visibleEntries.len
    let cellHeight = rend.chromeAtlas.cellHeight
    let stride = cellHeight * 2 + 10
    let pad = 10
    let titleArea = pad + cellHeight + 8
    let footerArea = cartographCatalogFooterHeight()
    let bottomPadding = pad
    let scrollArrowH = max(18, cellHeight + 6)

    let neededH =
      if entryCount <= 3:
        titleArea + entryCount * stride + bottomPadding + footerArea
      else:
        titleArea + 2 * scrollArrowH + 3 * stride + bottomPadding + footerArea

    catalogH = min(bounds.h, max(neededH, 48))

  sidebarCatalogRegions(
    bounds,
    sidebarWidth = CartographSidebarWidth,
    catalogHeight = catalogH,
    minCenterWidth = 320,
  )

proc contentRect(): pane_tree.Rect =
  if surfaceStack.active != asWorkspace:
    fullContentRect()
  else:
    let center = contentBelowActionBar(cartographRegions().center, CartographActionBarHeight)
    pane_tree.rect(center.x, center.y, center.w, center.h)

proc cartographCatalogFooterHeight(): int =
  if cartographWorkspace.selectedIndex >= 0 and cartographWorkspace.visibleEntries.len > 0:
    CartographCatalogFooterHeight
  else:
    0

proc activeCatalogInspectButtonRect(): overlay_lib.OverlayRect =
  let regions = cartographRegions()
  if regions.catalog.w <= 0 or rend == nil or rend.chromeAtlas == nil:
    overlay_lib.OverlayRect()
  else:
    overlay_surface.catalogInspectButtonRect(
      overlay_lib.OverlayRect(
        x: regions.catalog.x,
        y: regions.catalog.y,
        w: regions.catalog.w,
        h: regions.catalog.h,
      ),
      cartographCatalogFooterHeight(),
      rend.chromeAtlas.cellWidth,
      rend.chromeAtlas.cellHeight,
      CartographRailPad,
    )

proc activeModalLayout(): overlay_lib.ModalChromeLayout =
  let top = overlay_lib.overlayTop(overlayStack)
  let bounds = overlay_surface.overlayContentBounds(chromeHeaderHeight(), winWidth, winHeight)
  var metrics = overlay_lib.defaultModalChromeMetrics(
    rend.chromeAtlas.cellWidth,
    rend.chromeAtlas.cellHeight,
  )
  if top.id == "search_registry":
    metrics.maxPanelWidth = min(800, winWidth - 48)
    metrics.minPanelWidth = min(600, winWidth - 48)
  overlay_lib.computeModalChromeLayout(bounds, top.panel, metrics)

proc activeExplorerLayout(): overlay_lib.ExplorerChromeLayout =
  let top = overlay_lib.overlayTop(overlayStack)
  let bounds = overlay_surface.overlayContentBounds(chromeHeaderHeight(), winWidth, winHeight)
  let metrics = overlay_lib.defaultExplorerChromeMetrics(
    rend.chromeAtlas.cellWidth,
    rend.chromeAtlas.cellHeight,
  )
  overlay_lib.computeExplorerChromeLayout(bounds, top.title, metrics)

proc dismissTopOverlay() =
  let top = overlay_lib.overlayTop(overlayStack)
  if top.kind == overlay_lib.okExplorer:
    closeInspectSession(inspectSession)
  elif top.id == "search_registry" or top.id == "search_error":
    if activeSearchProcess != nil:
      try:
        activeSearchProcess.terminate()
        activeSearchProcess.close()
      except CatchableError:
        discard
      activeSearchProcess = nil
  discard overlay_lib.overlayDismissTop(overlayStack)

proc showInspectExplorer() =
  let entry = selectedCartographEntry(cartographWorkspace)
  if entry.dirName.len == 0:
    return
  let widgetPath = catalogRootPath / entry.dirName
  if not dirExists(widgetPath):
    return
  let title =
    if entry.name.len > 0:
      "Inspect: " & entry.name
    else:
      "Inspect: " & entry.id
  openInspectSession(inspectSession, widgetPath, title)
  overlayStack.overlayPushExplorer("inspect-" & entry.id, title)

proc handleOverlayPointer(x, y: int; down: bool): bool =
  if not overlay_lib.overlayCapturesInput(overlayStack):
    return false
  if not down:
    return true
  let top = overlay_lib.overlayTop(overlayStack)
  case top.kind
  of overlay_lib.okConfirm:
    let layout = activeModalLayout()
    let hit = overlay_lib.overlayHitTestModal(layout, x, y, top.dismissOnBackdrop)
    case hit.kind
    of overlay_lib.ohBackdrop:
      dismissTopOverlay()
      return true
    of overlay_lib.ohButton:
      dismissTopOverlay()
      return true
    of overlay_lib.ohPanel, overlay_lib.ohNone:
      return overlay_lib.pointInOverlayRect(layout.panel, x, y)
  of overlay_lib.okExplorer:
    let layout = activeExplorerLayout()
    let backdropHit = overlay_lib.overlayHitTestExplorer(layout, x, y, top.dismissOnBackdrop)
    if backdropHit.kind == overlay_lib.ohBackdrop:
      dismissTopOverlay()
      return true
    return handleInspectExplorerPointer(
      inspectSession,
      layout,
      x, y,
      down,
      rend.chromeAtlas.cellWidth,
      rend.chromeAtlas.cellHeight,
    )

proc handleOverlayWheel(x, y: int; yoffset: float): bool =
  if surfaceStack.active != asWorkspace:
    return false
  if not overlay_lib.overlayCapturesInput(overlayStack):
    return false
  let top = overlay_lib.overlayTop(overlayStack)
  if top.kind != overlay_lib.okExplorer:
    return true
  let layout = activeExplorerLayout()
  let cellW = rend.chromeAtlas.cellWidth
  let cellH = rend.chromeAtlas.cellHeight
  if overlay_lib.pointInOverlayRect(layout.treePane, x, y):
    let treeLayout = inspectTreeLayout(inspectSession, layout.treePane, cellW, cellH)
    if handleInspectTreeWheel(inspectSession, treeLayout, yoffset):
      return true
  if overlay_lib.pointInOverlayRect(layout.codePane, x, y):
    if handleInspectCodeWheel(inspectSession, layout.codePane, cellW, cellH, yoffset):
      return true
  overlay_lib.pointInOverlayRect(layout.panel, x, y)

proc handleOverlayEscape(): bool =
  if not overlay_lib.overlayCapturesInput(overlayStack):
    return false
  let top = overlay_lib.overlayTop(overlayStack)
  if top.dismissOnEscape:
    dismissTopOverlay()
    return true
  false

proc drawOverlays() =
  if overlay_lib.overlayIsEmpty(overlayStack):
    return
  let top = overlay_lib.overlayTop(overlayStack)
  case top.kind
  of overlay_lib.okConfirm:
    let layout = activeModalLayout()
    rend.drawModalOverlay(winWidth, winHeight, layout, top.panel)
  of overlay_lib.okExplorer:
    let layout = activeExplorerLayout()
    let cellW = rend.chromeAtlas.cellWidth
    let cellH = rend.chromeAtlas.cellHeight
    let treeLayout = inspectTreeLayout(inspectSession, layout.treePane, cellW, cellH)
    let treeRows = inspectTreeRows(inspectSession)
    let codeViewport = inspectCodeViewport(inspectSession, layout.codePane, cellW, cellH)
    rend.drawExplorerOverlay(
      winWidth,
      winHeight,
      layout,
      top.title,
      treeLayout,
      treeRows,
      codeViewport,
      inspectSession.previewPath,
      inspectSession.tree.selectedIndex,
    )

proc catalogListLayout(): CatalogListLayout =
  let regions = cartographRegions()
  if regions.catalog.w <= 0 or rend == nil or rend.chromeAtlas == nil:
    return CatalogListLayout()
  let listH = max(0, regions.catalog.h - cartographCatalogFooterHeight())
  computeCatalogListLayout(
    regions.catalog.x,
    regions.catalog.y,
    regions.catalog.w,
    listH,
    rend.chromeAtlas.cellHeight,
    rend.chromeAtlas.cellWidth,
    CartographRailPad,
    cartographWorkspace.catalogScrollRow,
    cartographWorkspace.visibleEntries.len,
  )

proc pointInCatalogList(x, y: int): bool =
  let regions = cartographRegions()
  if regions.catalog.w <= 0:
    return false
  let layout = catalogListLayout()
  if layout.visibleRows <= 0:
    return false
  x >= layout.contentX and x < layout.contentX + layout.contentW and
    y >= layout.listY and y < layout.listY + layout.visibleRows * layout.stride

proc catalogEntryIndexAt(x, y: int): int =
  if surfaceStack.active != asWorkspace or cartographWorkspace.visibleEntries.len == 0:
    return -1
  let layout = catalogListLayout()
  if x < layout.contentX or x >= layout.contentX + layout.contentW:
    return -1
  if not pointInCatalogList(x, y):
    return -1
  var rowY = layout.listY
  for local in 0 ..< min(
      cartographWorkspace.visibleEntries.len - cartographWorkspace.catalogScrollRow,
      layout.visibleRows,
    ):
    if y >= rowY - 2 and y < rowY + catalogRowHeight(rend.chromeAtlas.cellHeight) + 4:
      return cartographWorkspace.catalogScrollRow + local
    rowY += layout.stride
  -1

proc pointInRect(x, y: int; area: PaneRect): bool =
  x >= area.x and x < area.x + area.w and y >= area.y and y < area.y + area.h

proc searchInputActive(): bool =
  ## True when the Cartograph search field currently owns keyboard input.
  surfaceStack.active == asWorkspace and
    not overlay_lib.overlayCapturesInput(overlayStack) and
    cartographFocus.isFocused("search")

proc refreshCatalogFilter() =
  applyCatalogFilter(cartographWorkspace, catalogListLayout().visibleRows)
  markCartographDirty(cartographWorkspace)

proc focusCartographSearch() =
  discard cartographFocus.focus("search")
  markCartographDirty(cartographWorkspace)

proc blurCartographSearch() =
  if cartographFocus.hasFocus():
    cartographFocus.clearFocus()
    markCartographDirty(cartographWorkspace)

proc searchInsertRune(r: Rune) =
  if not searchInputActive():
    return
  cartographWorkspace.search.insertRune(r)
  refreshCatalogFilter()

proc searchInsertText(text: string) {.used.} =
  ## Used by the SDL text-input path; unused under the GLFW build config.
  if not searchInputActive():
    return
  for r in text.runes:
    cartographWorkspace.search.insertRune(r)
  refreshCatalogFilter()

proc triggerSearchModal(query: string) =
  let q = query.strip()
  if q.len == 0:
    return

  if activeSearchProcess != nil:
    try:
      activeSearchProcess.terminate()
      activeSearchProcess.close()
    except CatchableError:
      discard
    activeSearchProcess = nil

  try:
    activeSearchProcess = startProcess(
      command = "cartograph",
      args = @["search", q],
      options = {poUsePath, poStdErrToStdOut}
    )
    activeSearchQuery = q
  except CatchableError as e:
    activeSearchProcess = nil
    let errPanel = overlay_lib.OverlayPanel(
      title: "Registry Search Error",
      body: "Could not start cartograph search:\n\n" & e.msg,
      buttons: @[
        overlay_lib.OverlayButton(label: "Close", actionId: "close_search_error", primary: true)
      ]
    )
    overlayStack.overlayPushModal("search_error", errPanel)
    markCartographDirty(cartographWorkspace)
    return

  let searchingPanel = overlay_lib.OverlayPanel(
    title: "Search Cartograph Registry",
    body: "Searching registry for: '" & q & "'...\n\nPlease wait a moment.",
    buttons: @[
      overlay_lib.OverlayButton(label: "Cancel", actionId: "cancel_search", primary: true)
    ]
  )
  overlayStack.overlayPushModal("search_registry", searchingPanel)
  markCartographDirty(cartographWorkspace)

proc checkSearchProcess() =
  if activeSearchProcess != nil:
    if not activeSearchProcess.running():
      var output = ""
      try:
        output = activeSearchProcess.outputStream.readAll()
      except CatchableError as e:
        output = "Error reading output: " & e.msg

      try:
        activeSearchProcess.close()
      except CatchableError:
        discard
      activeSearchProcess = nil

      var title = "Registry Search Results"
      var body = ""

      try:
        let jsonNode = parseJson(output)
        let localNode = jsonNode{"local"}
        let registryNode = jsonNode{"registry"}

        var results: seq[string] = @[]

        proc formatWidgets(node: JsonNode; header: string) =
          if node != nil:
            let count = if node{"count"} != nil and node{"count"}.kind == JInt: node{"count"}.num.int else: 0
            let widgets = node{"widgets"}
            if widgets != nil and widgets.kind == JArray and widgets.len > 0:
              if results.len > 0:
                results.add ""
              results.add "=== " & header & " (" & $count & ") ==="
              for widget in widgets:
                let id = if widget{"id"} != nil and widget{"id"}.kind == JString: widget{"id"}.str else: ""
                let desc = if widget{"description"} != nil and widget{"description"}.kind == JString: widget{"description"}.str else: ""
                let lang = if widget{"language"} != nil and widget{"language"}.kind == JString: widget{"language"}.str else: ""
                if id.len > 0:
                  results.add "* " & id & " [" & lang & "]"
                  if desc.len > 0:
                    let shortDesc = if desc.len > 120: desc[0..117] & "..." else: desc
                    results.add "  " & shortDesc.strip().replace("\n", " ")

        formatWidgets(localNode, "Installed Widgets")
        formatWidgets(registryNode, "Registry Widgets")

        if results.len == 0:
          body = "No widgets found matching '" & activeSearchQuery & "'."
        else:
          body = results.join("\n")
      except CatchableError as e:
        body = "Search Output for '" & activeSearchQuery & "':\n\n" & output.strip()

      # Update the active modal overlay!
      if not overlayStack.overlayIsEmpty():
        let topIdx = overlayStack.layers.len - 1
        if overlayStack.layers[topIdx].id == "search_registry":
          overlayStack.layers[topIdx].panel.title = title
          overlayStack.layers[topIdx].panel.body = body
          overlayStack.layers[topIdx].panel.buttons = @[
            overlay_lib.OverlayButton(label: "Close", actionId: "close_search", primary: true)
          ]
          markCartographDirty(cartographWorkspace)

type SearchEditKey = enum
  sekBackspace, sekDelete, sekLeft, sekRight, sekHome, sekEnd, sekEscape, sekEnter

proc handleSearchEditKey(k: SearchEditKey): bool =
  ## Apply an editing/navigation key to the focused search field.
  ## Returns true when the key was consumed (must not reach the terminal).
  if not searchInputActive():
    return false
  case k
  of sekBackspace:
    if cartographWorkspace.search.backspace(): refreshCatalogFilter()
  of sekDelete:
    if cartographWorkspace.search.deleteForward(): refreshCatalogFilter()
  of sekLeft:
    cartographWorkspace.search.moveLeft()
    markCartographDirty(cartographWorkspace)
  of sekRight:
    cartographWorkspace.search.moveRight()
    markCartographDirty(cartographWorkspace)
  of sekHome:
    cartographWorkspace.search.moveHome()
    markCartographDirty(cartographWorkspace)
  of sekEnd:
    cartographWorkspace.search.moveEnd()
    markCartographDirty(cartographWorkspace)
  of sekEscape:
    blurCartographSearch()
  of sekEnter:
    let q = cartographWorkspace.search.text
    blurCartographSearch()
    triggerSearchModal(q)
  true

proc executeCatalogMenuAction(itemId: string)  ## Defined after clipboard glue.

proc catalogMenuLayout(): menu_lib.MenuLayout =
  let cellH = if rend != nil and rend.chromeAtlas != nil: rend.chromeAtlas.cellHeight else: 16
  let cellW = if rend != nil and rend.chromeAtlas != nil: rend.chromeAtlas.cellWidth else: 8
  menu_lib.computeMenuLayout(
    catalogMenuAnchorX, catalogMenuAnchorY, winWidth, winHeight,
    catalogMenu.items, cellW, menu_lib.defaultMenuMetrics(cellH))

proc dismissCatalogMenu() =
  if catalogMenuOpen:
    catalogMenuOpen = false
    catalogMenu.highlighted = -1
    markCartographDirty(cartographWorkspace)

proc openCatalogMenuAt(x, y: int): bool =
  ## Open the catalog context menu when the pointer is over a widget row.
  if surfaceStack.active != asWorkspace or overlay_lib.overlayCapturesInput(overlayStack):
    return false
  let idx = catalogEntryIndexAt(x, y)
  if idx < 0:
    return false
  selectCartographEntry(cartographWorkspace, idx, catalogListLayout().visibleRows)
  catalogMenuAnchorX = x
  catalogMenuAnchorY = y
  catalogMenuOpen = true
  catalogMenu.highlighted = -1
  blurCartographSearch()
  markCartographDirty(cartographWorkspace)
  true

proc handleCatalogMenuClick(x, y: int): bool =
  ## Route a left click while the menu is open: run the row action or dismiss.
  if not catalogMenuOpen:
    return false
  let layout = catalogMenuLayout()
  let row = menu_lib.menuRowAt(layout, catalogMenu.items, x, y)
  let itemId = if row >= 0: catalogMenu.items[row].id else: ""
  dismissCatalogMenu()
  if itemId.len > 0:
    executeCatalogMenuAction(itemId)
  true

proc updateCatalogMenuHover(x, y: int) =
  if not catalogMenuOpen:
    return
  let layout = catalogMenuLayout()
  let prev = catalogMenu.highlighted
  catalogMenu.highlightAt(layout, x, y)
  if catalogMenu.highlighted != prev:
    markCartographDirty(cartographWorkspace)

proc catalogScrollMetrics(): scrollbar_lib.ScrollMetrics =
  let layout = catalogListLayout()
  let stride = max(1, layout.stride)
  scrollbar_lib.scrollMetrics(
    contentSize = cartographWorkspace.visibleEntries.len * stride,
    viewportSize = layout.visibleRows * stride,
    offset = cartographWorkspace.catalogScrollRow * stride)

proc catalogScrollbarTrack(): scrollbar_lib.ScrollbarTrack =
  let regions = cartographRegions()
  let layout = catalogListLayout()
  scrollbar_lib.ScrollbarTrack(
    x: regions.catalog.x + regions.catalog.w - CatalogScrollbarWidth - 2,
    y: layout.listY,
    w: CatalogScrollbarWidth,
    h: max(0, layout.visibleRows * max(1, layout.stride)))

proc setCatalogScrollFromOffset(offset: int) =
  let layout = catalogListLayout()
  let stride = max(1, layout.stride)
  let row = offset div stride
  cartographWorkspace.catalogScrollRow =
    max(0, min(row, catalogScrollMax(cartographWorkspace, layout.visibleRows)))
  markCartographDirty(cartographWorkspace)

proc updateCatalogScrollDrag(y: int) =
  if not catalogScrollDrag.active:
    return
  let m = catalogScrollMetrics()
  let track = catalogScrollbarTrack()
  setCatalogScrollFromOffset(scrollbar_lib.offsetForDrag(catalogScrollDrag, track, m, y))

proc handleCartographPointer(x, y: int; down: bool): bool =
  if surfaceStack.active != asWorkspace:
    return false
  if handleOverlayPointer(x, y, down):
    return true
  if not down:
    return false
  let layout = catalogListLayout()
  if layout.scrollable:
    if layout.showScrollUp and pointInCatalogScrollArea(x, y, layout.scrollUp):
      scrollCartographCatalog(cartographWorkspace, -1, layout.visibleRows)
      return true
    if layout.showScrollDown and pointInCatalogScrollArea(x, y, layout.scrollDown):
      scrollCartographCatalog(cartographWorkspace, 1, layout.visibleRows)
      return true
  let regions = cartographRegions()
  if y >= regions.center.y and y < regions.center.y + CartographActionBarHeight and
      x >= regions.center.x and x < regions.center.x + regions.center.w:
    focusCartographSearch()
    return true
  ## Any click outside the search bar returns keyboard control to the terminal.
  blurCartographSearch()
  let inspectBtn = activeCatalogInspectButtonRect()
  if overlay_lib.pointInOverlayRect(inspectBtn, x, y):
    showInspectExplorer()
    return true
  let entryIdx = catalogEntryIndexAt(x, y)
  if entryIdx >= 0:
    selectCartographEntry(cartographWorkspace, entryIdx, catalogListLayout().visibleRows)
    return true
  if pointInRect(x, y, contentRect()):
    return false
  x >= regions.catalog.x and x < regions.catalog.x + regions.catalog.w

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
    if newIdx >= 0: workspaces[wi].sessions[newIdx].terminal.damage.markAll()
    discard refreshWorkspaceTabLabel(wi)
  workspaces[wi].sessionByPane(hit.get())

proc focusPaneAt(x, y: int, changed: var bool): ptr TerminalSession =
  let wi = activeWorkspaceIndex()
  if wi < 0: return nil
  let previous = workspaces[wi].panes.active
  result = focusPaneAt(x, y)
  changed = result != nil and previous != workspaces[wi].panes.active

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
  var displayWidth = 0
  var displayHeight = 0
  when defined(waymarkSdl3):
    let display = sdl.getPrimaryDisplay()
    if display == 0:
      return
    var rect: sdl.Rect
    if not sdl.getDisplayUsableBounds(display, rect):
      return
    displayWidth = int(rect.w)
    displayHeight = int(rect.h)
  else:
    let monitor = getPrimaryMonitor()
    if monitor == nil:
      return
    let mode = getVideoMode(monitor)
    if mode == nil:
      return
    displayWidth = int(mode.width)
    displayHeight = int(mode.height)
  let maxWidth = max(MinWindowWidth, int(float(displayWidth) * 0.92))
  let maxHeight = max(MinWindowHeight, int(float(displayHeight) * 0.86))
  winWidth = min(DefaultWindowWidth, maxWidth)
  winHeight = min(DefaultWindowHeight, maxHeight)

proc refreshTabCwdLabels(): bool =
  for wi in 0 ..< workspaces.len:
    if refreshWorkspaceTabLabel(wi):
      result = true

proc activeSessionCwd(fallback = ""): string =
  let workspace = activeWorkspace()
  if workspace == nil:
    return if fallback.len > 0: fallback else: config.startDirectory
  let idx = workspace[].activeSessionIndex()
  if idx < 0:
    return if fallback.len > 0: fallback else: config.startDirectory
  when not defined(windows):
    let liveCwd = processCwd(workspace[].sessions[idx].terminal.host.pid)
    if liveCwd.isSome:
      workspace[].sessions[idx].cwd = liveCwd.get()
      return liveCwd.get()
  let cached = workspace[].sessions[idx].cwd
  if cached.len > 0:
    cached
  elif fallback.len > 0:
    fallback
  else:
    config.startDirectory

proc refreshCatalogForActiveCwd(force = false): bool =
  if surfaceStack.active != asWorkspace:
    return false
  let now = epochTime()
  if not force and (now - lastCatalogPollTime) < catalogPollIntervalSec():
    return false
  if not force:
    lastCatalogPollTime = now
  let cwd = pollActiveShellCwd()
  if not force and cwd.len > 0 and cwd == lastCatalogScanCwd and
      catalogRootPath.len > 0 and dirExists(catalogRootPath) and
      cartographWorkspace.catalog.entries.len > 0:
    return false
  if cwd.len > 0:
    lastCatalogScanCwd = cwd
  let candidate = resolveCatalogRoot(if cwd.len > 0: cwd else: lastCatalogScanCwd)
  if not force and candidate == catalogRootPath and dirExists(candidate):
    return false
  catalogRootPath = candidate
  refreshCartographCatalog(cartographWorkspace, catalogRootPath)
  clampCartographCatalogScroll(cartographWorkspace, catalogListLayout().visibleRows)
  true

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
  if paramCount() > 0:
    let dir = paramStr(1)
    if dirExists(dir):
      return validSessionCwd(dir)
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
      if item.id == workspace.panes.active and not workspace.sessions[idx].terminal.viewport.userHeld:
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
    shortcutPreset = config.shortcutPreset,
  )
  term.screen.altScrollbackEnabled = altScrollbackEnabled(config.altScreenScrollback)
  applyConfiguredTheme(term)

  var session = TerminalSession(
    id: paneId,
    terminal: term,
    cwd: sessionCwd,
    title: newTitleState(tpPreferTitle)
  )
  discard session.title.updateCwd(sessionCwd)

  let sessPtr = addr session # Be careful with closures in loops if this were a loop
  term.onTitleChanged = proc(title: string) =
    # Note: This closure captures sessPtr which is stable inside TerminalSession seq if not reallocated
    # Actually, it's safer to use the workspace-level update since we refresh periodically anyway.
    # We'll just store it in the terminal for now.
    discard

  session

proc addTerminalTab() =
  let cwd =
    if workspaces.len == 0:
      startupSessionCwd()
    else:
      validSessionCwd(activeSessionCwd())
  let label = title_resolver_lib.cwdLabel(cwd)
  let id = tabs.addTab(label)
  var workspace = TerminalWorkspace(id: id, panes: pane_tree.newSplitPaneTree(), sessions: @[])
  workspace.sessions.add newSession(workspace.panes.active, contentRect(), cwd)
  workspaces.add workspace
  resizeTerminals()

proc activateTabNumber(number: int): bool =
  let idx = number - 1
  if idx < 0 or idx >= tabs.tabs.len:
    return false
  result = tabs.activate(tabs.tabs[idx].id)
  if result:
    let term = activeTerm()
    if term != nil:
      term.damage.markAll()

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
  var workspaceIdx = -1
  for i, workspace in workspaces:
    if workspace.id == id:
      workspaceIdx = i
      break
  if workspaceIdx < 0: return
  if workspaces.len <= 1:
    window_relay_lib.requestClose(windowRelays)
    return
  for session in workspaces[workspaceIdx].sessions:
    session.terminal.close()
  workspaces.delete(workspaceIdx)
  discard tabs.close(id)
  let term = activeTerm()
  if term != nil: term.damage.markAll()

proc closeActivePaneOrTab() =
  let workspace = activeWorkspace()
  if workspace == nil: return
  if workspace[].sessions.len > 1:
    closeActivePane()
  elif workspaces.len > 1 and tabs.activeId.isSome:
    removeTerminalTab(tabs.activeId.get())

proc inTitleBar(y: int): bool =
  y >= 0 and y < titleBarHeight

proc inTabBar(y: int): bool =
  surfaceStack.active == asPrimary and y >= titleBarHeight and y < chromeHeaderHeight()

proc localCol(area: PaneRect, x: cdouble): int =
  max(0, (int(x) - area.x) div rend.atlas.cellWidth)

proc localRow(area: PaneRect, y: cdouble): int =
  max(0, (int(y) - area.y) div rend.atlas.cellHeight)

proc rawLocalRow(area: PaneRect, y: cdouble): int =
  (int(y) - area.y) div rend.atlas.cellHeight

proc activeWorkspaceDirty(): bool =
  let wi = activeWorkspaceIndex()
  if wi < 0: return false
  for session in workspaces[wi].sessions:
    if session.terminal.damage.anyDirty: return true
  false

func toRenderColor(c: PaletteColor): render_relay_lib.RenderColor =
  render_relay_lib.rgba8(c.r, c.g, c.b)

func toOpenGlFilter(value: gpu_relay_lib.GpuTextureFilter): opengl_gpu_driver_lib.TextureFilter =
  case value
  of gpu_relay_lib.gtfNearest: opengl_gpu_driver_lib.tfNearest
  of gpu_relay_lib.gtfLinear: opengl_gpu_driver_lib.tfLinear

func toOpenGlWrap(value: gpu_relay_lib.GpuTextureWrap): opengl_gpu_driver_lib.TextureWrap =
  case value
  of gpu_relay_lib.gtwClampToEdge: opengl_gpu_driver_lib.twClampToEdge
  of gpu_relay_lib.gtwRepeat: opengl_gpu_driver_lib.twRepeat

func toOpenGlOptions(options: gpu_relay_lib.GpuTextureOptions): opengl_gpu_driver_lib.TextureOptions =
  opengl_gpu_driver_lib.TextureOptions(
    minFilter: options.minFilter.toOpenGlFilter,
    magFilter: options.magFilter.toOpenGlFilter,
    wrapS: options.wrapS.toOpenGlWrap,
    wrapT: options.wrapT.toOpenGlWrap,
  )

proc installOpenGlGpuRelays() =
  glTriangleDriver = opengl_gpu_driver_lib.newOpenGlTriangleDriver()
  gpuRelays = gpu_relay_lib.GpuRelays(
    createTextureProc: proc (): gpu_relay_lib.GpuTextureId =
      gpu_relay_lib.textureId(opengl_gpu_driver_lib.createTexture()),
    deleteTextureProc: proc (id: gpu_relay_lib.GpuTextureId) =
      opengl_gpu_driver_lib.deleteTexture(gpu_relay_lib.uint32Value(id)),
    configureTextureProc: proc (id: gpu_relay_lib.GpuTextureId; options: gpu_relay_lib.GpuTextureOptions) =
      opengl_gpu_driver_lib.configureTexture(gpu_relay_lib.uint32Value(id), options.toOpenGlOptions),
    uploadRgba8TextureProc: proc (id: gpu_relay_lib.GpuTextureId; width, height: int; pixels: pointer) =
      opengl_gpu_driver_lib.uploadRgba8Texture(gpu_relay_lib.uint32Value(id), width, height, pixels),
    drawTexturedTrianglesProc: proc (textureId: gpu_relay_lib.GpuTextureId; vertices: openArray[gpu_relay_lib.GpuVertex]) =
      glVertexScratch.setLen(vertices.len)
      for i, vertex in vertices:
        glVertexScratch[i] = opengl_gpu_driver_lib.TexturedVertex(
          x: vertex.x,
          y: vertex.y,
          u: vertex.u,
          v: vertex.v,
          r: vertex.r,
          g: vertex.g,
          b: vertex.b,
          a: vertex.a,
        )
      opengl_gpu_driver_lib.drawTexturedTriangles(glTriangleDriver, gpu_relay_lib.uint32Value(textureId), glVertexScratch),
    enableAlphaBlendingProc: proc () =
      opengl_gpu_driver_lib.enableAlphaTexturing(),
    flushProc: proc () =
      opengl_gpu_driver_lib.flush(),
  )

proc disposeOpenGlGpuRelays() =
  if glTriangleDriver != nil:
    opengl_gpu_driver_lib.dispose(glTriangleDriver)
    glTriangleDriver = nil

when not defined(waymarkSdl3):
  proc installGlfwWindowRelays() =
    windowRelays = window_relay_lib.WindowRelays(
      geometry: window_relay_lib.WindowGeometryRelays(
        getPosition: proc (): window_relay_lib.WindowPoint =
          if window == nil:
            return window_relay_lib.point(0, 0)
          var x, y: cint
          getWindowPos(window, addr x, addr y)
          window_relay_lib.point(int(x), int(y)),
        setPosition: proc (point: window_relay_lib.WindowPoint) =
          if window != nil:
            setWindowPos(window, cint(point.x), cint(point.y)),
        getWindowSize: proc (): window_relay_lib.WindowSize =
          if window == nil:
            return window_relay_lib.size2d(0, 0)
          var width, height: cint
          getWindowSize(window, addr width, addr height)
          window_relay_lib.size2d(int(width), int(height)),
        getDrawableSize: proc (): window_relay_lib.WindowSize =
          if window == nil:
            return window_relay_lib.size2d(0, 0)
          var width, height: cint
          getFramebufferSize(window, addr width, addr height)
          window_relay_lib.size2d(int(width), int(height)),
        setMinimumSize: proc (size: window_relay_lib.WindowSize) =
          if window != nil:
            setWindowSizeLimits(window, cint(size.width), cint(size.height), DONT_CARE, DONT_CARE),
      ),
      input: window_relay_lib.WindowInputRelays(
        isMouseButtonDown: proc (button: window_relay_lib.MouseButton): bool =
          if window == nil:
            return false
          let glfwButton =
            case button
            of window_relay_lib.mbLeft: MOUSE_BUTTON_LEFT
            of window_relay_lib.mbMiddle: MOUSE_BUTTON_MIDDLE
            of window_relay_lib.mbRight: MOUSE_BUTTON_RIGHT
          getMouseButton(window, cint(glfwButton)) == PRESS,
      ),
      lifecycle: window_relay_lib.WindowLifecycleRelays(
        shouldClose: proc (): bool =
          window != nil and windowShouldClose(window) != 0,
        requestClose: proc () =
          if window != nil:
            setWindowShouldClose(window, 1),
      )
    )

  proc installGlfwRenderRelays() =
    frameRelays = render_relay_lib.RenderRelays(
      frame: render_relay_lib.RenderFrameRelays(
        setViewport: proc (size: render_relay_lib.RenderSize) =
          glViewport(0, 0, cint(size.width), cint(size.height)),
        clear: proc (color: render_relay_lib.RenderColor) =
          glClearColor(color.r, color.g, color.b, color.a)
          glClear(GL_COLOR_BUFFER_BIT),
        flush: proc () =
          glFlush(),
        present: proc () =
          if window != nil:
            swapBuffers(window),
      )
    )

when defined(waymarkSdl3):
  proc installSdlWindowRelays() =
    windowRelays = window_relay_lib.WindowRelays(
      geometry: window_relay_lib.WindowGeometryRelays(
        getPosition: proc (): window_relay_lib.WindowPoint =
          if window == nil:
            return window_relay_lib.point(0, 0)
          var x, y: cint
          discard sdl.getWindowPosition(window, x, y)
          window_relay_lib.point(int(x), int(y)),
        setPosition: proc (point: window_relay_lib.WindowPoint) =
          if window != nil:
            discard sdl.setWindowPosition(window, cint(point.x), cint(point.y)),
        getWindowSize: proc (): window_relay_lib.WindowSize =
          if window == nil:
            return window_relay_lib.size2d(0, 0)
          var width, height: cint
          discard sdl.getWindowSize(window, width, height)
          window_relay_lib.size2d(int(width), int(height)),
        getDrawableSize: proc (): window_relay_lib.WindowSize =
          if window == nil:
            return window_relay_lib.size2d(0, 0)
          var width, height: cint
          discard sdl.getWindowSizeInPixels(window, width, height)
          window_relay_lib.size2d(int(width), int(height)),
        setMinimumSize: proc (size: window_relay_lib.WindowSize) =
          if window != nil:
            discard sdl.setWindowMinimumSize(window, cint(size.width), cint(size.height)),
      ),
      input: window_relay_lib.WindowInputRelays(
        isMouseButtonDown: proc (button: window_relay_lib.MouseButton): bool =
          let mask =
            case button
            of window_relay_lib.mbLeft: sdl.BUTTON_LMASK
            of window_relay_lib.mbMiddle: sdl.BUTTON_MMASK
            of window_relay_lib.mbRight: sdl.BUTTON_RMASK
          var x, y: cfloat
          (sdl.getMouseState(x, y) and uint32(mask)) != 0'u32,
      ),
      lifecycle: window_relay_lib.WindowLifecycleRelays(
        shouldClose: proc (): bool =
          appShouldClose,
        requestClose: proc () =
          appShouldClose = true,
      )
    )

  proc installSdlRenderRelays() =
    frameRelays = render_relay_lib.RenderRelays(
      frame: render_relay_lib.RenderFrameRelays(
        setViewport: proc (size: render_relay_lib.RenderSize) =
          glViewport(0, 0, cint(size.width), cint(size.height)),
        clear: proc (color: render_relay_lib.RenderColor) =
          glClearColor(color.r, color.g, color.b, color.a)
          glClear(GL_COLOR_BUFFER_BIT),
        flush: proc () =
          glFlush(),
        present: proc () =
          if window != nil:
            discard sdl.gL_SwapWindow(window),
      )
    )

proc drawCartographMode() =
  let wi = activeWorkspaceIndex()
  if wi < 0: return
  let activeIdx = workspaces[wi].activeSessionIndex()
  if activeIdx < 0: return
  clampCartographCatalogScroll(cartographWorkspace, catalogListLayout().visibleRows)
  let regions = cartographRegions()
  let bg = workspaces[wi].sessions[activeIdx].terminal.screen.theme.background
  render_relay_lib.beginFrame(frameRelays, render_relay_lib.size2d(winWidth, winHeight), toRenderColor(bg))
  let searchCellW =
    if rend != nil and rend.chromeAtlas != nil: max(1, rend.chromeAtlas.cellWidth)
    else: 8
  let searchCols = max(1, (regions.center.w - CartographRailPad * 2) div searchCellW)
  let searchView = cartographWorkspace.search.viewport(searchCols)
  let searchFocusedNow = cartographFocus.isFocused("search")
  let sbMetrics = catalogScrollMetrics()
  let sbVisible = scrollbar_lib.scrollbarVisible(sbMetrics)
  let sbTrack = catalogScrollbarTrack()
  let sbThumb =
    if sbVisible: scrollbar_lib.computeThumb(sbTrack, sbMetrics)
    else: scrollbar_lib.ScrollbarThumb()
  rend.drawCartographShell(
    winWidth,
    winHeight,
    regions,
    displayCatalog(cartographWorkspace),
    cartographWorkspace.selectedIndex,
    cartographWorkspace.catalogScrollRow,
    CartographActionBarHeight,
    cartographCatalogFooterHeight(),
    searchView.text,
    (if searchFocusedNow: searchView.caretCol else: -1),
    searchFocusedNow,
    false,
    sbTrack,
    sbThumb,
  )
  let termArea = contentRect()
  let layouts = workspaces[wi].panes.layouts(termArea)
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
  if catalogMenuOpen:
    rend.drawContextMenu(winWidth, winHeight, catalogMenuLayout(), catalogMenu.items, catalogMenu.highlighted)
  block toasts:
    let now = epochTime()
    toast_lib.prune(appToasts, now)
    let visible = toast_lib.visibleToasts(appToasts, now)
    if visible.len > 0:
      rend.drawToasts(winWidth, winHeight, visible, now)
  clearCartographDirty(cartographWorkspace)

proc drawActiveWorkspace() =
  let wi = activeWorkspaceIndex()
  if wi < 0: return
  let activeIdx = workspaces[wi].activeSessionIndex()
  if activeIdx < 0: return
  let bg = workspaces[wi].sessions[activeIdx].terminal.screen.theme.background
  render_relay_lib.beginFrame(frameRelays, render_relay_lib.size2d(winWidth, winHeight), toRenderColor(bg))
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

proc pumpTerminalSessions(): int =
  checkSearchProcess()
  var n = 0
  for workspace in workspaces.mitems:
    for session in workspace.sessions:
      let readCount = session.terminal.step()
      if readCount > 0:
        session.terminal.refreshViewport(stickToBottom = true)
      n += readCount
  n

proc toggleSurface() =
  if surfaceStack.active == asPrimary:
    switchSurface(surfaceStack, asWorkspace)
  else:
    while overlay_lib.overlayCapturesInput(overlayStack):
      dismissTopOverlay()
    switchSurface(surfaceStack, asPrimary)
  ## Leave the terminal in charge of the keyboard whenever surfaces switch.
  cartographFocus.clearFocus()
  dismissCatalogMenu()
  persistActiveSurface()
  markCartographDirty(cartographWorkspace)
  resizeTerminals()
  let term = activeTerm()
  if term != nil:
    term.damage.markAll()

proc installAppSurfaces() =
  var initial = asPrimary
  let envSurface = getEnv("WAYMARK_SURFACE", "").strip()
  if envSurface.len > 0:
    initial = parseAppSurfaceId(envSurface)
  elif fileExists(ConfigPath):
    try:
      let dict = loadConfig(ConfigPath)
      initial = parseAppSurfaceId(dict.getSectionValue("surface", "default", "primary"))
    except CatchableError:
      discard
  surfaceStack = newAppSurfaceStack(asPrimary)
  cartographWorkspace = newCartographWorkspace()
  catalogRootPath = resolveCatalogRoot(pollActiveShellCwd())
  lastCatalogScanCwd = pollActiveShellCwd()
  refreshCartographCatalog(cartographWorkspace, catalogRootPath)
  surfaceStack.registerSurface(SurfaceRelays(
    id: asPrimary,
    label: "Terminal",
    tick: proc (): int =
      pumpTerminalSessions(),
    draw: proc () =
      drawActiveWorkspace(),
    needsRedraw: proc (): bool =
      activeWorkspaceDirty(),
  ))
  surfaceStack.registerSurface(SurfaceRelays(
    id: asWorkspace,
    label: "Cartograph",
    activate: proc () =
      discard refreshCatalogForActiveCwd(force = true)
      markCartographDirty(cartographWorkspace)
      resizeTerminals()
      let term = activeTerm()
      if term != nil:
        term.damage.markAll(),
    tick: proc (): int =
      pumpTerminalSessions(),
    draw: proc () =
      drawCartographMode(),
    needsRedraw: proc (): bool =
      cartographNeedsRedraw(cartographWorkspace) or activeWorkspaceDirty(),
  ))
  if initial == asWorkspace:
    switchSurface(surfaceStack, asWorkspace)

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
  rend = newGpuTerminalRenderer(atlas, chromeAtlas, gpuRelays)
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
    lines.add "using_alt=" & $term.screen.usingAlt
    lines.add "scroll_region=" & $term.screen.scrollTop & "," & $term.screen.scrollBottom
    lines.add "total_rows=" & $term.screen.totalRows & " viewport_max_scroll=" & $term.viewport.maxScroll
    lines.add "viewport_scroll_offset=" & $term.viewport.scrollOffset &
      " viewport_top=" & $term.viewport.viewportToBuffer(0) &
      " viewport_bottom=" & $term.viewport.viewportToBuffer(term.viewport.height - 1)
    let mode = term.inputMode.snapshot(term.screen.usingAlt)
    lines.add "input_mouse_mode=" & $mode.mouseMode
    lines.add "input_sgr_mouse=" & $mode.sgrMouse
    lines.add "input_alternate_scroll=" & $mode.alternateScroll
    lines.add "input_bracketed_paste=" & $mode.bracketedPaste
    lines.add "input_focus_reporting=" & $mode.focusReporting
    lines.add "input_cursor_app=" & $mode.cursorApp
    lines.add "input_scroll_kind=" & $mode.scrollInputKind
    lines.add "normal_tui_likely=" & $(
      (not term.screen.usingAlt) and
      mode.mouseMode == mmNone and
      (mode.cursorApp or mode.focusReporting)
    )

    proc colorName(c: screen_buffer_lib.Color): string =
      case c.kind
      of ckDefault:
        "default"
      of ckIndexed:
        "idx" & $c.index
      of ckRgb:
        "#" & c.r.toHex(2) & c.g.toHex(2) & c.b.toHex(2)

    proc attrName(attrs: screen_buffer_lib.Attrs): string =
      var parts: seq[string] = @[]
      if attrs.fg.kind != ckDefault: parts.add "fg=" & colorName(attrs.fg)
      if attrs.bg.kind != ckDefault: parts.add "bg=" & colorName(attrs.bg)
      if attrs.flags.len > 0: parts.add "flags=" & $attrs.flags
      if attrs.underlineStyle != usNone: parts.add "underline=" & $attrs.underlineStyle
      if parts.len == 0: "default" else: parts.join(",")

    proc rowAttrRuns(row: int): string =
      if row < 0 or row >= term.screen.rows: return ""
      var runs: seq[string] = @[]
      var start = 0
      var last = attrName(term.screen.cellAt(row, 0).attrs)
      for col in 1 ..< term.screen.cols:
        let attrs = attrName(term.screen.cellAt(row, col).attrs)
        if attrs != last:
          if last != "default":
            runs.add $start & "-" & $(col - 1) & ":" & last
          start = col
          last = attrs
      if last != "default":
        runs.add $start & "-" & $(term.screen.cols - 1) & ":" & last
      runs.join(" | ")

    lines.add "cursor_attrs=" & attrName(term.screen.cursor.attrs)

    var rowsToDump: seq[int] = @[]
    proc addDumpRow(row: int) =
      if row >= 0 and row < term.screen.rows and row notin rowsToDump:
        rowsToDump.add row

    for i in 0 ..< min(term.screen.rows, 20):
      addDumpRow(i)
    for i in term.screen.cursor.row - 4 .. term.screen.cursor.row + 2:
      addDumpRow(i)
    for i in max(0, term.screen.rows - 8) ..< term.screen.rows:
      addDumpRow(i)

    rowsToDump.sort()
    for i in rowsToDump:
      lines.add $i & ": " & term.screen.lineText(i)
      let attrs = rowAttrRuns(i)
      if attrs.len > 0:
        lines.add $i & " attrs: " & attrs
    writeFile(screenSnapshotPath, lines.join("\n"))
  except CatchableError:
    discard

func toProviderResult(value: system_clipboard_lib.ClipboardResult): clipboard_provider_lib.ClipboardResult =
  case value.status
  of system_clipboard_lib.csSuccess:
    clipboard_provider_lib.clipboardSuccess(value.backend)
  of system_clipboard_lib.csNoBackend:
    clipboard_provider_lib.clipboardUnavailable(value.backend, value.message)
  of system_clipboard_lib.csCommandFailed:
    clipboard_provider_lib.clipboardFailed(value.backend, value.message)

func toProviderTextResult(value: system_clipboard_lib.ClipboardTextResult): clipboard_provider_lib.ClipboardTextResult =
  case value.status
  of system_clipboard_lib.csSuccess:
    clipboard_provider_lib.clipboardTextSuccess(value.backend, value.text)
  of system_clipboard_lib.csNoBackend:
    clipboard_provider_lib.clipboardTextUnavailable(value.backend, value.message)
  of system_clipboard_lib.csCommandFailed:
    clipboard_provider_lib.clipboardTextFailed(value.backend, value.message)

proc nativeClipboardProvider(): clipboard_provider_lib.ClipboardProvider =
  when defined(waymarkSdl3):
    clipboard_provider_lib.provider(
      "sdl3",
      proc (): clipboard_provider_lib.ClipboardTextResult =
        let text = sdl.getClipboardText()
        if text == nil:
          return clipboard_provider_lib.clipboardTextUnavailable("sdl3", $sdl.getError())
        result = clipboard_provider_lib.clipboardTextSuccess("sdl3", $text)
        sdl.sdlFree(text),
      proc (text: string): clipboard_provider_lib.ClipboardResult =
        if sdl.setClipboardText(cstring(text)):
          clipboard_provider_lib.clipboardSuccess("sdl3")
        else:
          clipboard_provider_lib.clipboardFailed("sdl3", $sdl.getError()),
    )
  else:
    clipboard_provider_lib.provider(
      "glfw",
      proc (): clipboard_provider_lib.ClipboardTextResult =
        if window == nil:
          return clipboard_provider_lib.clipboardTextUnavailable("glfw", "window is not available")
        let text = window.getClipboardString()
        if text == nil:
          clipboard_provider_lib.clipboardTextUnavailable("glfw", "clipboard text is not available")
        else:
          clipboard_provider_lib.clipboardTextSuccess("glfw", $text),
      proc (text: string): clipboard_provider_lib.ClipboardResult =
        if window == nil:
          return clipboard_provider_lib.clipboardUnavailable("glfw", "window is not available")
        window.setClipboardString(cstring(text))
        clipboard_provider_lib.clipboardSuccess("glfw"),
    )

proc systemClipboardProvider(): clipboard_provider_lib.ClipboardProvider =
  clipboard_provider_lib.provider(
    "system-command",
    proc (): clipboard_provider_lib.ClipboardTextResult =
      system_clipboard_lib.pasteText().toProviderTextResult,
    proc (text: string): clipboard_provider_lib.ClipboardResult =
      system_clipboard_lib.copyText(text).toProviderResult,
  )

proc installClipboardProviders() =
  clipboardProviders = @[nativeClipboardProvider(), systemClipboardProvider()]

proc copyToClipboard(text: string) =
  discard clipboard_provider_lib.writeText(clipboardProviders, text, clipboardPolicy)

proc pushToast(text: string) =
  appToasts.push(text, epochTime())
  markCartographDirty(cartographWorkspace)

proc executeCatalogMenuAction(itemId: string) =
  let entry = selectedCartographEntry(cartographWorkspace)
  case itemId
  of "inspect":
    showInspectExplorer()
  of "copy-id":
    if entry.id.len > 0:
      copyToClipboard(entry.id)
      pushToast("Copied " & entry.id)
  else:
    discard

proc pasteFromClipboard(): string =
  let text = clipboard_provider_lib.readText(clipboardProviders, clipboardPolicy)
  if clipboard_provider_lib.success(text):
    text.text
  else:
    ""

proc handleShortcutAction(term: Terminal; action: string): bool =
  result = true
  case action
  of "copy":
    if term.selection.isActive:
      let text = term.selection.extractText(term.screen.cols) do (r: int) -> seq[CellData]:
        let row = term.screen.absoluteRowAt(r)
        var res = newSeq[CellData](row.len)
        for i, c in row: res[i] = CellData(rune: c.rune, width: int(c.width))
        res
      copyToClipboard(text)
  of "paste":
    let text = pasteFromClipboard()
    if text.len > 0:
      discard term.sendPaste(text)
  of "close-tab":
    if tabs.activeId.isSome:
      removeTerminalTab(tabs.activeId.get())
  of "switch-surface":
    toggleSurface()
  of "zoom-in":
    fontSize += 1.0
    rebuildAtlas()
  of "zoom-out":
    fontSize = max(4.0, fontSize - 1.0)
    rebuildAtlas()
  else:
    if action.startsWith("tab-"):
      try:
        discard activateTabNumber(parseInt(action[4 .. ^1]))
      except ValueError:
        discard
    else:
      result = false

proc closeAllWorkspaces() =
  for workspace in workspaces:
    for session in workspace.sessions:
      session.terminal.close()
  workspaces.setLen(0)
  tabs = newTabSet()

proc renderOnce() =
  surfaceStack.drawActive()
  rend.drawChrome(tabs, winWidth, winHeight, titleBarHeight, tabBarHeight, surfaceStack.active, config.title)
  render_relay_lib.endFrame(frameRelays)
  writeGpuSnapshot()
  let term = activeTerm()
  if term != nil:
    writeScreenSnapshot(term)

when defined(waymarkSdl3):
  proc pollEvents()

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
      render_relay_lib.setViewport(frameRelays, render_relay_lib.size2d(winWidth, winHeight))
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
# Platform Callbacks and Events
# ---------------------------------------------------------------------------

when not defined(waymarkSdl3):
  proc onChar(win: Window, codepoint: cuint) {.cdecl.} =
    if overlay_lib.overlayCapturesInput(overlayStack) and surfaceStack.active == asWorkspace: return
    if keyTextFallback: return
    if searchInputActive():
      searchInsertRune(Rune(codepoint.int32))
      return
    let term = activeTerm()
    if term == nil: return
    let sent = term.sendKey(keyChar(uint32(codepoint)))
    if inputDebug: echo "[input] char codepoint=", codepoint, " queued=", sent
    term.damage.markAll()

  proc onKey(win: Window, key, scancode, action, mods: cint) {.cdecl.} =
    if action == PRESS and key == KEY_ESCAPE and catalogMenuOpen:
      dismissCatalogMenu()
      return
    if action == PRESS and key == KEY_ESCAPE and handleOverlayEscape():
      return
    if overlay_lib.overlayCapturesInput(overlayStack) and surfaceStack.active == asWorkspace and
        (action == PRESS or action == REPEAT):
      return
    if action == PRESS or action == REPEAT:
      let m = castSet(mods)
      if terminal.modCtrl in m and terminal.modShift in m and key == KEY_A:
        toggleSurface()
        return
    if (action == PRESS or action == REPEAT) and searchInputActive():
      let m = castSet(mods)
      case key
      of KEY_ESCAPE: blurCartographSearch(); return
      of KEY_BACKSPACE: discard handleSearchEditKey(sekBackspace); return
      of KEY_DELETE: discard handleSearchEditKey(sekDelete); return
      of KEY_LEFT: discard handleSearchEditKey(sekLeft); return
      of KEY_RIGHT: discard handleSearchEditKey(sekRight); return
      of KEY_HOME: discard handleSearchEditKey(sekHome); return
      of KEY_END: discard handleSearchEditKey(sekEnd); return
      of KEY_ENTER, KEY_KP_ENTER: discard handleSearchEditKey(sekEnter); return
      else:
        if keyTextFallback:
          let ch = toPrintableRune(key, mods)
          if ch.isSome:
            searchInsertRune(Rune(ch.get().int32))
            return
        ## Swallow other unmodified keys so typing never leaks to the terminal.
        if terminal.modCtrl notin m and terminal.modAlt notin m:
          return
    if action == PRESS or action == REPEAT:
      let term = activeTerm()
      if term == nil: return
      let m = castSet(mods)
      if inputDebug: echo "[input] key key=", key, " action=", action, " mods=", mods

      if terminal.modCtrl in m and terminal.modShift in m and key == KEY_T:
        addTerminalTab()
        return
      if terminal.modCtrl in m and terminal.modShift in m and key == KEY_N:
        let activeCwd = validSessionCwd(activeSessionCwd())
        try:
          discard startProcess(getAppFilename(), args = @[activeCwd], options = {poParentStreams})
        except CatchableError:
          discard
        return
      if terminal.modCtrl in m and terminal.modShift in m and (key == KEY_ENTER or key == KEY_KP_ENTER):
        splitActivePane()
        return
      if terminal.modCtrl in m and terminal.modShift in m and key == KEY_W:
        closeActivePaneOrTab()
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
      of KEY_ENTER, KEY_KP_ENTER: sk = shortcut_map_lib.kEnter
      else:
        if key >= 32 and key <= 126: sk = shortcut_map_lib.shortcutKey(char(key))
        else: sk = shortcut_map_lib.kNone

      # 2. Lookup high-level actions
      let actionName = term.shortcuts.lookup(sk, cast[set[shortcut_map_lib.Modifier]](m))
      if actionName.isSome:
        if handleShortcutAction(term, actionName.get()):
          return

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
    if button == MOUSE_BUTTON_LEFT and handleOverlayPointer(int(x), int(y), action == PRESS):
      return
    if catalogMenuOpen and button == MOUSE_BUTTON_LEFT and action == PRESS:
      if handleCatalogMenuClick(int(x), int(y)):
        return
    if button == MOUSE_BUTTON_RIGHT and action == PRESS:
      if openCatalogMenuAt(int(x), int(y)):
        return
    if button == MOUSE_BUTTON_LEFT and action == RELEASE:
      draggingWindow = false
      catalogScrollDrag.active = false

    if button == MOUSE_BUTTON_LEFT and action == PRESS and inTitleBar(int(y)):
      if surfaceToggleHitTest(int(x), int(y), winWidth, titleBarHeight):
        toggleSurface()
        return
      draggingWindow = true
      dragStartMouseX = x
      dragStartMouseY = y
      let pos = window_relay_lib.getPosition(windowRelays)
      dragStartWinX = cint(pos.x)
      dragStartWinY = cint(pos.y)
      dragStartGlobalX = float(pos.x) + x
      dragStartGlobalY = float(pos.y) + y
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

    if int(y) < chromeHeaderHeight(): return
    if handleCartographPointer(int(x), int(y), action == PRESS):
      return
    var paneFocusChanged = false
    let session = focusPaneAt(int(x), int(y), paneFocusChanged)
    if session == nil: return
    let term = session[].terminal
    # Swallow the pane-focus-acquiring click ONLY when the child isn't tracking
    # mouse. Mouse-aware apps (grok, vim) need that click forwarded too, else
    # their own click-to-focus (e.g. focusing a chat input) never fires.
    if paneFocusChanged and button == MOUSE_BUTTON_LEFT and action == PRESS and
       term.inputMode.shouldIntercept(castSet(mods)):
      return
    let area = activeSessionRect(session[].id)
    if area.isNone: return
    let col = localCol(area.get(), x); let row = localRow(area.get(), y)
    let bufferRow = term.viewport.viewportToBuffer(row)
    if bufferRow < 0: return
    if term.inputMode.shouldIntercept(castSet(mods)):
      if button == MOUSE_BUTTON_LEFT:
        let isDown = action == PRESS

        # Handle link clicking
        if not isDown and term.activeLink.isSome:
          launchUri(term.activeLink.get().link.text)
          return

        term.drag.update(row, col, isDown)
        if isDown:
          let wi = activeWorkspaceIndex()
          if wi >= 0: clearSelectionsExcept(workspaces[wi], session[].id)
          term.selection.start(point(bufferRow, col))
        term.damage.markAll()
    else:
      let tmb = toMouseButton(button).int
      if tmb != terminal.mbRelease.int: # skip only the unknown-button sentinel
        lastMouseReportRow = row; lastMouseReportCol = col
        discard term.sendMouse(mouse(if action == PRESS: mePress else: meRelease, cast[terminal.MouseButton](tmb), row, col, castSet(mods)))

  proc onCursorPos(win: Window, x, y: cdouble) {.cdecl.} =
    if draggingWindow:
      let pos = window_relay_lib.getPosition(windowRelays)
      let currentGlobalX = float(pos.x) + x
      let currentGlobalY = float(pos.y) + y
      window_relay_lib.setPosition(
        windowRelays,
        window_relay_lib.point(
          int(dragStartWinX + cint(currentGlobalX - dragStartGlobalX)),
          int(dragStartWinY + cint(currentGlobalY - dragStartGlobalY)),
        )
      )
      return
    if catalogScrollDrag.active:
      updateCatalogScrollDrag(int(y))
      return
    if catalogMenuOpen:
      updateCatalogMenuHover(int(x), int(y))

    let wi = activeWorkspaceIndex()
    if wi < 0: return
    let activeId = workspaces[wi].panes.active
    let sessionIdx = workspaces[wi].sessionIndex(activeId)
    if sessionIdx < 0: return
    let term = workspaces[wi].sessions[sessionIdx].terminal
    if int(y) < chromeHeaderHeight() and term.drag.state == dsIdle:
      if term.activeLink.isSome:
        term.activeLink = none(ActiveLink)
        term.damage.markAll()
      return
    let area = activeSessionRect(activeId)
    if area.isNone: return
    let col = localCol(area.get(), x)
    let row = localRow(area.get(), y)
    let rawRow = rawLocalRow(area.get(), y)

    if term.drag.state != dsIdle:
      let leftDown = window_relay_lib.isMouseButtonDown(windowRelays, window_relay_lib.mbLeft)
      term.drag.update(rawRow, col, leftDown)
      if term.drag.state == dsIdle:
        term.damage.markAll()
        return
      let delta = term.drag.autoscrollDelta()
      if delta < 0:
        term.viewport.scrollUp(1)
      elif delta > 0:
        term.viewport.scrollDown(1)
      term.refreshViewport(false)
      let focusRow = term.drag.focusViewportRow()
      let focusBufferRow = term.viewport.viewportToBuffer(focusRow)
      if focusBufferRow >= 0:
        term.selection.update(point(focusBufferRow, col))
      term.damage.markAll()
    else:
      let absRow = term.viewport.viewportToBuffer(row)
      if absRow < 0: return
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

      if not term.inputMode.shouldIntercept() and term.inputMode.trackingWantsMotion() and
         (row != lastMouseReportRow or col != lastMouseReportCol):
        # Only report motion on cell change (xterm behavior). Per-pixel reports
        # flood the child and turn a jittery click into press+drag+release,
        # which apps read as a selection rather than a focus click.
        lastMouseReportRow = row; lastMouseReportCol = col
        let leftDown = window_relay_lib.isMouseButtonDown(windowRelays, window_relay_lib.mbLeft)
        let kind =
          if leftDown and term.inputMode.trackingWantsDrag(): meDrag
          else: meMove
        # No button held during motion must report "no button" (param 35),
        # not a phantom left-drag. mbRelease encodes to the no-button code.
        let btn = if leftDown: terminal.mbLeft else: terminal.mbRelease
        discard term.sendMouse(mouse(kind, btn, row, col, castSet(0)))

  proc onScroll(win: Window, xoffset, yoffset: cdouble) {.cdecl.} =
    var x, y: cdouble; getCursorPos(win, addr x, addr y)
    if handleOverlayWheel(int(x), int(y), yoffset):
      return
    let session = if int(y) >= chromeHeaderHeight(): focusPaneAt(int(x), int(y)) else: nil
    let term = if session == nil: activeTerm() else: session[].terminal
    if term == nil: return
    let ctrlDown = (getKey(window, KEY_LEFT_CONTROL) == PRESS or getKey(window, KEY_RIGHT_CONTROL) == PRESS)
    let shiftDown = (getKey(window, KEY_LEFT_SHIFT) == PRESS or getKey(window, KEY_RIGHT_SHIFT) == PRESS)
    if ctrlDown:
      if yoffset > 0: fontSize += 1.0
      elif yoffset < 0: fontSize = max(4.0, fontSize - 1.0)
      rebuildAtlas()
    else:
      let scrollKind = term.inputMode.scrollInputKind(term.screen.usingAlt)
      let normalTuiLikely =
        (not term.screen.usingAlt) and
        term.inputMode.mouseMode == mmNone and
        (term.inputMode.cursorApp or term.inputMode.focusReporting)
      let action = decideWheelAction(ScrollPolicyInput(
        usingAltScreen: term.screen.usingAlt,
        childWantsWheel: term.inputMode.shouldSendWheel(term.screen.usingAlt),
        childWheelEncoding: toChildWheelEncoding(scrollKind),
        viewportHasHistory: term.viewport.maxScroll > 0,
        viewportHasMeaningfulHistory: term.viewport.hasMeaningfulHistory(config.meaningfulHistoryRows),
        viewportAtLiveEnd: term.viewport.isAtLiveEnd,
        scrollingTowardHistory: yoffset > 0,
        normalScreenTuiLikely: normalTuiLikely,
        forceTerminalScroll: shiftDown,
        forceChildScroll: false,
        altScrollbackMode: config.altScreenScrollback,
        altWheelPolicy: config.altWheelPolicy,
        normalWheelPolicy: config.normalWheelPolicy,
      ))
      case action
      of saScrollViewport:
        if yoffset > 0: term.viewport.scrollUp(3)
        elif yoffset < 0: term.viewport.scrollDown(3)
      of saRouteToChild:
        let paneId =
          if session == nil:
            let workspace = activeWorkspace()
            if workspace == nil: pane_tree.paneId(-1) else: workspace[].panes.active
          else:
            session[].id
        let area = activeSessionRect(paneId)
        let col = if area.isSome: localCol(area.get(), x) else: term.screen.cursor.col
        let row = if area.isSome: localRow(area.get(), y) else: term.screen.cursor.row
        case scrollKind
        of sikCursorKeys:
          let keyCode = if yoffset > 0: kArrowUp else: kArrowDown
          for _ in 0 ..< max(1, int(abs(yoffset) * 3)):
            discard term.sendKey(key(keyCode))
        of sikMouseWheel:
          let button = if yoffset > 0: mbWheelUp else: mbWheelDown
          for _ in 0 ..< max(1, int(abs(yoffset))):
            discard term.sendMouse(mouse(mePress, button, row, col))
        of sikNone:
          discard
      of saRouteMouseWheel:
        let paneId =
          if session == nil:
            let workspace = activeWorkspace()
            if workspace == nil: pane_tree.paneId(-1) else: workspace[].panes.active
          else:
            session[].id
        let area = activeSessionRect(paneId)
        let col = if area.isSome: localCol(area.get(), x) else: term.screen.cursor.col
        let row = if area.isSome: localRow(area.get(), y) else: term.screen.cursor.row
        let button = if yoffset > 0: mbWheelUp else: mbWheelDown
        for _ in 0 ..< max(1, int(abs(yoffset))):
          discard term.sendMouse(mouse(mePress, button, row, col))
      of saRouteCursorKeys:
        let keyCode = if yoffset > 0: kArrowUp else: kArrowDown
        for _ in 0 ..< max(1, int(abs(yoffset) * 3)):
          discard term.sendKey(key(keyCode))
      of saRoutePageKeys:
        let keyCode = if yoffset > 0: kPageUp else: kPageDown
        discard term.sendKey(key(keyCode))
      of saIgnore:
        discard
      term.refreshViewport(false)
    term.damage.markAll()

  proc onWindowFocus(win: Window, focused: cint) {.cdecl.} =
    let term = activeTerm()
    if term == nil: return
    discard term.sendFocus(focused != 0)

  proc resizeToFramebuffer(win: Window, fallbackWidth, fallbackHeight: cint) =
    let drawableSize = window_relay_lib.getDrawableSize(windowRelays)
    let currentWindowSize = window_relay_lib.getWindowSize(windowRelays)
    let report = chooseDrawableSize(
      framebuffer = size2d(drawableSize.width, drawableSize.height),
      window = size2d(currentWindowSize.width, currentWindowSize.height),
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
    render_relay_lib.setViewport(frameRelays, render_relay_lib.size2d(int(actualWidth), int(actualHeight)))
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
    let drawableSize = window_relay_lib.getDrawableSize(windowRelays)
    let currentWindowSize = window_relay_lib.getWindowSize(windowRelays)
    let report = chooseDrawableSize(
      framebuffer = size2d(drawableSize.width, drawableSize.height),
      window = size2d(currentWindowSize.width, currentWindowSize.height),
      fallback = size2d(0, 0),
    )
    if not report.chosen.isPositive:
      return false
    if not report.changedFrom(size2d(winWidth, winHeight)):
      return false
    resizeToFramebuffer(window, cint(report.chosen.width), cint(report.chosen.height))
    true

when defined(waymarkSdl3):
  func toTerminalMods(mods: sdl.Keymod): set[terminal.Modifier] =
    let raw = mods.uint32
    if (raw and sdl.KMOD_SHIFT) != 0: result.incl terminal.modShift
    if (raw and sdl.KMOD_CTRL) != 0: result.incl terminal.modCtrl
    if (raw and sdl.KMOD_ALT) != 0: result.incl terminal.modAlt
    if (raw and sdl.KMOD_GUI) != 0: result.incl terminal.modSuper

  func toShortcutMods(mods: set[terminal.Modifier]): set[shortcut_map_lib.Modifier] =
    cast[set[shortcut_map_lib.Modifier]](mods)

  func toSdlKeyCode(scancode: sdl.Scancode): terminal.KeyCode =
    case scancode
    of sdl.SCANCODE_RETURN: kEnter
    of sdl.SCANCODE_TAB: kTab
    of sdl.SCANCODE_BACKSPACE: kBackspace
    of sdl.SCANCODE_ESCAPE: kEscape
    of sdl.SCANCODE_INSERT: kInsert
    of sdl.SCANCODE_DELETE: kDelete
    of sdl.SCANCODE_HOME: kHome
    of sdl.SCANCODE_END: kEnd
    of sdl.SCANCODE_PAGEUP: kPageUp
    of sdl.SCANCODE_PAGEDOWN: kPageDown
    of sdl.SCANCODE_UP: kArrowUp
    of sdl.SCANCODE_DOWN: kArrowDown
    of sdl.SCANCODE_LEFT: kArrowLeft
    of sdl.SCANCODE_RIGHT: kArrowRight
    of sdl.SCANCODE_F1: kF1
    of sdl.SCANCODE_F2: kF2
    of sdl.SCANCODE_F3: kF3
    of sdl.SCANCODE_F4: kF4
    of sdl.SCANCODE_F5: kF5
    of sdl.SCANCODE_F6: kF6
    of sdl.SCANCODE_F7: kF7
    of sdl.SCANCODE_F8: kF8
    of sdl.SCANCODE_F9: kF9
    of sdl.SCANCODE_F10: kF10
    of sdl.SCANCODE_F11: kF11
    of sdl.SCANCODE_F12: kF12
    of sdl.SCANCODE_KP_ENTER: kKeypadEnter
    else: kNone

  func toSdlMouseButton(button: uint8): terminal.MouseButton =
    case button
    of sdl.BUTTON_LEFT: mbLeft
    of sdl.BUTTON_MIDDLE: mbMiddle
    of sdl.BUTTON_RIGHT: mbRight
    else: mbRelease

  func printableFromSdlKey(keycode: sdl.Keycode): Option[uint32] =
    if keycode >= 32'u32 and keycode <= 126'u32:
      some(uint32(keycode))
    else:
      none(uint32)

  func shortcutKeyFromSdl(keycode: sdl.Keycode): shortcut_map_lib.KeyCode =
    case keycode
    of sdl.SDLK_EQUALS: shortcut_map_lib.kEqual
    of sdl.SDLK_MINUS: shortcut_map_lib.kMinus
    of sdl.SDLK_PLUS: shortcut_map_lib.kPlus
    of sdl.SDLK_RETURN, sdl.SDLK_KP_ENTER: shortcut_map_lib.kEnter
    else:
      if keycode >= 32'u32 and keycode <= 126'u32:
        shortcut_map_lib.shortcutKey(char(keycode))
      else:
        shortcut_map_lib.kNone

  proc handleTextInput(text: cstring) =
    if overlay_lib.overlayCapturesInput(overlayStack) and surfaceStack.active == asWorkspace: return
    if text == nil or keyTextFallback: return
    if searchInputActive():
      searchInsertText($text)
      return
    let term = activeTerm()
    if term == nil: return
    for r in ($text).runes:
      discard term.sendKey(keyChar(uint32(r)))
    term.damage.markAll()

  proc handleSdlKey(event: sdl.KeyboardEvent) =
    if event.down and event.scancode == sdl.SCANCODE_ESCAPE and catalogMenuOpen:
      dismissCatalogMenu()
      return
    if event.down and event.scancode == sdl.SCANCODE_ESCAPE and handleOverlayEscape():
      return
    if overlay_lib.overlayCapturesInput(overlayStack) and surfaceStack.active == asWorkspace:
      return
    if not event.down: return
    let mods = toTerminalMods(event.`mod`)
    let sc = event.scancode
    if terminal.modCtrl in mods and terminal.modShift in mods and sc == sdl.SCANCODE_A:
      toggleSurface()
      return
    if searchInputActive():
      case sc
      of sdl.SCANCODE_ESCAPE: blurCartographSearch(); return
      of sdl.SCANCODE_BACKSPACE: discard handleSearchEditKey(sekBackspace); return
      of sdl.SCANCODE_DELETE: discard handleSearchEditKey(sekDelete); return
      of sdl.SCANCODE_LEFT: discard handleSearchEditKey(sekLeft); return
      of sdl.SCANCODE_RIGHT: discard handleSearchEditKey(sekRight); return
      of sdl.SCANCODE_HOME: discard handleSearchEditKey(sekHome); return
      of sdl.SCANCODE_END: discard handleSearchEditKey(sekEnd); return
      of sdl.SCANCODE_RETURN, sdl.SCANCODE_KP_ENTER: discard handleSearchEditKey(sekEnter); return
      else:
        if keyTextFallback:
          let ch = printableFromSdlKey(event.key)
          if ch.isSome:
            searchInsertRune(Rune(ch.get().int32))
            return
        ## Swallow other unmodified keys so typing never leaks to the terminal.
        if terminal.modCtrl notin mods and terminal.modAlt notin mods:
          return
    let term = activeTerm()
    if term == nil: return

    if terminal.modCtrl in mods and terminal.modShift in mods and sc == sdl.SCANCODE_T:
      addTerminalTab()
      return
    if terminal.modCtrl in mods and terminal.modShift in mods and sc == sdl.SCANCODE_N:
      let activeCwd = validSessionCwd(activeSessionCwd())
      try:
        discard startProcess(getAppFilename(), args = @[activeCwd], options = {poParentStreams})
      except CatchableError:
        discard
      return
    if terminal.modCtrl in mods and terminal.modShift in mods and (sc == sdl.SCANCODE_RETURN or sc == sdl.SCANCODE_KP_ENTER):
      splitActivePane()
      return
    if terminal.modCtrl in mods and terminal.modShift in mods and sc == sdl.SCANCODE_W:
      closeActivePaneOrTab()
      return
    if terminal.modCtrl in mods and sc == sdl.SCANCODE_TAB:
      if terminal.modShift in mods: discard tabs.activatePrevious()
      else: discard tabs.activateNext()
      let term = activeTerm()
      if term != nil: term.damage.markAll()
      return

    let actionName = term.shortcuts.lookup(shortcutKeyFromSdl(event.key), toShortcutMods(mods))
    if actionName.isSome:
      if handleShortcutAction(term, actionName.get()):
        return

    if terminal.modCtrl in mods or terminal.modAlt in mods or keyTextFallback:
      let ch = printableFromSdlKey(event.key)
      if ch.isSome:
        discard term.sendKey(keyChar(ch.get(), mods))
        term.damage.markAll()
        return

    let tk = toSdlKeyCode(sc)
    if tk != kNone and tk != kChar:
      discard term.sendKey(terminal.key(tk, mods))
      term.damage.markAll()

  proc handleMouseButton(x, y: float; button: uint8; down: bool; mods: set[terminal.Modifier]) =
    if button == sdl.BUTTON_LEFT and handleOverlayPointer(int(x), int(y), down):
      return
    if catalogMenuOpen and button == sdl.BUTTON_LEFT and down:
      if handleCatalogMenuClick(int(x), int(y)):
        return
    if button == sdl.BUTTON_RIGHT and down:
      if openCatalogMenuAt(int(x), int(y)):
        return
    if button == sdl.BUTTON_LEFT and not down:
      draggingWindow = false
      catalogScrollDrag.active = false

    if button == sdl.BUTTON_LEFT and down and inTitleBar(int(y)):
      if surfaceToggleHitTest(int(x), int(y), winWidth, titleBarHeight):
        toggleSurface()
        return
      draggingWindow = true
      dragStartMouseX = x
      dragStartMouseY = y
      let pos = window_relay_lib.getPosition(windowRelays)
      dragStartWinX = cint(pos.x)
      dragStartWinY = cint(pos.y)
      dragStartGlobalX = float(pos.x) + x
      dragStartGlobalY = float(pos.y) + y
      let term = activeTerm()
      if term != nil and term.activeLink.isSome:
        term.activeLink = none(ActiveLink)
        term.damage.markAll()
      return

    if button == sdl.BUTTON_LEFT and down and inTabBar(int(y)):
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

    if int(y) < chromeHeaderHeight(): return
    if handleCartographPointer(int(x), int(y), down):
      return
    var paneFocusChanged = false
    let session = focusPaneAt(int(x), int(y), paneFocusChanged)
    if session == nil: return
    let term = session[].terminal
    # Swallow the pane-focus-acquiring click ONLY when the child isn't tracking
    # mouse. Mouse-aware apps (grok, vim) need that click forwarded too, else
    # their own click-to-focus (e.g. focusing a chat input) never fires.
    if paneFocusChanged and button == sdl.BUTTON_LEFT and down and
       term.inputMode.shouldIntercept(mods):
      return
    let area = activeSessionRect(session[].id)
    if area.isNone: return
    let col = localCol(area.get(), x)
    let row = localRow(area.get(), y)
    let bufferRow = term.viewport.viewportToBuffer(row)
    if bufferRow < 0: return
    if term.inputMode.shouldIntercept(mods):
      if button == sdl.BUTTON_LEFT:
        if not down and term.activeLink.isSome:
          launchUri(term.activeLink.get().link.text)
          return
        term.drag.update(row, col, down)
        if down:
          let wi = activeWorkspaceIndex()
          if wi >= 0: clearSelectionsExcept(workspaces[wi], session[].id)
          term.selection.start(point(bufferRow, col))
        term.damage.markAll()
    else:
      let tmb = toSdlMouseButton(button)
      if tmb != mbRelease:
        lastMouseReportRow = row; lastMouseReportCol = col
        discard term.sendMouse(mouse(if down: mePress else: meRelease, tmb, row, col, mods))

  proc handleMouseMove(x, y: float; state: uint32) =
    if draggingWindow:
      let pos = window_relay_lib.getPosition(windowRelays)
      let currentGlobalX = float(pos.x) + x
      let currentGlobalY = float(pos.y) + y
      window_relay_lib.setPosition(
        windowRelays,
        window_relay_lib.point(
          int(dragStartWinX + cint(currentGlobalX - dragStartGlobalX)),
          int(dragStartWinY + cint(currentGlobalY - dragStartGlobalY)),
        )
      )
      return
    if catalogScrollDrag.active:
      updateCatalogScrollDrag(int(y))
      return
    if catalogMenuOpen:
      updateCatalogMenuHover(int(x), int(y))

    let wi = activeWorkspaceIndex()
    if wi < 0: return
    let activeId = workspaces[wi].panes.active
    let sessionIdx = workspaces[wi].sessionIndex(activeId)
    if sessionIdx < 0: return
    let term = workspaces[wi].sessions[sessionIdx].terminal
    if int(y) < chromeHeaderHeight() and term.drag.state == dsIdle:
      if term.activeLink.isSome:
        term.activeLink = none(ActiveLink)
        term.damage.markAll()
      return
    let area = activeSessionRect(activeId)
    if area.isNone: return
    let col = localCol(area.get(), x)
    let row = localRow(area.get(), y)
    let rawRow = rawLocalRow(area.get(), y)

    if term.drag.state != dsIdle:
      let leftDown = window_relay_lib.isMouseButtonDown(windowRelays, window_relay_lib.mbLeft)
      term.drag.update(rawRow, col, leftDown)
      if term.drag.state == dsIdle:
        term.damage.markAll()
        return
      let delta = term.drag.autoscrollDelta()
      if delta < 0: term.viewport.scrollUp(1)
      elif delta > 0: term.viewport.scrollDown(1)
      term.refreshViewport(false)
      let focusRow = term.drag.focusViewportRow()
      let focusBufferRow = term.viewport.viewportToBuffer(focusRow)
      if focusBufferRow >= 0:
        term.selection.update(point(focusBufferRow, col))
      term.damage.markAll()
    else:
      let absRow = term.viewport.viewportToBuffer(row)
      if absRow < 0: return
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

      if not term.inputMode.shouldIntercept() and term.inputMode.trackingWantsMotion() and
         (row != lastMouseReportRow or col != lastMouseReportCol):
        # Only report motion on cell change (xterm behavior). Per-pixel reports
        # flood the child and turn a jittery click into press+drag+release,
        # which apps read as a selection rather than a focus click.
        lastMouseReportRow = row; lastMouseReportCol = col
        let leftDown = window_relay_lib.isMouseButtonDown(windowRelays, window_relay_lib.mbLeft)
        let kind = if leftDown and term.inputMode.trackingWantsDrag(): meDrag else: meMove
        # No button held during motion must report "no button" (param 35),
        # not a phantom left-drag. mbRelease encodes to the no-button code.
        let btn = if leftDown: terminal.mbLeft else: terminal.mbRelease
        discard term.sendMouse(mouse(kind, btn, row, col, {}))

  proc handleScrollAt(x, y: float; yoffset: float; mods: set[terminal.Modifier]) =
    if handleOverlayWheel(int(x), int(y), yoffset):
      return
    let session = if int(y) >= chromeHeaderHeight(): focusPaneAt(int(x), int(y)) else: nil
    let term = if session == nil: activeTerm() else: session[].terminal
    if term == nil: return
    let ctrlDown = terminal.modCtrl in mods
    let shiftDown = terminal.modShift in mods
    if ctrlDown:
      if yoffset > 0: fontSize += 1.0
      elif yoffset < 0: fontSize = max(4.0, fontSize - 1.0)
      rebuildAtlas()
    else:
      let scrollKind = term.inputMode.scrollInputKind(term.screen.usingAlt)
      let normalTuiLikely =
        (not term.screen.usingAlt) and
        term.inputMode.mouseMode == mmNone and
        (term.inputMode.cursorApp or term.inputMode.focusReporting)
      let action = decideWheelAction(ScrollPolicyInput(
        usingAltScreen: term.screen.usingAlt,
        childWantsWheel: term.inputMode.shouldSendWheel(term.screen.usingAlt),
        childWheelEncoding: toChildWheelEncoding(scrollKind),
        viewportHasHistory: term.viewport.maxScroll > 0,
        viewportHasMeaningfulHistory: term.viewport.hasMeaningfulHistory(config.meaningfulHistoryRows),
        viewportAtLiveEnd: term.viewport.isAtLiveEnd,
        scrollingTowardHistory: yoffset > 0,
        normalScreenTuiLikely: normalTuiLikely,
        forceTerminalScroll: shiftDown,
        forceChildScroll: false,
        altScrollbackMode: config.altScreenScrollback,
        altWheelPolicy: config.altWheelPolicy,
        normalWheelPolicy: config.normalWheelPolicy,
      ))
      let paneId =
        if session == nil:
          let workspace = activeWorkspace()
          if workspace == nil: pane_tree.paneId(-1) else: workspace[].panes.active
        else:
          session[].id
      let area = activeSessionRect(paneId)
      let col = if area.isSome: localCol(area.get(), x) else: term.screen.cursor.col
      let row = if area.isSome: localRow(area.get(), y) else: term.screen.cursor.row
      case action
      of saScrollViewport:
        if yoffset > 0: term.viewport.scrollUp(3)
        elif yoffset < 0: term.viewport.scrollDown(3)
      of saRouteToChild:
        case scrollKind
        of sikCursorKeys:
          let keyCode = if yoffset > 0: kArrowUp else: kArrowDown
          for _ in 0 ..< max(1, int(abs(yoffset) * 3)):
            discard term.sendKey(key(keyCode))
        of sikMouseWheel:
          let button = if yoffset > 0: mbWheelUp else: mbWheelDown
          for _ in 0 ..< max(1, int(abs(yoffset))):
            discard term.sendMouse(mouse(mePress, button, row, col))
        of sikNone:
          discard
      of saRouteMouseWheel:
        let button = if yoffset > 0: mbWheelUp else: mbWheelDown
        for _ in 0 ..< max(1, int(abs(yoffset))):
          discard term.sendMouse(mouse(mePress, button, row, col))
      of saRouteCursorKeys:
        let keyCode = if yoffset > 0: kArrowUp else: kArrowDown
        for _ in 0 ..< max(1, int(abs(yoffset) * 3)):
          discard term.sendKey(key(keyCode))
      of saRoutePageKeys:
        let keyCode = if yoffset > 0: kPageUp else: kPageDown
        discard term.sendKey(key(keyCode))
      of saIgnore:
        discard
      term.refreshViewport(false)
    term.damage.markAll()

  proc resizeToFramebuffer(fallbackWidth, fallbackHeight: cint) =
    let drawableSize = window_relay_lib.getDrawableSize(windowRelays)
    let currentWindowSize = window_relay_lib.getWindowSize(windowRelays)
    let report = chooseDrawableSize(
      framebuffer = size2d(drawableSize.width, drawableSize.height),
      window = size2d(currentWindowSize.width, currentWindowSize.height),
      fallback = size2d(int(fallbackWidth), int(fallbackHeight)),
    )
    if not report.chosen.isPositive: return
    let changedSize = report.changedFrom(size2d(winWidth, winHeight))
    if changedSize:
      winWidth = report.chosen.width
      winHeight = report.chosen.height
      if rend != nil and rend.atlas != nil:
        resizeTerminals()
    render_relay_lib.setViewport(frameRelays, render_relay_lib.size2d(winWidth, winHeight))

  proc syncFramebufferSize(): bool =
    if window == nil: return false
    let drawableSize = window_relay_lib.getDrawableSize(windowRelays)
    let currentWindowSize = window_relay_lib.getWindowSize(windowRelays)
    let report = chooseDrawableSize(
      framebuffer = size2d(drawableSize.width, drawableSize.height),
      window = size2d(currentWindowSize.width, currentWindowSize.height),
      fallback = size2d(0, 0),
    )
    if not report.chosen.isPositive: return false
    if not report.changedFrom(size2d(winWidth, winHeight)): return false
    resizeToFramebuffer(cint(report.chosen.width), cint(report.chosen.height))
    true

  proc onWindowFocus(focused: bool) =
    let term = activeTerm()
    if term == nil: return
    discard term.sendFocus(focused)

  proc pollEvents() =
    var event: sdl.Event
    while sdl.pollEvent(event):
      let evType = uint32(event.common.`type`)
      if evType == uint32(sdl.EVENT_QUIT) or evType == uint32(sdl.EVENT_WINDOW_CLOSE_REQUESTED):
        appShouldClose = true
      elif evType == uint32(sdl.EVENT_WINDOW_RESIZED) or evType == uint32(sdl.EVENT_WINDOW_PIXEL_SIZE_CHANGED):
        resizeToFramebuffer(cint(event.window.data1), cint(event.window.data2))
      elif evType == uint32(sdl.EVENT_WINDOW_FOCUS_GAINED):
        onWindowFocus(true)
      elif evType == uint32(sdl.EVENT_WINDOW_FOCUS_LOST):
        onWindowFocus(false)
      elif evType == uint32(sdl.EVENT_TEXT_INPUT):
        handleTextInput(event.text.text)
      elif evType == uint32(sdl.EVENT_KEY_DOWN):
        handleSdlKey(event.key)
      elif evType == uint32(sdl.EVENT_MOUSE_BUTTON_DOWN) or evType == uint32(sdl.EVENT_MOUSE_BUTTON_UP):
        handleMouseButton(event.button.x, event.button.y, event.button.button, event.button.down, toTerminalMods(sdl.getModState()))
      elif evType == uint32(sdl.EVENT_MOUSE_MOTION):
        handleMouseMove(event.motion.x, event.motion.y, event.motion.state)
      elif evType == uint32(sdl.EVENT_MOUSE_WHEEL):
        handleScrollAt(event.wheel.mouse_x, event.wheel.mouse_y, event.wheel.y, toTerminalMods(sdl.getModState()))

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

config = loadTerminalConfig()
fontSize = config.fontSize
lifecycleChaosCycles = parseIntOr(getEnv("WAYMARK_LIFECYCLE_CHAOS_CYCLES", "0"), 0)
keyTextFallback =
  getEnv("WAYMARK_KEY_TEXT_FALLBACK", "0") == "1"
inputDebug = getEnv("WAYMARK_INPUT_DEBUG", "0") == "1"

chooseInitialWindowSize()

when defined(waymarkSdl3):
  if not sdl.init(sdl.INIT_VIDEO): quit("Failed to init SDL3: " & $sdl.getError())
  discard sdl.gL_SetAttribute(sdl.GL_CONTEXT_MAJOR_VERSION, 2)
  discard sdl.gL_SetAttribute(sdl.GL_CONTEXT_MINOR_VERSION, 1)
  discard sdl.gL_SetAttribute(sdl.GL_DOUBLEBUFFER, 1)
  let flags = sdl.WINDOW_OPENGL or sdl.WINDOW_RESIZABLE or sdl.WINDOW_HIGH_PIXEL_DENSITY
  window = sdl.createWindow(cstring(config.title), cint(winWidth), cint(winHeight), flags)
  if window == nil: quit("Failed to create SDL3 window: " & $sdl.getError())
  installSdlWindowRelays()
  window_relay_lib.setMinimumSize(windowRelays, window_relay_lib.size2d(MinWindowWidth, MinWindowHeight))
  glContext = sdl.gL_CreateContext(window)
  if glContext == nil: quit("Failed to create SDL3 OpenGL context: " & $sdl.getError())
  if not sdl.gL_MakeCurrent(window, glContext): quit("Failed to make SDL3 OpenGL context current: " & $sdl.getError())
  loadExtensions()
  discard sdl.gL_SetSwapInterval(1)
  discard sdl.startTextInput(window)
  installOpenGlGpuRelays()
  installSdlRenderRelays()
  installClipboardProviders()
  resizeToFramebuffer(cint(winWidth), cint(winHeight))
else:
  if init() == 0: quit("Failed to init GLFW")
  windowHint(CONTEXT_VERSION_MAJOR, 2); windowHint(CONTEXT_VERSION_MINOR, 1)
  window = createWindow(cint(winWidth), cint(winHeight), cstring(config.title), nil, nil)
  if window == nil: quit("Failed to create window")
  installGlfwWindowRelays()
  window_relay_lib.setMinimumSize(windowRelays, window_relay_lib.size2d(MinWindowWidth, MinWindowHeight))
  focusWindow(window)
  makeContextCurrent(window); loadExtensions()
  swapInterval(cint(1))  # vsync: cap presentation to display refresh (mirrors SDL gL_SetSwapInterval)
  installOpenGlGpuRelays()
  installGlfwRenderRelays()
  installClipboardProviders()
  let drawableSize = window_relay_lib.getDrawableSize(windowRelays)
  if window_relay_lib.isPositive(drawableSize):
    winWidth = drawableSize.width
    winHeight = drawableSize.height
    render_relay_lib.setViewport(frameRelays, render_relay_lib.size2d(winWidth, winHeight))

fallbackTypefaces = loadFallbackTypefaces()
let atlas = makeAtlas(fontSize, font)
let chromeAtlas = makeAtlas(config.fontSize, chromeFont)
rend = newGpuTerminalRenderer(atlas, chromeAtlas, gpuRelays)
rend.loadLogoTexture(config.logoPath)
updateChromeHeights()
addTerminalTab()
installAppSurfaces()

when not defined(waymarkSdl3):
  discard window.setCharCallback(onChar); discard window.setKeyCallback(onKey)
  discard window.setMouseButtonCallback(onMouseButton); discard window.setCursorPosCallback(onCursorPos)
  discard window.setScrollCallback(onScroll); discard window.setFramebufferSizeCallback(onResize)
  discard window.setWindowSizeCallback(onResize)
  discard window.setWindowFocusCallback(onWindowFocus)
  onResize(window, cint(winWidth), cint(winHeight))
writeGpuSnapshot()

if lifecycleChaosCycles > 0:
  runLifecycleChaos(lifecycleChaosCycles)
  closeAllWorkspaces()
  if rend != nil:
    rend.dispose()
    disposeOpenGlGpuRelays()
    writeGpuSnapshot()
  when defined(waymarkSdl3):
    if glContext != nil:
      discard sdl.gL_DestroyContext(glContext)
      glContext = nil
    if window != nil:
      sdl.destroyWindow(window)
      window = nil
    sdl.quit()
  else:
    terminate()
  quit(0)

let perf = newPerfMonitor()
# Frame-rate cap. vsync (gL_SetSwapInterval) is unreliable under Wayland/this GL setup --
# present does not block, so without this the loop free-runs at ~20k FPS whenever a process is
# emitting output (n>0 every iteration), saturating the GPU and starving compute (e.g. ROCm
# training) until amdgpu hangs. This explicit budget caps the loop regardless of vsync.
let maxFps = block:
  let raw = os.getEnv("WAYMARK_MAX_FPS", "120")
  try: max(1, parseInt(raw)) except CatchableError: 120
let frameBudgetSec = 1.0 / maxFps.float
while true:
  if window_relay_lib.shouldClose(windowRelays): break
  let frameStart = epochTime()
  perf.beginFrame()
  let resized = syncFramebufferSize()
  if resized:
    markCartographDirty(cartographWorkspace)
    if surfaceStack.active == asWorkspace:
      clampCartographCatalogScroll(cartographWorkspace, catalogListLayout().visibleRows)
  resizeTerminals()
  let n = surfaceStack.tickActive()
  let term = activeTerm()
  if term == nil and surfaceStack.active == asPrimary:
    break
  let atlasWasDirty = atlas.isDirty
  let chromeAtlasWasDirty = chromeAtlas.isDirty
  if atlasWasDirty: rend.updateAtlasTexture()
  if chromeAtlasWasDirty: rend.updateChromeAtlasTexture()
  let tabLabelsChanged =
    if surfaceStack.active == asPrimary: refreshTabCwdLabels() else: false
  let catalogChanged =
    if surfaceStack.active == asWorkspace: refreshCatalogForActiveCwd() else: false
  let blockedBySyncUpdate = activeWorkspaceSyncUpdateActive()
  let surfaceDirty =
    if surfaceStack.active == asPrimary: activeWorkspaceDirty() else: surfaceStack.activeNeedsRedraw()
  let overlayOpen = not overlay_lib.overlayIsEmpty(overlayStack)
  let toastsActive = surfaceStack.active == asWorkspace and toast_lib.hasActive(appToasts, epochTime())
  let changed = (resized or n > 0 or atlasWasDirty or chromeAtlasWasDirty or surfaceDirty or tabLabelsChanged or catalogChanged or overlayOpen or toastsActive) and not blockedBySyncUpdate
  if changed:
    surfaceStack.drawActive()
    drawOverlays()
    rend.drawChrome(tabs, winWidth, winHeight, titleBarHeight, tabBarHeight, surfaceStack.active, config.title)
    render_relay_lib.endFrame(frameRelays)
    writeGpuSnapshot()
    if term != nil:
      writeScreenSnapshot(term)
  pollEvents(); perf.endFrame()
  if perf.shouldReport(2.0):
    let s = perf.takeReport()
    echo "FPS: ", s.fps, " Latency: ", s.avgLatencyMs, " ms"
  # Pace the frame to the budget whether or not anything changed. This is the real cap:
  # even under continuous output (n>0) the loop can never exceed maxFps, so it cannot
  # busy-render the GPU. Idle frames sleep the full budget; active frames sleep the remainder.
  let frameSec = epochTime() - frameStart
  if frameSec < frameBudgetSec:
    os.sleep(int((frameBudgetSec - frameSec) * 1000.0))

persistActiveSurface()

if rend != nil:
  rend.dispose()
  disposeOpenGlGpuRelays()
  writeGpuSnapshot()
when defined(waymarkSdl3):
  if glContext != nil:
    discard sdl.gL_DestroyContext(glContext)
    glContext = nil
  if window != nil:
    sdl.destroyWindow(window)
    window = nil
  sdl.quit()
else:
  terminate()
