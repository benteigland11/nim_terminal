## GPU-accelerated terminal grid renderer.
##
## Translates the in-memory `Screen` buffer into GPU quads.
## Uses `TileBatcher` for efficiency and `GlyphAtlas` for UV mapping.

import pixie
import std/[options, os, times, unicode]
import ../cg/data_screen_buffer_nim/src/screen_buffer_lib
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
import ../cg/universal_tile_batcher_nim/src/tile_batcher_lib
import ../cg/frontend_gpu_relays_nim/src/gpu_relays_lib
import ../cg/universal_tab_set_nim/src/tab_set_lib
import ../cg/frontend_app_surface_relays_nim/src/app_surface_relays_lib
import ../cg/frontend_workspace_chrome_nim/src/workspace_chrome_lib
import ../cg/data_widget_catalog_nim/src/widget_catalog_lib as widget_catalog
import cartograph_surface
import ../cg/universal_resource_ledger_nim/src/resource_ledger_lib
import ../cg/data_pixel_resource_size_nim/src/pixel_resource_size_lib
import ../cg/data_terminal_render_attrs_nim/src/terminal_render_attrs_lib as render_attrs
import ../cg/frontend_cursor_row_highlight_nim/src/cursor_row_highlight_lib
import ../cg/frontend_overlay_stack_nim/src/overlay_stack_lib as overlay_lib
import ../cg/frontend_scroll_tree_nim/src/scroll_tree_lib as scroll_tree
import ../cg/frontend_syntax_viewport_nim/src/syntax_viewport_lib as syntax_viewport
import ../cg/frontend_chrome_theme_nim/src/chrome_theme_lib as chrome_theme
import ../cg/frontend_menu_nim/src/menu_lib as menu_lib
import ../cg/frontend_button_nim/src/button_lib as button_lib
import ../cg/frontend_scrollbar_nim/src/scrollbar_lib as scrollbar_lib
import ../cg/frontend_toast_nim/src/toast_lib as toast_lib
import ../cg/frontend_underline_decoration_nim/src/underline_decoration_lib as underline_deco
import terminal

## Single source of truth for chrome colors. Rebrand by reassigning this
## (e.g. `appChromeTheme = appChromeTheme.withAccent(...)`).
var appChromeTheme* = chrome_theme.defaultDarkChromeTheme()

func toRgba(c: chrome_theme.ThemeColor): tile_batcher_lib.RgbaColor =
  tile_batcher_lib.rgba(c.r.float32, c.g.float32, c.b.float32, c.a.float32)

type
  GpuTerminalRenderer* = ref object
    atlas*: GlyphAtlas
    chromeAtlas*: GlyphAtlas
    batcher*: TileBatcher
    gpu*: GpuRelays
    gpuVertices: seq[GpuVertex]
    atlasTexId*: uint32
    chromeTexId*: uint32
    bgTexId*: uint32      ## 1x1 white texture for drawing backgrounds
    logoTexId*: uint32
    logoAspect*: float32
    resources*: ResourceLedger
    disposed*: bool

func glId(id: uint32): string = $id

func atlasBytes(atlas: GlyphAtlas): int64 =
  if atlas == nil or atlas.atlasImage.width <= 0 or atlas.atlasImage.height <= 0:
    return 0
  rgba8Bytes(atlas.atlasImage.width, atlas.atlasImage.height)

proc recordTexture(r: GpuTerminalRenderer; id: uint32; label: string; bytes: int64) =
  if r == nil or id == 0: return
  r.resources.recordUpsert("texture", glId(id), bytes, label)

proc recordBatcherBuffer(r: GpuTerminalRenderer) =
  if r == nil or r.batcher == nil: return
  let id = r.batcher.gpuBufferId()
  if id == 0: return
  r.resources.recordUpsert("buffer", glId(id), r.batcher.uploadedVertexBytes(), "tile batch vertex buffer")

proc finishBatch(r: GpuTerminalRenderer) =
  r.batcher.endBatch(proc (textureId: uint32; vertices: openArray[TileVertex]) =
    r.gpuVertices.setLen(vertices.len)
    for i, vertex in vertices:
      r.gpuVertices[i] = GpuVertex(
        x: vertex.x,
        y: vertex.y,
        u: vertex.u,
        v: vertex.v,
        r: vertex.r,
        g: vertex.g,
        b: vertex.b,
        a: vertex.a,
      )
    r.gpu.drawTexturedTriangles(gpu_relays_lib.textureId(textureId), r.gpuVertices)
  )

proc uploadAtlasTexture(r: GpuTerminalRenderer; atlas: GlyphAtlas; texId: uint32; label: string) =
  let img = atlas.atlasImage
  if img.width <= 0 or img.height <= 0 or img.data.len == 0: return
  r.gpu.uploadRgba8Texture(textureId(texId), img.width, img.height, addr img.data[0])
  atlas.isDirty = false
  r.recordTexture(texId, label, atlasBytes(atlas))

proc updateAtlasTexture*(r: GpuTerminalRenderer) =
  if not r.atlas.isDirty: return
  uploadAtlasTexture(r, r.atlas, r.atlasTexId, "glyph atlas")

proc updateChromeAtlasTexture*(r: GpuTerminalRenderer) =
  if not r.chromeAtlas.isDirty: return
  uploadAtlasTexture(r, r.chromeAtlas, r.chromeTexId, "chrome glyph atlas")

proc loadLogoTexture*(r: GpuTerminalRenderer, path: string) =
  try:
    let img = readImage(path)
    if img.width <= 0 or img.height <= 0 or img.data.len == 0: return
    if r.logoTexId != 0:
      var oldId = r.logoTexId
      r.gpu.deleteTexture(textureId(oldId))
      r.resources.recordDelete("texture", glId(oldId))
      r.logoTexId = 0
    let id = uint32Value(r.gpu.createTexture())
    r.gpu.configureTexture(textureId(id), defaultTextureOptions(gtfLinear))
    r.gpu.uploadRgba8Texture(textureId(id), img.width, img.height, addr img.data[0])
    r.logoTexId = id
    r.logoAspect = img.width.float32 / img.height.float32
    r.recordTexture(id, "titlebar logo", rgba8Bytes(img.width, img.height))
  except CatchableError:
    r.logoTexId = 0
    r.logoAspect = 1.0

func toRgba(c: PaletteColor): RgbaColor =
  tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

func toRgba(c: render_attrs.RenderColor): RgbaColor =
  tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

func toRgba(c: HighlightColor): RgbaColor =
  tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

func toRenderColor(c: PaletteColor): render_attrs.RenderColor =
  render_attrs.rgb(c.r, c.g, c.b)

func toTerminalColor(c: screen_buffer_lib.Color): render_attrs.TerminalColor =
  case c.kind
  of screen_buffer_lib.ckDefault:
    render_attrs.defaultColor()
  of screen_buffer_lib.ckIndexed:
    render_attrs.indexedColor(int(c.index))
  of screen_buffer_lib.ckRgb:
    render_attrs.rgbColor(c.r, c.g, c.b)

func toRenderFlags(flags: set[AttrFlag]): set[render_attrs.RenderFlag] =
  if afBold in flags: result.incl render_attrs.rfBold
  if afDim in flags: result.incl render_attrs.rfDim
  if afItalic in flags: result.incl render_attrs.rfItalic
  if afUnderline in flags: result.incl render_attrs.rfUnderline
  if afStrike in flags: result.incl render_attrs.rfStrike
  if afInverse in flags: result.incl render_attrs.rfInverse
  if afHidden in flags: result.incl render_attrs.rfHidden
  if afOverline in flags: result.incl render_attrs.rfOverline

func toRenderAttrs(attrs: Attrs): render_attrs.RenderAttrs =
  render_attrs.RenderAttrs(
    fg: toTerminalColor(attrs.fg),
    bg: toTerminalColor(attrs.bg),
    flags: toRenderFlags(attrs.flags),
  )

