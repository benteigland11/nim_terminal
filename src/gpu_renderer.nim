## GPU-accelerated terminal grid renderer.
##
## Translates the in-memory `Screen` buffer into OpenGL quads.
## Uses `TileBatcher` for efficiency and `GlyphAtlas` for UV mapping.

import opengl
import pixie
import std/options
import ../cg/data_screen_buffer_nim/src/screen_buffer_lib
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
import ../cg/universal_tile_batcher_nim/src/tile_batcher_lib
import ../cg/universal_tab_set_nim/src/tab_set_lib
import ../cg/data_terminal_render_attrs_nim/src/terminal_render_attrs_lib as render_attrs
import terminal

type
  GpuTerminalRenderer* = ref object
    atlas*: GlyphAtlas
    chromeAtlas*: GlyphAtlas
    batcher*: TileBatcher
    atlasTexId*: uint32
    chromeTexId*: uint32
    bgTexId*: uint32      ## 1x1 white texture for drawing backgrounds
    logoTexId*: uint32
    logoAspect*: float32

proc uploadAtlasTexture(atlas: GlyphAtlas, texId: uint32) =
  glBindTexture(GL_TEXTURE_2D, texId)
  let img = atlas.atlasImage
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, cint(img.width), cint(img.height),
               0, GL_RGBA, GL_UNSIGNED_BYTE, addr img.data[0])
  atlas.isDirty = false

proc updateAtlasTexture*(r: GpuTerminalRenderer) =
  if not r.atlas.isDirty: return
  uploadAtlasTexture(r.atlas, r.atlasTexId)

proc updateChromeAtlasTexture*(r: GpuTerminalRenderer) =
  if not r.chromeAtlas.isDirty: return
  uploadAtlasTexture(r.chromeAtlas, r.chromeTexId)

proc loadLogoTexture*(r: GpuTerminalRenderer, path: string) =
  try:
    let img = readImage(path)
    if img.width <= 0 or img.height <= 0 or img.data.len == 0: return
    var id: uint32
    glGenTextures(1, addr id)
    glBindTexture(GL_TEXTURE_2D, id)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, cint(img.width), cint(img.height),
                 0, GL_RGBA, GL_UNSIGNED_BYTE, addr img.data[0])
    r.logoTexId = id
    r.logoAspect = img.width.float32 / img.height.float32
  except CatchableError:
    r.logoTexId = 0
    r.logoAspect = 1.0

func toRgba(c: PaletteColor): RgbaColor =
  tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

func toRgba(c: render_attrs.RenderColor): RgbaColor =
  tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

func toRenderColor(c: PaletteColor): render_attrs.RenderColor =
  render_attrs.rgb(c.r, c.g, c.b)

func toTerminalColor(c: screen_buffer_lib.Color): render_attrs.TerminalColor =
  case c.kind
  of screen_buffer_lib.ckDefault:
    render_attrs.defaultColor()
  of screen_buffer_lib.ckIndexed:
    render_attrs.indexedColor(c.index)
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
  r.updateChromeAtlasTexture()

proc newGpuTerminalRenderer*(atlas: GlyphAtlas, chromeAtlas: GlyphAtlas = nil): GpuTerminalRenderer =
  var ids: array[3, uint32]
  glGenTextures(3, addr ids[0])
  glBindTexture(GL_TEXTURE_2D, ids[0])
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
  glBindTexture(GL_TEXTURE_2D, ids[1])
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
  glBindTexture(GL_TEXTURE_2D, ids[2])
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
  var whitePixel: uint32 = 0xFFFFFFFF'u32
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr whitePixel)

  result = GpuTerminalRenderer(
    atlas: atlas,
    chromeAtlas: if chromeAtlas == nil: atlas else: chromeAtlas,
    batcher: newTileBatcher(ids[0], capacity = 100000),
    atlasTexId: ids[0],
    chromeTexId: ids[1],
    bgTexId: ids[2],
    logoTexId: 0,
    logoAspect: 1.0
  )
  result.preRenderAscii()
  result.preRenderChromeAscii()

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
  for ch in text:
    if col >= maxChars: break
    let glyph = r.chromeAtlas.getGlyph(uint32(ch))
    r.batcher.addTile(
      ndcX(x + col * r.chromeAtlas.cellWidth, winWidth),
      ndcY(y, winHeight),
      ndcW(r.chromeAtlas.cellWidth, winWidth),
      ndcH(r.chromeAtlas.cellHeight, winHeight),
      glyph.uvMin.x, glyph.uvMin.y, glyph.uvMax.x, glyph.uvMax.y,
      color
    )
    inc col

