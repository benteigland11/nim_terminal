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
import ../cg/universal_color_palette_nim/src/color_palette_lib
import ../cg/universal_tab_set_nim/src/tab_set_lib
import terminal

type
  GpuTerminalRenderer* = ref object
    atlas*: GlyphAtlas
    batcher*: TileBatcher
    atlasTexId*: uint32
    bgTexId*: uint32      ## 1x1 white texture for drawing backgrounds

proc updateAtlasTexture*(r: GpuTerminalRenderer) =
  if not r.atlas.isDirty: return
  glBindTexture(GL_TEXTURE_2D, r.atlasTexId)
  let img = r.atlas.atlasImage
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, cint(img.width), cint(img.height),
               0, GL_RGBA, GL_UNSIGNED_BYTE, addr img.data[0])
  r.atlas.isDirty = false

func toRgba(c: PaletteColor): RgbaColor =
  tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

func toRgba(c: color_palette_lib.RgbColor): RgbaColor =
  tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

func resolveColor(c: screen_buffer_lib.Color, tAnsi: array[16, RgbaColor]): RgbaColor =
  case c.kind
  of screen_buffer_lib.ckDefault: tile_batcher_lib.rgba(0, 0, 0, 0)
  of screen_buffer_lib.ckIndexed:
    if c.index < 16: return tAnsi[c.index]
    else: return toRgba(getXterm256Color(uint8(c.index)))
  of screen_buffer_lib.ckRgb:
    return tile_batcher_lib.rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

proc preRenderAscii*(r: GpuTerminalRenderer) =
  for i in 32..126: discard r.atlas.getGlyph(uint32(i))
  r.updateAtlasTexture()

proc newGpuTerminalRenderer*(atlas: GlyphAtlas): GpuTerminalRenderer =
  var ids: array[2, uint32]
  glGenTextures(2, addr ids[0])
  glBindTexture(GL_TEXTURE_2D, ids[0])
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  glBindTexture(GL_TEXTURE_2D, ids[1])
  var whitePixel: uint32 = 0xFFFFFFFF'u32
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr whitePixel)

  result = GpuTerminalRenderer(
    atlas: atlas,
    batcher: newTileBatcher(ids[0], capacity = 100000),
    atlasTexId: ids[0],
    bgTexId: ids[1]
  )
  result.preRenderAscii()

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

proc addText(r: GpuTerminalRenderer, x, y, winWidth, winHeight: int, text: string, color: RgbaColor, maxChars: int = int.high) =
  var col = 0
  for ch in text:
    if col >= maxChars: break
    let glyph = r.atlas.getGlyph(uint32(ch))
    r.batcher.addTile(
      ndcX(x + col * r.atlas.cellWidth, winWidth),
      ndcY(y, winHeight),
      ndcW(r.atlas.cellWidth, winWidth),
      ndcH(r.atlas.cellHeight, winHeight),
      glyph.uvMin.x, glyph.uvMin.y, glyph.uvMax.x, glyph.uvMax.y,
      color
    )
    inc col

proc drawChrome*(r: GpuTerminalRenderer, tabs: TabSet, winWidth, winHeight, headerHeight: int) =
  if winWidth <= 0 or winHeight <= 0 or headerHeight <= 0: return

  let bg = tile_batcher_lib.rgba(0.07, 0.08, 0.09, 1.0)
  let border = tile_batcher_lib.rgba(0.24, 0.28, 0.32, 1.0)
  let activeBg = tile_batcher_lib.rgba(0.16, 0.18, 0.20, 1.0)
  let inactiveBg = tile_batcher_lib.rgba(0.10, 0.11, 0.12, 1.0)
  let closeBg = tile_batcher_lib.rgba(0.20, 0.22, 0.24, 1.0)
  let text = tile_batcher_lib.rgba(0.88, 0.91, 0.92, 1.0)
  let muted = tile_batcher_lib.rgba(0.58, 0.63, 0.67, 1.0)

  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.addRect(0, 0, winWidth, headerHeight, winWidth, winHeight, bg)
  r.addRect(0, headerHeight - 1, winWidth, 1, winWidth, winHeight, border)

  let plusWidth = max(32, headerHeight)
  let tabCount = max(1, tabs.tabs.len)
  let canClose = tabs.tabs.len > 1
  let tabAreaWidth = max(0, winWidth - plusWidth)
  let tabWidth = if tabs.tabs.len == 0: tabAreaWidth else: max(12, tabAreaWidth div tabCount)

  for i, tab in tabs.tabs:
    let x = i * tabWidth
    if x >= tabAreaWidth: break
    let w = min(tabWidth, tabAreaWidth - x)
    let isActive = tabs.activeId.isSome and tabs.activeId.get() == tab.id
    r.addRect(x, 2, w, headerHeight - 3, winWidth, winHeight, if isActive: activeBg else: inactiveBg)
    if canClose and w >= 44:
      let closeSize = max(10, min(headerHeight - 10, 16))
      let closeX = x + w - closeSize - 6
      let closeY = max(4, (headerHeight - closeSize) div 2)
      r.addRect(closeX, closeY, closeSize, closeSize, winWidth, winHeight, closeBg)
    r.addRect(x + w - 1, 4, 1, headerHeight - 8, winWidth, winHeight, border)

  r.addRect(tabAreaWidth, 2, plusWidth, headerHeight - 3, winWidth, winHeight, inactiveBg)
  r.batcher.endBatch()

  r.batcher.textureId = r.atlasTexId
  r.batcher.beginBatch()
  let textY = max(1, (headerHeight - r.atlas.cellHeight) div 2)
  for i, tab in tabs.tabs:
    let x = i * tabWidth
    if x >= tabAreaWidth: break
    let w = min(tabWidth, tabAreaWidth - x)
    let isActive = tabs.activeId.isSome and tabs.activeId.get() == tab.id
    let closeReserve = if canClose and w >= 44: max(18, min(headerHeight, 24)) else: 0
    let labelCols = max(0, (w - 16 - closeReserve) div max(1, r.atlas.cellWidth))
    r.addText(x + 8, textY, winWidth, winHeight, tab.label, if isActive: text else: muted, labelCols)
    if canClose and w >= 44:
      let closeSize = max(10, min(headerHeight - 10, 16))
      let closeX = x + w - closeSize - 6
      let closeTextX = closeX + max(0, (closeSize - r.atlas.cellWidth) div 2)
      r.addText(closeTextX, textY, winWidth, winHeight, "x", muted, 1)

  let plusX = tabAreaWidth + max(0, (plusWidth - r.atlas.cellWidth) div 2)
  r.addText(plusX, textY, winWidth, winHeight, "+", text, 1)
  r.batcher.endBatch()