proc preRenderAscii*(r: GpuTerminalRenderer) =
  for i in 32..126: discard r.atlas.getGlyph(uint32(i))
  r.updateAtlasTexture()

proc preRenderChromeAscii*(r: GpuTerminalRenderer) =
  for i in 32..126: discard r.chromeAtlas.getGlyph(uint32(i))
  discard r.chromeAtlas.getGlyph(0x25B2'u32)  ## ▲
  discard r.chromeAtlas.getGlyph(0x25BC'u32)  ## ▼
  r.updateChromeAtlasTexture()

proc newGpuTerminalRenderer*(atlas: GlyphAtlas, chromeAtlas: GlyphAtlas = nil, gpu = noopGpuRelays()): GpuTerminalRenderer =
  var ids: array[3, uint32]
  for i in 0 ..< ids.len:
    ids[i] = uint32Value(gpu.createTexture())
  gpu.configureTexture(textureId(ids[0]), defaultTextureOptions(gtfLinear))
  gpu.configureTexture(textureId(ids[1]), defaultTextureOptions(gtfLinear))
  gpu.configureTexture(textureId(ids[2]), defaultTextureOptions(gtfNearest))
  var whitePixel: uint32 = 0xFFFFFFFF'u32
  gpu.uploadSolidRgba8Texture(textureId(ids[2]), whitePixel)

  result = GpuTerminalRenderer(
    atlas: atlas,
    chromeAtlas: if chromeAtlas == nil: atlas else: chromeAtlas,
    batcher: newTileBatcher(ids[0], capacity = 100000),
    gpu: gpu,
    gpuVertices: @[],
    atlasTexId: ids[0],
    chromeTexId: ids[1],
    bgTexId: ids[2],
    logoTexId: 0,
    logoAspect: 1.0,
    resources: newResourceLedger(),
    disposed: false,
  )
  result.recordTexture(result.atlasTexId, "glyph atlas", atlasBytes(result.atlas))
  result.recordTexture(result.chromeTexId, "chrome glyph atlas", atlasBytes(result.chromeAtlas))
  result.recordTexture(result.bgTexId, "solid color texture", rgba8Bytes(1, 1))
  result.preRenderAscii()
  result.preRenderChromeAscii()

proc gpuSnapshot*(r: GpuTerminalRenderer): ResourceSnapshot =
  if r == nil:
    return newResourceLedger().snapshot()
  r.recordBatcherBuffer()
  r.resources.snapshot()

proc dispose*(r: GpuTerminalRenderer) =
  if r == nil or r.disposed: return
  if r.batcher != nil:
    let id = r.batcher.gpuBufferId()
    r.batcher.dispose()
    if id != 0:
      r.resources.recordDelete("buffer", glId(id))
  var texIds: seq[uint32] = @[]
  for id in [r.atlasTexId, r.chromeTexId, r.bgTexId, r.logoTexId]:
    if id != 0:
      texIds.add id
  for id in texIds:
    r.gpu.deleteTexture(textureId(id))
    r.resources.recordDelete("texture", glId(id))
  r.atlasTexId = 0
  r.chromeTexId = 0
  r.bgTexId = 0
  r.logoTexId = 0
  r.disposed = true

func ndcX(px, winWidth: int): float32 =
  -1.0'f32 + (float32(px) / float32(winWidth)) * 2.0'f32

func ndcY(py, winHeight: int): float32 =
  1.0'f32 - (float32(py) / float32(winHeight)) * 2.0'f32

func ndcW(px, winWidth: int): float32 =
  (float32(px) / float32(winWidth)) * 2.0'f32

func ndcH(py, winHeight: int): float32 =
  (float32(py) / float32(winHeight)) * 2.0'f32

proc addRect(r: GpuTerminalRenderer, x, y, w, h, winWidth, winHeight: int, color: RgbaColor) =
  r.batcher.addTile(ndcX(x, winWidth), ndcY(y, winHeight), ndcW(w, winWidth), ndcH(h, winHeight), 0, 0, 1, 1, color)

proc addChromeText(r: GpuTerminalRenderer, x, y, winWidth, winHeight: int, text: string, color: RgbaColor, maxChars: int = int.high) =
  var col = 0
  for rune in text.runes:
    if col >= maxChars: break
    let glyph = r.chromeAtlas.getGlyph(uint32(rune))
    r.batcher.addTile(
      ndcX(x + col * r.chromeAtlas.cellWidth, winWidth),
      ndcY(y, winHeight),
      ndcW(r.chromeAtlas.cellWidth, winWidth),
      ndcH(r.chromeAtlas.cellHeight, winHeight),
      glyph.uvMin.x, glyph.uvMin.y, glyph.uvMax.x, glyph.uvMax.y,
      color
    )
    inc col

proc prepareChromeText(r: GpuTerminalRenderer, text: string, maxChars: int = int.high) =
  var col = 0
  for rune in text.runes:
    if col >= maxChars: break
    discard r.chromeAtlas.getGlyph(uint32(rune))
    inc col

proc drawChrome*(
    r: GpuTerminalRenderer,
    tabs: TabSet,
    winWidth, winHeight, titleBarHeight, tabBarHeight: int,
    activeSurface: AppSurfaceId,
    title = "Waymark - Built with Nim",
    progress: ProgressSnapshot = ProgressSnapshot(),
) =
  if winWidth <= 0 or winHeight <= 0 or titleBarHeight <= 0: return
  let showTabs = activeSurface == asPrimary and tabBarHeight > 0
  let headerHeight = if showTabs: titleBarHeight + tabBarHeight else: titleBarHeight
  let titleBg = tile_batcher_lib.rgba(0.11, 0.12, 0.13, 1.0)
  let bg = tile_batcher_lib.rgba(0.07, 0.08, 0.09, 1.0)
  let border = tile_batcher_lib.rgba(0.24, 0.28, 0.32, 1.0)
  let nimYellow = tile_batcher_lib.rgba(0.95, 0.76, 0.23, 1.0)
  let activeBg = tile_batcher_lib.rgba(0.16, 0.18, 0.20, 1.0)
  let inactiveBg = tile_batcher_lib.rgba(0.10, 0.11, 0.12, 1.0)
  let closeBg = tile_batcher_lib.rgba(0.20, 0.22, 0.24, 1.0)
  let text = tile_batcher_lib.rgba(0.88, 0.91, 0.92, 1.0)
  let muted = tile_batcher_lib.rgba(0.58, 0.63, 0.67, 1.0)
  let progressTrack = tile_batcher_lib.rgba(0.18, 0.20, 0.22, 1.0)
  let progressFill =
    case progress.state
    of pbsError: tile_batcher_lib.rgba(0.86, 0.28, 0.28, 1.0)
    of pbsPaused: tile_batcher_lib.rgba(0.95, 0.76, 0.23, 1.0)
    of pbsIndeterminate: tile_batcher_lib.rgba(0.35, 0.62, 0.95, 1.0)
    else: tile_batcher_lib.rgba(0.32, 0.72, 0.48, 1.0)

  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(0, 0, winWidth, titleBarHeight, winWidth, winHeight, titleBg)
  if progress.visible:
    ## OSC 9;4 host progress — thin strip under the title (ConEmu/WT style).
    let barH = max(2, min(4, titleBarHeight div 6))
    let barY = titleBarHeight - barH
    r.addRect(0, barY, winWidth, barH, winWidth, winHeight, progressTrack)
    if progress.state == pbsIndeterminate:
      ## Sliding chunk so long compact/busy work still looks alive.
      let chunk = max(24, winWidth div 5)
      let phase = int((epochTime() * 0.7) * float(winWidth + chunk)) mod (winWidth + chunk)
      let x = phase - chunk
      let drawX = max(0, x)
      let drawW = min(winWidth - drawX, chunk - (drawX - x))
      if drawW > 0:
        r.addRect(drawX, barY, drawW, barH, winWidth, winHeight, progressFill)
    else:
      let fillW = max(0, min(winWidth, int(float(winWidth) * progress.fraction)))
      if fillW > 0:
        r.addRect(0, barY, fillW, barH, winWidth, winHeight, progressFill)
  else:
    r.addRect(0, titleBarHeight - 1, winWidth, 1, winWidth, winHeight, nimYellow)
  if showTabs:
    r.addRect(0, titleBarHeight, winWidth, tabBarHeight, winWidth, winHeight, bg)
    r.addRect(0, headerHeight - 1, winWidth, 1, winWidth, winHeight, border)

  let toggle = surfaceToggleRect(winWidth, titleBarHeight)
  let toggleActive = activeSurface == asWorkspace
  let toggleBg = if toggleActive: activeBg else: inactiveBg
  r.addRect(toggle.x, toggle.y, toggle.width, toggle.height, winWidth, winHeight, toggleBg)

  if not showTabs:
    r.finishBatch()

    let logoX = 8
    let logoH = max(18, min(titleBarHeight - 4, 30))
    let logoW = max(14, int(float32(logoH) * r.logoAspect))
    let logoY = max(2, (titleBarHeight - logoH) div 2)
    if r.logoTexId != 0:
      r.batcher.textureId = r.logoTexId
      r.batcher.beginBatch()
      r.batcher.addTile(
        ndcX(logoX, winWidth), ndcY(logoY, winHeight),
        ndcW(logoW, winWidth), ndcH(logoH, winHeight),
        0, 0, 1, 1,
        tile_batcher_lib.rgba(1, 1, 1, 1),
      )
      r.finishBatch()

    r.batcher.textureId = r.chromeTexId
    r.batcher.beginBatch()
    let titleTextY = max(1, (titleBarHeight - r.chromeAtlas.cellHeight) div 2)
    let titleTextX = if r.logoTexId != 0: logoX + logoW + 10 else: logoX
    let titleCols = max(0, (toggle.x - titleTextX - 12) div max(1, r.chromeAtlas.cellWidth))
    r.prepareChromeText(title, titleCols)
    r.prepareChromeText("Terminal")
    r.prepareChromeText("Cartograph")
    if r.chromeAtlas.isDirty:
      r.updateChromeAtlasTexture()
    r.addChromeText(titleTextX, titleTextY, winWidth, winHeight, title, text, titleCols)
    let toggleText = if toggleActive: "Cartograph" else: "Terminal"
    let toggleTextX = toggle.x + max(8, (toggle.width - toggleText.len * r.chromeAtlas.cellWidth) div 2)
    let toggleTextY = toggle.y + max(1, (toggle.height - r.chromeAtlas.cellHeight) div 2)
    r.addChromeText(toggleTextX, toggleTextY, winWidth, winHeight, toggleText, if toggleActive: text else: muted, 16)
    r.finishBatch()
    return

  if tabBarHeight <= 0: return

  let plusWidth = max(32, tabBarHeight)
  let tabCount = max(1, tabs.tabs.len)
  let canClose = tabs.tabs.len > 1
  let tabAreaWidth = max(0, winWidth - plusWidth)
  let tabWidth = if tabs.tabs.len == 0: tabAreaWidth else: max(12, tabAreaWidth div tabCount)

  for i, tab in tabs.tabs:
    let x = i * tabWidth
    if x >= tabAreaWidth: break
    let w = min(tabWidth, tabAreaWidth - x)
    let isActive = tabs.activeId.isSome and tabs.activeId.get() == tab.id
    r.addRect(x, titleBarHeight + 2, w, tabBarHeight - 3, winWidth, winHeight, if isActive: activeBg else: inactiveBg)
    if canClose and w >= 44:
      let closeSize = max(10, min(tabBarHeight - 10, 16))
      let closeX = x + w - closeSize - 6
      let closeY = titleBarHeight + max(4, (tabBarHeight - closeSize) div 2)
      r.addRect(closeX, closeY, closeSize, closeSize, winWidth, winHeight, closeBg)
    r.addRect(x + w - 1, titleBarHeight + 4, 1, tabBarHeight - 8, winWidth, winHeight, border)

  r.addRect(tabAreaWidth, titleBarHeight + 2, plusWidth, tabBarHeight - 3, winWidth, winHeight, inactiveBg)
  r.finishBatch()

  let logoX = 8
  let logoH = max(18, min(titleBarHeight - 4, 30))
  let logoW = max(14, int(float32(logoH) * r.logoAspect))
  let logoY = max(2, (titleBarHeight - logoH) div 2)
  if r.logoTexId != 0:
    r.batcher.textureId = r.logoTexId
    r.batcher.beginBatch()
    r.batcher.addTile(
      ndcX(logoX, winWidth), ndcY(logoY, winHeight),
      ndcW(logoW, winWidth), ndcH(logoH, winHeight),
      0, 0, 1, 1,
      tile_batcher_lib.rgba(1, 1, 1, 1),
    )
    r.finishBatch()

  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  let titleTextY = max(1, (titleBarHeight - r.chromeAtlas.cellHeight) div 2)
  let titleTextX = if r.logoTexId != 0: logoX + logoW + 10 else: logoX
  let titleCols = max(0, (winWidth - titleTextX - 12) div max(1, r.chromeAtlas.cellWidth))
  r.prepareChromeText(title, titleCols)
  for tab in tabs.tabs:
    r.prepareChromeText(tab.label)
  r.prepareChromeText("x+")
  if r.chromeAtlas.isDirty:
    r.updateChromeAtlasTexture()

  r.addChromeText(titleTextX, titleTextY, winWidth, winHeight, title, text, titleCols)

  let textY = titleBarHeight + max(1, (tabBarHeight - r.chromeAtlas.cellHeight) div 2)
  for i, tab in tabs.tabs:
    let x = i * tabWidth
    if x >= tabAreaWidth: break
    let w = min(tabWidth, tabAreaWidth - x)
    let isActive = tabs.activeId.isSome and tabs.activeId.get() == tab.id
    let closeReserve = if canClose and w >= 44: max(18, min(tabBarHeight, 24)) else: 0
    let labelCols = max(0, (w - 16 - closeReserve) div max(1, r.chromeAtlas.cellWidth))
    r.addChromeText(x + 8, textY, winWidth, winHeight, tab.label, if isActive: text else: muted, labelCols)
    if canClose and w >= 44:
      let closeSize = max(10, min(tabBarHeight - 10, 16))
      let closeX = x + w - closeSize - 6
      let closeTextX = closeX + max(0, (closeSize - r.chromeAtlas.cellWidth) div 2)
      r.addChromeText(closeTextX, textY, winWidth, winHeight, "x", muted, 1)

  let plusX = tabAreaWidth + max(0, (plusWidth - r.chromeAtlas.cellWidth) div 2)
  r.addChromeText(plusX, textY, winWidth, winHeight, "+", text, 1)
  let toggleText = if toggleActive: "Cartograph" else: "Terminal"
  let toggleTextX = toggle.x + max(8, (toggle.width - toggleText.len * r.chromeAtlas.cellWidth) div 2)
  let toggleTextY = toggle.y + max(1, (toggle.height - r.chromeAtlas.cellHeight) div 2)
  r.prepareChromeText(toggleText)
  r.addChromeText(toggleTextX, toggleTextY, winWidth, winHeight, toggleText, if toggleActive: text else: muted, 16)
  r.finishBatch()

proc catalogListSubtitle(entry: widget_catalog.CatalogEntry): string =
  if entry.language.len > 0 and entry.domain.len > 0:
    entry.language & " - " & entry.domain
  elif entry.language.len > 0:
    entry.language
  elif entry.domain.len > 0:
    entry.domain
  else:
    entry.id

func catalogEntryTitleColor(
  entry: widget_catalog.CatalogEntry;
  selected: bool;
  textColor, muted, accent: RgbaColor,
): RgbaColor =
  if not entry.validated:
    accent
  elif selected:
    textColor
  else:
    muted

func centeredLabelOrigin(btn: overlay_lib.OverlayRect; cellWidth, cellHeight: int; label: string): (int, int) =
  let textW = overlay_lib.buttonPixelWidth(cellWidth, label, 0)
  (
    btn.x + max(0, (btn.w - textW) div 2),
    btn.y + max(0, (btn.h - cellHeight) div 2),
  )

proc drawCartographShell*(
    r: GpuTerminalRenderer,
    winWidth, winHeight: int,
    regions: ThreeColumnRegions,
    catalog: widget_catalog.WidgetCatalog,
    selectedIndex: int,
    catalogScrollRow: int,
    actionBarHeight: int,
    catalogFooterHeight: int,
    searchText: string = "",
    searchCaretCol: int = -1,
    searchFocused: bool = false,
    showScrollbar: bool = false,
    scrollbarTrack: scrollbar_lib.ScrollbarTrack = scrollbar_lib.ScrollbarTrack(),
    scrollbarThumb: scrollbar_lib.ScrollbarThumb = scrollbar_lib.ScrollbarThumb(),
) =
  if r == nil or winWidth <= 0 or winHeight <= 0:
    return
  let panelBg = appChromeTheme.panel.toRgba()
  let railBg = appChromeTheme.rail.toRgba()
  let accent = appChromeTheme.accent.toRgba()
  let textColor = appChromeTheme.text.toRgba()
  let muted = appChromeTheme.muted.toRgba()
  let border = appChromeTheme.border.toRgba()
  let selectedBg = appChromeTheme.selection.toRgba()
  let pad = 10
  let cellHeight = r.chromeAtlas.cellHeight
  let cellWidth = r.chromeAtlas.cellWidth
  let catalogListH =
    if catalogFooterHeight > 0:
      max(0, regions.catalog.h - catalogFooterHeight)
    else:
      regions.catalog.h
  let layout = computeCatalogListLayout(
    regions.catalog.x,
    regions.catalog.y,
    regions.catalog.w,
    catalogListH,
    cellHeight,
    cellWidth,
    pad,
    catalogScrollRow,
    catalog.entries.len,
  )
  let titleY = layout.titleY
  let catalogListY = layout.listY
  let stride = layout.stride
  let maxCatalogRows = layout.visibleRows
  let scrollRow = max(0, min(catalogScrollRow, max(0, catalog.entries.len - maxCatalogRows)))
  let visibleCount = min(catalog.entries.len - scrollRow, maxCatalogRows)

  ## Phase 1: every solid-color rect in one batch (backgrounds, selection, buttons).
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  if regions.catalog.w > 0:
    r.addRect(regions.catalog.x, regions.catalog.y, regions.catalog.w, regions.catalog.h, winWidth, winHeight, railBg)
    r.addRect(regions.catalog.x, regions.catalog.y, 1, regions.catalog.h, winWidth, winHeight, border)
    r.addRect(regions.catalog.x, regions.catalog.y + regions.catalog.h - 1, regions.catalog.w, 1, winWidth, winHeight, border)
  let centerPanel = contentBelowActionBar(regions.center, actionBarHeight)
  if centerPanel.w > 0 and centerPanel.h > 0:
    let centerBg = appChromeTheme.background.toRgba()
    r.addRect(centerPanel.x, centerPanel.y, centerPanel.w, centerPanel.h, winWidth, winHeight, centerBg)
    r.addRect(centerPanel.x, centerPanel.y, 1, centerPanel.h, winWidth, winHeight, border)
    r.addRect(centerPanel.x + centerPanel.w - 1, centerPanel.y, 1, centerPanel.h, winWidth, winHeight, border)
  if actionBarHeight > 0:
    let searchBar = actionBarRegionTop(regions.center, actionBarHeight)
    r.addRect(searchBar.x, searchBar.y, searchBar.w, searchBar.h, winWidth, winHeight, panelBg)
    let underline = if searchFocused: accent else: border
    r.addRect(searchBar.x, searchBar.y + searchBar.h - 1, searchBar.w, 1, winWidth, winHeight, underline)
    if searchFocused and searchCaretCol >= 0:
      let caretX = regions.center.x + pad + searchCaretCol * cellWidth
      r.addRect(caretX, regions.center.y + 6, 2, cellHeight, winWidth, winHeight, textColor)
  if regions.catalog.w > 0 and catalog.entries.len > 0:
    var rowY = catalogListY
    for local in 0 ..< visibleCount:
      let entryIndex = scrollRow + local
      if entryIndex == selectedIndex:
        r.addRect(layout.contentX, rowY - 2, layout.contentW, catalogRowHeight(cellHeight) + 4, winWidth, winHeight, selectedBg)
      rowY += stride
  const inspectLabel = "Inspect"
  var inspectBtn = overlay_lib.OverlayRect()
  if catalogFooterHeight > 0 and selectedIndex >= 0 and selectedIndex < catalog.entries.len and regions.catalog.w > 0:
    let footerY = regions.catalog.y + regions.catalog.h - catalogFooterHeight
    r.addRect(regions.catalog.x, footerY, regions.catalog.w, catalogFooterHeight, winWidth, winHeight, panelBg)
    r.addRect(regions.catalog.x, footerY, regions.catalog.w, 1, winWidth, winHeight, border)
    let btnW = button_lib.buttonPixelWidth(cellWidth, runeLen(inspectLabel), 10)
    let btnH = button_lib.buttonPixelHeight(cellHeight, 4)
    inspectBtn = overlay_lib.OverlayRect(
      x: regions.catalog.x + pad,
      y: footerY + max(0, (catalogFooterHeight - btnH) div 2),
      w: btnW,
      h: btnH,
    )
    r.addRect(inspectBtn.x, inspectBtn.y, inspectBtn.w, inspectBtn.h, winWidth, winHeight, selectedBg)
  if showScrollbar and scrollbarTrack.w > 0 and scrollbarTrack.h > 0:
    r.addRect(scrollbarTrack.x, scrollbarTrack.y, scrollbarTrack.w, scrollbarTrack.h, winWidth, winHeight, selectedBg)
    if scrollbarThumb.h > 0:
      r.addRect(scrollbarThumb.x, scrollbarThumb.y, scrollbarThumb.w, scrollbarThumb.h, winWidth, winHeight, muted)
  if layout.scrollable:
    r.addRect(regions.catalog.x + 1, layout.scrollUp.y, regions.catalog.w - 1, layout.scrollUp.h, winWidth, winHeight, panelBg)
    let bottomY = if catalogFooterHeight > 0: regions.catalog.y + regions.catalog.h - catalogFooterHeight else: regions.catalog.y + regions.catalog.h
    let rectH = max(0, bottomY - layout.scrollDown.y)
    r.addRect(regions.catalog.x + 1, layout.scrollDown.y, regions.catalog.w - 1, rectH, winWidth, winHeight, panelBg)
  r.finishBatch()

  ## Phase 2: prepare glyphs, then draw all chrome text in one batch.
  r.gpu.enableAlphaBlending()
  r.prepareChromeText("Installed")
  r.prepareChromeText(inspectLabel)
  r.prepareChromeText("Search registry...")
  if searchText.len > 0:
    r.prepareChromeText(searchText, 256)
  r.prepareChromeText("No widgets found in cg/")
  if layout.scrollable:
    r.prepareChromeText("▲")
    r.prepareChromeText("▼")
  for local in 0 ..< visibleCount:
    let entry = catalog.entries[scrollRow + local]
    let label = if entry.name.len > 0: entry.name else: entry.id
    r.prepareChromeText(label, layout.textCols)
    r.prepareChromeText(catalogListSubtitle(entry), layout.textCols)
  if r.chromeAtlas.isDirty:
    r.updateChromeAtlasTexture()

  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  let labelCols = if layout.textCols > 0: layout.textCols else: 1
  if regions.catalog.w > 0:
    r.addChromeText(regions.catalog.x + pad, titleY, winWidth, winHeight, "Installed", textColor, labelCols)
    var rowY = catalogListY
    if catalog.entries.len == 0:
      r.addChromeText(regions.catalog.x + pad, rowY, winWidth, winHeight, "No widgets found in cg/", muted, labelCols)
    else:
      for local in 0 ..< visibleCount:
        let entryIndex = scrollRow + local
        let entry = catalog.entries[entryIndex]
        let selected = entryIndex == selectedIndex
        let label = if entry.name.len > 0: entry.name else: entry.id
        let titleColor = catalogEntryTitleColor(entry, selected, textColor, muted, accent)
        r.addChromeText(layout.contentX, rowY, winWidth, winHeight, label, titleColor, labelCols)
        r.addChromeText(
          layout.contentX,
          rowY + r.chromeAtlas.cellHeight + 2,
          winWidth,
          winHeight,
          catalogListSubtitle(entry),
          muted,
          labelCols,
        )
        rowY += stride
    if layout.scrollable:
      block:
        let label = "▲"
        let textW = runeLen(label) * cellWidth
        let textX = layout.scrollUp.x + max(0, (layout.scrollUp.w - textW) div 2)
        let textY = layout.scrollUp.y + max(0, (layout.scrollUp.h - cellHeight) div 2)
        let color = if layout.showScrollUp: textColor else: chrome_theme.withAlpha(appChromeTheme.muted, 0.30).toRgba()
        r.addChromeText(textX, textY, winWidth, winHeight, label, color, 1)
      block:
        let label = "▼"
        let textW = runeLen(label) * cellWidth
        let textX = layout.scrollDown.x + max(0, (layout.scrollDown.w - textW) div 2)
        let bottomY = if catalogFooterHeight > 0: regions.catalog.y + regions.catalog.h - catalogFooterHeight else: regions.catalog.y + regions.catalog.h
        let rectH = max(0, bottomY - layout.scrollDown.y)
        let textY = layout.scrollDown.y + max(0, (rectH - cellHeight) div 2)
        let color = if layout.showScrollDown: textColor else: chrome_theme.withAlpha(appChromeTheme.muted, 0.30).toRgba()
        r.addChromeText(textX, textY, winWidth, winHeight, label, color, 1)
    if inspectBtn.w > 0:
      let btnRect = button_lib.buttonRect(inspectBtn.x, inspectBtn.y, inspectBtn.w, inspectBtn.h)
      let (textX, textY) = button_lib.centeredLabelOrigin(btnRect, cellWidth, cellHeight, runeLen(inspectLabel))
      r.addChromeText(textX, textY, winWidth, winHeight, inspectLabel, textColor, runeLen(inspectLabel))

  if actionBarHeight > 0:
    let barY = regions.center.y + 8
    if searchText.len == 0 and not searchFocused:
      r.addChromeText(regions.center.x + pad, barY, winWidth, winHeight, "Search registry...", muted, 48)
    elif searchText.len > 0:
      r.addChromeText(regions.center.x + pad, barY, winWidth, winHeight, searchText, textColor, 256)

  r.finishBatch()

proc drawContextMenu*(
    r: GpuTerminalRenderer,
    winWidth, winHeight: int,
    layout: menu_lib.MenuLayout,
    items: seq[menu_lib.MenuItem],
    highlighted: int,
) =
  if r == nil or layout.rect.w <= 0 or layout.rect.h <= 0:
    return
  let panelBg = appChromeTheme.panel.toRgba()
  let border = appChromeTheme.border.toRgba()
  let textColor = appChromeTheme.text.toRgba()
  let muted = appChromeTheme.muted.toRgba()
  let selectedBg = appChromeTheme.selection.toRgba()
  let cellHeight = r.chromeAtlas.cellHeight

  ## Phase 1: panel, hairline border, and the highlighted row background.
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(layout.rect.x, layout.rect.y, layout.rect.w, layout.rect.h, winWidth, winHeight, panelBg)
  r.addRect(layout.rect.x, layout.rect.y, layout.rect.w, 1, winWidth, winHeight, border)
  r.addRect(layout.rect.x, layout.rect.y + layout.rect.h - 1, layout.rect.w, 1, winWidth, winHeight, border)
  r.addRect(layout.rect.x, layout.rect.y, 1, layout.rect.h, winWidth, winHeight, border)
  r.addRect(layout.rect.x + layout.rect.w - 1, layout.rect.y, 1, layout.rect.h, winWidth, winHeight, border)
  if highlighted >= 0 and highlighted < items.len:
    let rowBg = menu_lib.menuRowBounds(layout, highlighted)
    r.addRect(rowBg.x, rowBg.y, rowBg.w, rowBg.h, winWidth, winHeight, selectedBg)
  r.finishBatch()

  ## Phase 2: row labels.
  r.gpu.enableAlphaBlending()
  for item in items:
    r.prepareChromeText(item.label, 64)
  if r.chromeAtlas.isDirty:
    r.updateChromeAtlasTexture()
  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  for i, item in items:
    let rowBg = menu_lib.menuRowBounds(layout, i)
    let textY = rowBg.y + max(0, (layout.rowHeight - cellHeight) div 2)
    let color = if item.enabled: textColor else: muted
    r.addChromeText(layout.rect.x + layout.padX, textY, winWidth, winHeight, item.label, color, 64)
  r.finishBatch()

proc drawToasts*(
    r: GpuTerminalRenderer,
    winWidth, winHeight: int,
    toasts: seq[toast_lib.Toast],
    now: float,
) =
  ## Stack transient toasts bottom-right, newest lowest, fading per opacity.
  if r == nil or toasts.len == 0:
    return
  let cellHeight = r.chromeAtlas.cellHeight
  let cellWidth = r.chromeAtlas.cellWidth
  const padX = 12
  const padY = 6
  const marginX = 16
  const marginBottom = 16
  const gap = 8
  let panel = appChromeTheme.panel
  let border = appChromeTheme.border
  let textColor = appChromeTheme.text
  var placed: seq[tuple[x, y, w, h: int; alpha: float; label: string]] = @[]
  var cursorY = winHeight - marginBottom
  for t in toasts:
    let alpha = toast_lib.toastAlpha(t, now)
    if alpha <= 0.0:
      continue
    let w = runeLen(t.text) * max(1, cellWidth) + padX * 2
    let h = cellHeight + padY * 2
    cursorY -= h
    let x = winWidth - marginX - w
    placed.add (x, cursorY, w, h, alpha, t.text)
    cursorY -= gap
  if placed.len == 0:
    return

  r.gpu.enableAlphaBlending()
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  for item in placed:
    r.addRect(item.x, item.y, item.w, item.h, winWidth, winHeight, panel.withAlpha(item.alpha).toRgba())
    let edge = border.withAlpha(item.alpha).toRgba()
    r.addRect(item.x, item.y, item.w, 1, winWidth, winHeight, edge)
    r.addRect(item.x, item.y + item.h - 1, item.w, 1, winWidth, winHeight, edge)
    r.addRect(item.x, item.y, 1, item.h, winWidth, winHeight, edge)
    r.addRect(item.x + item.w - 1, item.y, 1, item.h, winWidth, winHeight, edge)
  r.finishBatch()

  for item in placed:
    r.prepareChromeText(item.label, 128)
  if r.chromeAtlas.isDirty:
    r.updateChromeAtlasTexture()
  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  for item in placed:
    r.addChromeText(item.x + padX, item.y + padY, winWidth, winHeight, item.label,
                    textColor.withAlpha(item.alpha).toRgba(), 128)
  r.finishBatch()

proc drawModalOverlay*(
    r: GpuTerminalRenderer,
    winWidth, winHeight: int,
    layout: overlay_lib.ModalChromeLayout,
    panel: overlay_lib.OverlayPanel,
) =
  if r == nil or layout.panel.w <= 0 or layout.panel.h <= 0:
    return
  let dim = appChromeTheme.overlayDim.toRgba()
  let panelBg = appChromeTheme.panel.toRgba()
  let buttonBg = appChromeTheme.selection.toRgba()
  let accent = appChromeTheme.accent.toRgba()
  let textColor = appChromeTheme.text.toRgba()
  let muted = appChromeTheme.muted.toRgba()
  let border = appChromeTheme.border.toRgba()
  let cellHeight = r.chromeAtlas.cellHeight
  let cellWidth = r.chromeAtlas.cellWidth

  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  if layout.backdrop.w > 0 and layout.backdrop.h > 0:
    r.addRect(
      layout.backdrop.x, layout.backdrop.y, layout.backdrop.w, layout.backdrop.h,
      winWidth, winHeight, dim,
    )
  r.addRect(layout.panel.x, layout.panel.y, layout.panel.w, layout.panel.h, winWidth, winHeight, panelBg)
  r.addRect(layout.panel.x, layout.panel.y, layout.panel.w, 2, winWidth, winHeight, accent)
  r.addRect(layout.panel.x, layout.panel.y + layout.panel.h - 1, layout.panel.w, 1, winWidth, winHeight, border)
  for btn in layout.buttons:
    r.addRect(btn.x, btn.y, btn.w, btn.h, winWidth, winHeight, buttonBg)
  r.finishBatch()

  r.gpu.enableAlphaBlending()
  r.prepareChromeText(panel.title, layout.titleCols)
  r.prepareChromeText(panel.body, layout.bodyCols)
  for btn in panel.buttons:
    r.prepareChromeText(btn.label)
  if r.chromeAtlas.isDirty:
    r.updateChromeAtlasTexture()

  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  if panel.title.len > 0:
    r.addChromeText(
      layout.panel.x + 16, layout.titleY, winWidth, winHeight,
      panel.title, textColor, layout.titleCols,
    )
  if panel.body.len > 0:
    r.addChromeText(
      layout.panel.x + 16, layout.bodyY, winWidth, winHeight,
      panel.body, muted, layout.bodyCols,
    )
  for i, btn in layout.buttons:
    if i >= panel.buttons.len:
      break
    let label = panel.buttons[i].label
    let (textX, textY) = centeredLabelOrigin(btn, cellWidth, cellHeight, label)
    r.addChromeText(textX, textY, winWidth, winHeight, label, textColor, runeLen(label))
  r.finishBatch()

func syntaxTokenColor(kind: syntax_viewport.SourceTokenKind): RgbaColor =
  case kind
  of syntax_viewport.tvComment:
    tile_batcher_lib.rgba(0.45, 0.58, 0.48, 1.0)
  of syntax_viewport.tvString:
    tile_batcher_lib.rgba(0.55, 0.78, 0.52, 1.0)
  of syntax_viewport.tvNumber:
    tile_batcher_lib.rgba(0.82, 0.62, 0.42, 1.0)
  of syntax_viewport.tvKeyword:
    tile_batcher_lib.rgba(0.62, 0.72, 0.95, 1.0)
  of syntax_viewport.tvType:
    tile_batcher_lib.rgba(0.52, 0.82, 0.86, 1.0)
  of syntax_viewport.tvOperator:
    tile_batcher_lib.rgba(0.95, 0.76, 0.23, 1.0)
  else:
    tile_batcher_lib.rgba(0.88, 0.91, 0.92, 1.0)

proc drawExplorerOverlay*(
    r: GpuTerminalRenderer,
    winWidth, winHeight: int,
    layout: overlay_lib.ExplorerChromeLayout,
    title: string,
    treeLayout: scroll_tree.ScrollTreeLayout,
    treeRows: openArray[scroll_tree.TreeRowView],
    codeViewport: syntax_viewport.SourceViewport,
    previewPath: string,
    selectedTreeRowId: int = -1,
) =
  if r == nil or layout.panel.w <= 0 or layout.panel.h <= 0:
    return
  let dim = appChromeTheme.overlayDim.toRgba()
  let panelBg = appChromeTheme.panel.toRgba()
  let paneBg = appChromeTheme.surface.toRgba()
  let accent = appChromeTheme.accent.toRgba()
  let textColor = appChromeTheme.text.toRgba()
  let muted = appChromeTheme.muted.toRgba()
  let border = appChromeTheme.border.toRgba()
  let selectedBg = appChromeTheme.selection.toRgba()
  let cellHeight = r.chromeAtlas.cellHeight
  let cellWidth = r.chromeAtlas.cellWidth

  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  if layout.backdrop.w > 0 and layout.backdrop.h > 0:
    r.addRect(
      layout.backdrop.x, layout.backdrop.y, layout.backdrop.w, layout.backdrop.h,
      winWidth, winHeight, dim,
    )
  r.addRect(layout.panel.x, layout.panel.y, layout.panel.w, layout.panel.h, winWidth, winHeight, panelBg)
  r.addRect(layout.panel.x, layout.panel.y, layout.panel.w, 2, winWidth, winHeight, accent)
  r.addRect(layout.panel.x, layout.panel.y + layout.panel.h - 1, layout.panel.w, 1, winWidth, winHeight, border)
  if layout.treePane.w > 0 and layout.treePane.h > 0:
    r.addRect(layout.treePane.x, layout.treePane.y, layout.treePane.w, layout.treePane.h, winWidth, winHeight, paneBg)
    r.addRect(layout.treePane.x + layout.treePane.w - 1, layout.treePane.y, 1, layout.treePane.h, winWidth, winHeight, border)
  if layout.codePane.w > 0 and layout.codePane.h > 0:
    r.addRect(layout.codePane.x, layout.codePane.y, layout.codePane.w, layout.codePane.h, winWidth, winHeight, paneBg)
  let visibleTreeRows = min(treeLayout.visibleRows, max(0, treeRows.len - treeLayout.scrollRow))
  if layout.treePane.w > 0:
    for local in 0 ..< visibleTreeRows:
      let rowIndex = treeLayout.scrollRow + local
      if rowIndex >= treeRows.len:
        break
      let row = treeRows[rowIndex]
      if row.rowId == selectedTreeRowId:
        let rowY = scroll_tree.treeRowY(treeLayout, local)
        r.addRect(
          treeLayout.listX, rowY - 1, treeLayout.contentW, treeLayout.stride,
          winWidth, winHeight, selectedBg,
        )
  r.finishBatch()

  r.gpu.enableAlphaBlending()
  r.prepareChromeText(title, layout.titleCols)
  if previewPath.len > 0:
    r.prepareChromeText(splitPath(previewPath).tail, 64)
  if treeLayout.showScrollUp:
    r.prepareChromeText("▲")
  if treeLayout.showScrollDown:
    r.prepareChromeText("▼")
  for local in 0 ..< visibleTreeRows:
    let rowIndex = treeLayout.scrollRow + local
    if rowIndex >= treeRows.len:
      break
    let row = treeRows[rowIndex]
    if row.isBranch:
      r.prepareChromeText(if row.expanded: "▼" else: "▶")
    r.prepareChromeText(row.label, scroll_tree.treeRowLabelCols(treeLayout, row.depth))
  if codeViewport.lines.len == 0:
    r.prepareChromeText("Select a file to preview", 48)
  else:
    for line in codeViewport.lines:
      for run in line.runs:
        if run.text.len > 0:
          r.prepareChromeText(run.text)
  if r.chromeAtlas.isDirty:
    r.updateChromeAtlasTexture()

  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  if title.len > 0:
    r.addChromeText(
      layout.panel.x + 14, layout.titleY, winWidth, winHeight,
      title, textColor, layout.titleCols,
    )
  if previewPath.len > 0 and layout.codePane.w > 0:
    let pathLabel = splitPath(previewPath).tail
    r.addChromeText(
      layout.codePane.x + 8, layout.treePane.y - cellHeight - 2, winWidth, winHeight,
      pathLabel, muted, min(64, layout.codePane.w div max(1, cellWidth)),
    )
  if layout.treePane.w > 0:
    if treeLayout.showScrollUp:
      let upX = treeLayout.scrollUp.x + (treeLayout.scrollUp.w - cellWidth) div 2
      let upY = treeLayout.scrollUp.y + max(1, (treeLayout.scrollUp.h - cellHeight) div 2)
      r.addChromeText(upX, upY, winWidth, winHeight, "▲", accent, 1)
    if treeLayout.showScrollDown:
      let downX = treeLayout.scrollDown.x + (treeLayout.scrollDown.w - cellWidth) div 2
      let downY = treeLayout.scrollDown.y + max(1, treeLayout.scrollDown.h - cellHeight - 1)
      r.addChromeText(downX, downY, winWidth, winHeight, "▼", accent, 1)
    for local in 0 ..< visibleTreeRows:
      let rowIndex = treeLayout.scrollRow + local
      if rowIndex >= treeRows.len:
        break
      let row = treeRows[rowIndex]
      let rowY = scroll_tree.treeRowY(treeLayout, local)
      if row.isBranch:
        let toggleX = treeLayout.listX + row.depth * treeLayout.indentCols * cellWidth
        let glyph = if row.expanded: "▼" else: "▶"
        r.addChromeText(toggleX, rowY, winWidth, winHeight, glyph, muted, 1)
      let labelX = scroll_tree.treeRowLabelX(treeLayout, row.depth, cellWidth)
      let labelCols = scroll_tree.treeRowLabelCols(treeLayout, row.depth)
      let rowColor = if row.rowId == selectedTreeRowId: textColor else: muted
      r.addChromeText(labelX, rowY, winWidth, winHeight, row.label, rowColor, labelCols)
  if layout.codePane.w > 0:
    var lineY = layout.codePane.y + 8
    if codeViewport.lines.len == 0:
      r.addChromeText(
        layout.codePane.x + 8, lineY, winWidth, winHeight,
        "Select a file to preview", muted, 48,
      )
    else:
      let maxLineY = layout.codePane.y + layout.codePane.h - 8
      for line in codeViewport.lines:
        if lineY + cellHeight > maxLineY:
          break
        var colX = layout.codePane.x + 8
        for run in line.runs:
          if run.text.len == 0:
            continue
          let maxCols = max(0, (layout.codePane.x + layout.codePane.w - colX - 8) div cellWidth)
          if maxCols <= 0:
            break
          let drawLen = min(run.text.runeLen, maxCols)
          let drawText = run.text.runeSubstr(0, drawLen)
          r.addChromeText(colX, lineY, winWidth, winHeight, drawText, syntaxTokenColor(run.kind), drawLen)
          colX += drawLen * cellWidth
        lineY += cellHeight
  r.finishBatch()

proc drawWorkspacePlaceholder*(
    r: GpuTerminalRenderer,
    winWidth, winHeight, headerHeight: int,
) =
  if winWidth <= 0 or winHeight <= 0:
    return
  let panelBg = tile_batcher_lib.rgba(0.10, 0.12, 0.16, 1.0)
  let accent = tile_batcher_lib.rgba(0.95, 0.76, 0.23, 1.0)
  let text = tile_batcher_lib.rgba(0.88, 0.91, 0.92, 1.0)
  let muted = tile_batcher_lib.rgba(0.58, 0.63, 0.67, 1.0)
  let pad = 24
  let top = headerHeight + pad
  let panelW = max(120, winWidth - pad * 2)
  let panelH = max(80, winHeight - top - pad)

  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(pad, top, panelW, panelH, winWidth, winHeight, panelBg)
  r.addRect(pad, top, panelW, 3, winWidth, winHeight, accent)
  r.finishBatch()

  r.gpu.enableAlphaBlending()
  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  let lineY = top + 20
  r.prepareChromeText("Cartograph Workspace")
  r.prepareChromeText("Terminal panes embed in center column.")
  r.prepareChromeText("Ctrl+Shift+A or header toggle -> Terminal")
  if r.chromeAtlas.isDirty:
    r.updateChromeAtlasTexture()
  r.addChromeText(pad + 16, lineY, winWidth, winHeight, "Cartograph Workspace", text, 32)
  r.addChromeText(
    pad + 16,
    lineY + r.chromeAtlas.cellHeight + 8,
    winWidth,
    winHeight,
    "Waymark engine. Terminal panes embed in center column.",
    muted,
    48,
  )
  r.addChromeText(
    pad + 16,
    lineY + (r.chromeAtlas.cellHeight + 8) * 2,
    winWidth,
    winHeight,
    "Ctrl+Shift+A or header toggle -> Terminal",
    muted,
    56,
  )
  r.finishBatch()

proc drawPaneBorder*(r: GpuTerminalRenderer, x, y, w, h, winWidth, winHeight: int, active: bool) =
  if w <= 0 or h <= 0: return
  let border =
    if active: tile_batcher_lib.rgba(0.95, 0.76, 0.23, 1.0)
    else: tile_batcher_lib.rgba(0.16, 0.19, 0.22, 1.0)
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(x, y, w, 1, winWidth, winHeight, border)
  r.addRect(x, y + h - 1, w, 1, winWidth, winHeight, border)
  r.addRect(x, y, 1, h, winWidth, winHeight, border)
  r.addRect(x + w - 1, y, 1, h, winWidth, winHeight, border)
  r.finishBatch()

proc drawPaneBackground*(r: GpuTerminalRenderer, t: Terminal, x, y, w, h, winWidth, winHeight: int) =
  if w <= 0 or h <= 0: return
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(x, y, w, h, winWidth, winHeight, toRgba(t.screen.theme.background))
  r.finishBatch()

proc prepareVisibleGlyphs(r: GpuTerminalRenderer, t: Terminal) =
  let s = t.screen
  let rows = max(1, t.viewport.height)
  let cols = s.cols
  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      if cell.width != 0 and cell.rune > 32:
        discard r.atlas.getGlyph(cell.rune)

proc drawInRect*(r: GpuTerminalRenderer, t: Terminal, winWidth, winHeight: int, x, y, w, h: int, showCursor = true) =
  ## Optimized single-pass rendering.
  if w <= 0 or h <= 0: return
  let s = t.screen; let theme = s.theme
  let rows = max(1, t.viewport.height); let cols = s.cols

  # Pre-calculate
  let defaultBg = toRenderColor(theme.background)
  let defaultFg = toRenderColor(theme.foreground)
  let tBg = toRgba(defaultBg)
  let tCursor = toRgba(theme.cursor)
  var tAnsi: array[16, render_attrs.RenderColor]
  for i in 0..15: tAnsi[i] = toRenderColor(theme.ansi[i])

  let cw = float32(r.atlas.cellWidth); let ch = float32(r.atlas.cellHeight)
  let sw = float32(winWidth); let sh = float32(winHeight)
  let tw = (cw / sw) * 2.0; let th = (ch / sh) * 2.0

  r.prepareVisibleGlyphs(t)
  if r.atlas.isDirty:
    r.updateAtlasTexture()

  r.gpu.enableAlphaBlending()

  # --- ONE PASS FOR ALL BACKGROUNDS ---
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(x, y, w, h, winWidth, winHeight, tBg)

  let cvr = t.viewport.bufferToViewport(s.absoluteCursorRow())
  var visibleRowTexts = newSeq[string](rows)
  for row in 0 ..< rows:
    visibleRowTexts[row] = s.absoluteLineText(t.viewport.viewportToBuffer(row))
  let composerHighlight = defaultComposerHighlightStyle()
  let composerRects = codexPromptHighlightRects(
    visibleRowTexts,
    cellHeight = r.atlas.cellHeight,
    viewport = PixelRect(x: x, y: y, w: w, h: h),
    cursorVisible = s.cursor.visible and not s.cursor.pendingWrap,
    style = composerHighlight,
  )
  for rect in composerRects:
    r.addRect(rect.x, rect.y, rect.w, rect.h, winWidth, winHeight, toRgba(composerHighlight.color))

  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    let py = ndcY(y + row * r.atlas.cellHeight, winHeight)
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      let resolved = render_attrs.resolveRenderAttrs(toRenderAttrs(cell.attrs), defaultFg, defaultBg, tAnsi)
      if resolved.drawBackground:
        r.batcher.addTile(ndcX(x + col * r.atlas.cellWidth, winWidth), py, tw*float32(max(1, int(cell.width))), th, 0, 0, 1, 1, toRgba(resolved.background))
  # Cursor
  if showCursor and cvr != -1 and s.cursor.visible and not s.cursor.pendingWrap:
    let cursorX = x + s.cursor.col * r.atlas.cellWidth
    let cursorY = y + cvr * r.atlas.cellHeight
    case s.cursor.style
    of csBlock:
      r.batcher.addTile(ndcX(cursorX, winWidth), ndcY(cursorY, winHeight), tw, th, 0, 0, 1, 1, tCursor)
    of csUnderline:
      let linePx = max(1, r.atlas.cellHeight div 8)
      r.batcher.addTile(ndcX(cursorX, winWidth), ndcY(cursorY + r.atlas.cellHeight - linePx, winHeight), tw, ndcH(linePx, winHeight), 0, 0, 1, 1, tCursor)
    of csBar:
      let barPx = max(1, r.atlas.cellWidth div 8)
      r.batcher.addTile(ndcX(cursorX, winWidth), ndcY(cursorY, winHeight), ndcW(barPx, winWidth), th, 0, 0, 1, 1, tCursor)

  # --- PASS 1.5: SELECTION HIGHLIGHT & LINKS ---
  if t.selection.isActive:
    let tSel = toRgba(theme.selection)
    for sp in t.selection.spans(cols):
      let vRow = t.viewport.bufferToViewport(sp.row)
      if vRow != -1:
        let contentEnd = min(cols, s.absoluteContentLen(sp.row))
        let startCol = max(0, min(sp.startCol, contentEnd))
        let endCol = max(startCol, min(sp.endCol, contentEnd))
        if startCol >= endCol: continue
        let px = ndcX(x + startCol * r.atlas.cellWidth, winWidth)
        let py = ndcY(y + vRow * r.atlas.cellHeight, winHeight)
        r.batcher.addTile(px, py, tw * float32(endCol - startCol), th, 0, 0, 1, 1, tSel)

  if t.activeLink.isSome:
    let al = t.activeLink.get()
    let vRow = t.viewport.bufferToViewport(al.row)
    if vRow != -1:
      let px = ndcX(x + al.startCol * r.atlas.cellWidth, winWidth)
      # Draw a thin line at the bottom of the cell (y offset)
      let lineTh = th * 0.05
      let py = ndcY(y + vRow * r.atlas.cellHeight, winHeight) - (th - lineTh)
      r.batcher.addTile(px, py, tw * float32(al.endCol - al.startCol), lineTh, 0, 0, 1, 1, tCursor)

  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      if cell.width == 0: continue
      let flags = cell.attrs.flags
      let hasUnderline = afUnderline in flags and cell.attrs.underlineStyle != usNone
      let drawLinkUnderline = cell.linkId != 0
      ## Spaces still get underlines/overlines/strikes when attributes demand it.
      if cell.rune == uint32(' ') and not hasUnderline and not drawLinkUnderline and
          afStrike notin flags and afOverline notin flags:
        continue
      if not hasUnderline and not drawLinkUnderline and afStrike notin flags and afOverline notin flags:
        continue
      let resolved = render_attrs.resolveRenderAttrs(toRenderAttrs(cell.attrs), defaultFg, defaultBg, tAnsi)
      let color = toRgba(resolved.foreground)
      let linkColor = tile_batcher_lib.rgba(0.45, 0.70, 1.0, 1.0)
      let cellPx = col * r.atlas.cellWidth
      let cellPy = row * r.atlas.cellHeight
      let cellW = r.atlas.cellWidth * max(1, int(cell.width))
      let cellH = r.atlas.cellHeight
      let linePx = underline_deco.underlineThickness(cellH)
      let lineH = ndcH(linePx, winHeight)
      let lineW = tw * float32(max(1, int(cell.width)))
      let px = ndcX(x + cellPx, winWidth)

      if hasUnderline or drawLinkUnderline:
        let kind =
          if hasUnderline:
            case cell.attrs.underlineStyle
            of usNone: underline_deco.ukNone
            of usSingle: underline_deco.ukSingle
            of usDouble: underline_deco.ukDouble
            of usCurly: underline_deco.ukCurly
            of usDotted: underline_deco.ukDotted
            of usDashed: underline_deco.ukDashed
          else:
            underline_deco.ukSingle
        let ulColor =
          if drawLinkUnderline and not hasUnderline: linkColor
          else: color
        let segs = underline_deco.underlineSegments(
          kind,
          cellX = x + cellPx,
          cellY = y + cellPy,
          cellW = cellW,
          cellH = cellH,
          thickness = linePx,
        )
        for seg in segs:
          r.batcher.addTile(
            ndcX(seg.x, winWidth),
            ndcY(seg.y, winHeight),
            ndcW(seg.w, winWidth),
            ndcH(seg.h, winHeight),
            0, 0, 1, 1, ulColor,
          )
      if afStrike in flags and cell.rune != uint32(' '):
        r.batcher.addTile(px, ndcY(y + cellPy + (cellH div 2), winHeight), lineW, lineH, 0, 0, 1, 1, color)
      if afOverline in flags:
        r.batcher.addTile(px, ndcY(y + cellPy, winHeight), lineW, lineH, 0, 0, 1, 1, color)

  r.finishBatch()

  # --- ONE PASS FOR ALL GLYPHS ---
  r.batcher.textureId = r.atlasTexId
  r.batcher.beginBatch()
  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    let py = ndcY(y + row * r.atlas.cellHeight, winHeight)
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      if cell.rune > 32:
        let glyph = r.atlas.getGlyph(cell.rune)
        let resolved = render_attrs.resolveRenderAttrs(toRenderAttrs(cell.attrs), defaultFg, defaultBg, tAnsi)
        let color = toRgba(resolved.foreground)
        r.batcher.addTile(ndcX(x + col * r.atlas.cellWidth, winWidth), py, tw, th, glyph.uvMin.x, glyph.uvMin.y, glyph.uvMax.x, glyph.uvMax.y, color)
  r.finishBatch()
  r.gpu.flush()
  t.damage.clear()

proc draw*(r: GpuTerminalRenderer, t: Terminal, winWidth, winHeight: int, topOffsetPx: int = 0) =
  r.drawInRect(t, winWidth, winHeight, 0, topOffsetPx, winWidth, max(1, winHeight - topOffsetPx))