proc drawChrome*(r: GpuTerminalRenderer, tabs: TabSet, winWidth, winHeight, titleBarHeight, tabBarHeight: int, title = "Waymark - Built with Nim") =
  if winWidth <= 0 or winHeight <= 0 or titleBarHeight <= 0 or tabBarHeight <= 0: return

  let headerHeight = titleBarHeight + tabBarHeight
  let titleBg = tile_batcher_lib.rgba(0.11, 0.12, 0.13, 1.0)
  let bg = tile_batcher_lib.rgba(0.07, 0.08, 0.09, 1.0)
  let border = tile_batcher_lib.rgba(0.24, 0.28, 0.32, 1.0)
  let nimYellow = tile_batcher_lib.rgba(0.95, 0.76, 0.23, 1.0)
  let activeBg = tile_batcher_lib.rgba(0.16, 0.18, 0.20, 1.0)
  let inactiveBg = tile_batcher_lib.rgba(0.10, 0.11, 0.12, 1.0)
  let closeBg = tile_batcher_lib.rgba(0.20, 0.22, 0.24, 1.0)
  let text = tile_batcher_lib.rgba(0.88, 0.91, 0.92, 1.0)
  let muted = tile_batcher_lib.rgba(0.58, 0.63, 0.67, 1.0)

  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(0, 0, winWidth, titleBarHeight, winWidth, winHeight, titleBg)
  r.addRect(0, titleBarHeight - 1, winWidth, 1, winWidth, winHeight, nimYellow)
  r.addRect(0, titleBarHeight, winWidth, tabBarHeight, winWidth, winHeight, bg)
  r.addRect(0, headerHeight - 1, winWidth, 1, winWidth, winHeight, border)

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
  r.batcher.endBatch()

  let logoX = 10
  let logoH = max(14, min(titleBarHeight - 8, 24))
  let logoW = max(14, int(float32(logoH) * r.logoAspect))
  let logoY = max(3, (titleBarHeight - logoH) div 2)
  if r.logoTexId != 0:
    r.batcher.textureId = r.logoTexId
    r.batcher.beginBatch()
    r.batcher.addTile(
      ndcX(logoX, winWidth), ndcY(logoY, winHeight),
      ndcW(logoW, winWidth), ndcH(logoH, winHeight),
      0, 0, 1, 1,
      tile_batcher_lib.rgba(1, 1, 1, 1),
    )
    r.batcher.endBatch()

  r.batcher.textureId = r.chromeTexId
  r.batcher.beginBatch()
  let titleTextY = max(1, (titleBarHeight - r.chromeAtlas.cellHeight) div 2)
  let titleTextX = if r.logoTexId != 0: logoX + logoW + 10 else: logoX
  let titleCols = max(0, (winWidth - titleTextX - 12) div max(1, r.chromeAtlas.cellWidth))
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
  r.batcher.endBatch()

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
  r.batcher.endBatch()

proc drawPaneBackground*(r: GpuTerminalRenderer, t: Terminal, x, y, w, h, winWidth, winHeight: int) =
  if w <= 0 or h <= 0: return
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(x, y, w, h, winWidth, winHeight, toRgba(t.screen.theme.background))
  r.batcher.endBatch()

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

  glEnable(GL_TEXTURE_2D); glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

  # --- ONE PASS FOR ALL BACKGROUNDS ---
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(x, y, w, h, winWidth, winHeight, tBg)

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
  let cvr = t.viewport.bufferToViewport(s.absoluteCursorRow())
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
      if cell.rune == uint32(' '): continue
      let flags = cell.attrs.flags
      let drawSingleUnderline = afUnderline in flags and cell.attrs.underlineStyle == usSingle
      if not drawSingleUnderline and afStrike notin flags and afOverline notin flags: continue
      let resolved = render_attrs.resolveRenderAttrs(toRenderAttrs(cell.attrs), defaultFg, defaultBg, tAnsi)
      let color = toRgba(resolved.foreground)
      let px = ndcX(x + col * r.atlas.cellWidth, winWidth)
      let lineW = tw * float32(max(1, int(cell.width)))
      let linePx = max(1, r.atlas.cellHeight div 14)
      let lineH = ndcH(linePx, winHeight)
      if drawSingleUnderline:
        r.batcher.addTile(px, ndcY(y + row * r.atlas.cellHeight + r.atlas.cellHeight - linePx, winHeight), lineW, lineH, 0, 0, 1, 1, color)
      if afStrike in flags:
        r.batcher.addTile(px, ndcY(y + row * r.atlas.cellHeight + (r.atlas.cellHeight div 2), winHeight), lineW, lineH, 0, 0, 1, 1, color)
      if afOverline in flags:
        r.batcher.addTile(px, ndcY(y + row * r.atlas.cellHeight, winHeight), lineW, lineH, 0, 0, 1, 1, color)

  r.batcher.endBatch()

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
  r.batcher.endBatch()
  glFlush()
  t.damage.clear()

proc draw*(r: GpuTerminalRenderer, t: Terminal, winWidth, winHeight: int, topOffsetPx: int = 0) =
  r.drawInRect(t, winWidth, winHeight, 0, topOffsetPx, winWidth, max(1, winHeight - topOffsetPx))