proc draw*(r: GpuTerminalRenderer, t: Terminal, winWidth, winHeight: int, topOffsetPx: int = 0) =
  ## Optimized single-pass rendering.
  let s = t.screen; let theme = s.theme
  let rows = max(1, t.viewport.height); let cols = s.cols; let historyLen = s.scrollback.len

  # Pre-calculate
  let tBg = toRgba(theme.background); let tFg = toRgba(theme.foreground); let tCursor = toRgba(theme.cursor)
  var tAnsi: array[16, RgbaColor]
  for i in 0..15: tAnsi[i] = toRgba(theme.ansi[i])

  let cw = float32(r.atlas.cellWidth); let ch = float32(r.atlas.cellHeight)
  let sw = float32(winWidth); let sh = float32(winHeight)
  let tw = (cw / sw) * 2.0; let th = (ch / sh) * 2.0
  let topOffset = (float32(topOffsetPx) / sh) * 2.0

  glEnable(GL_TEXTURE_2D); glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

  # --- ONE PASS FOR ALL BACKGROUNDS ---
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.batcher.addTile(-1.0, 1.0 - topOffset, 2.0, 2.0 - topOffset, 0, 0, 1, 1, tBg) # Screen fill

  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    let py = 1.0 - topOffset - (float32(row) * th)
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      if cell.attrs.bg.kind != screen_buffer_lib.ckDefault:
        let color = resolveColor(cell.attrs.bg, tAnsi)
        r.batcher.addTile(-1.0 + (float32(col)*tw), py, tw*float32(cell.width), th, 0, 0, 1, 1, color)
  # Cursor
  let cvr = t.viewport.bufferToViewport(historyLen + s.cursor.row)
  if cvr != -1 and not s.cursor.pendingWrap:
    r.batcher.addTile(-1.0 + (float32(s.cursor.col)*tw), 1.0 - topOffset - (float32(cvr)*th), tw, th, 0, 0, 1, 1, tCursor)

  # --- PASS 1.5: SELECTION HIGHLIGHT & LINKS ---
  if t.selection.isActive:
    let tSel = toRgba(theme.selection)
    for sp in t.selection.spans(cols):
      let vRow = t.viewport.bufferToViewport(sp.row)
      if vRow != -1:
        let px = -1.0 + (float32(sp.startCol) * tw)
        let py = 1.0 - topOffset - (float32(vRow) * th)
        r.batcher.addTile(px, py, tw * float32(sp.endCol - sp.startCol), th, 0, 0, 1, 1, tSel)

  if t.activeLink.isSome:
    let al = t.activeLink.get()
    let vRow = t.viewport.bufferToViewport(al.row)
    if vRow != -1:
      let px = -1.0 + (float32(al.startCol) * tw)
      # Draw a thin line at the bottom of the cell (y offset)
      let lineTh = th * 0.05
      let py = 1.0 - topOffset - (float32(vRow) * th) - (th - lineTh)
      r.batcher.addTile(px, py, tw * float32(al.endCol - al.startCol), lineTh, 0, 0, 1, 1, tCursor)

  r.batcher.endBatch()

  # --- ONE PASS FOR ALL GLYPHS ---
  r.batcher.textureId = r.atlasTexId
  r.batcher.beginBatch()
  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    let py = 1.0 - topOffset - (float32(row) * th)
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      if cell.rune > 32:
        let glyph = r.atlas.getGlyph(cell.rune)
        let color = if cell.attrs.fg.kind == screen_buffer_lib.ckDefault: tFg
                    else: resolveColor(cell.attrs.fg, tAnsi)
        r.batcher.addTile(-1.0 + (float32(col)*tw), py, tw, th, glyph.uvMin.x, glyph.uvMin.y, glyph.uvMax.x, glyph.uvMax.y, color)
  r.batcher.endBatch()
  glFlush()
  t.damage.clear()
