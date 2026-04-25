## GPU-accelerated terminal grid renderer.
##
## Translates the in-memory `Screen` buffer into OpenGL quads.
## Uses `TileBatcher` for efficiency and `GlyphAtlas` for UV mapping.

import opengl
import pixie
import ../cg/data_screen_buffer_nim/src/screen_buffer_lib
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
import ../cg/universal_tile_batcher_nim/src/tile_batcher_lib
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
  rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

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

proc draw*(r: GpuTerminalRenderer, t: Terminal, winWidth, winHeight: int) =
  ## Optimized single-pass rendering.
  let s = t.screen; let theme = s.theme
  let rows = s.rows; let cols = s.cols; let historyLen = s.scrollback.len
  
  # Pre-calculate
  let tBg = toRgba(theme.background); let tFg = toRgba(theme.foreground); let tCursor = toRgba(theme.cursor)
  var tAnsi: array[16, RgbaColor]
  for i in 0..15: tAnsi[i] = toRgba(theme.ansi[i])

  let cw = float32(r.atlas.cellWidth); let ch = float32(r.atlas.cellHeight)
  let sw = float32(winWidth); let sh = float32(winHeight)
  let tw = (cw / sw) * 2.0; let th = (ch / sh) * 2.0
  
  glEnable(GL_TEXTURE_2D); glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

  # --- ONE PASS FOR ALL BACKGROUNDS ---
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  r.batcher.addTile(-1.0, 1.0, 2.0, 2.0, 0, 0, 1, 1, tBg) # Screen fill

  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    let py = 1.0 - (float32(row) * th)
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      if cell.attrs.bg.kind != ckDefault:
        let color = if cell.attrs.bg.kind == ckIndexed: tAnsi[cell.attrs.bg.index mod 16]
                    else: rgba(cell.attrs.bg.r.float32/255.0, cell.attrs.bg.g.float32/255.0, cell.attrs.bg.b.float32/255.0, 1.0)
        r.batcher.addTile(-1.0 + (float32(col)*tw), py, tw*float32(cell.width), th, 0, 0, 1, 1, color)
  # Cursor
  let cvr = t.viewport.bufferToViewport(historyLen + s.cursor.row)
  if cvr != -1 and not s.cursor.pendingWrap:
    r.batcher.addTile(-1.0 + (float32(s.cursor.col)*tw), 1.0 - (float32(cvr)*th), tw, th, 0, 0, 1, 1, tCursor)

  # --- PASS 1.5: SELECTION HIGHLIGHT ---
  if t.selection.isActive:
    let tSel = toRgba(theme.selection)
    for sp in t.selection.spans(cols):
      let vRow = t.viewport.bufferToViewport(sp.row)
      if vRow != -1:
        let px = -1.0 + (float32(sp.startCol) * tw)
        let py = 1.0 - (float32(vRow) * th)
        r.batcher.addTile(px, py, tw * float32(sp.endCol - sp.startCol), th, 0, 0, 1, 1, tSel)

  r.batcher.endBatch()

  # --- ONE PASS FOR ALL GLYPHS ---
  r.batcher.textureId = r.atlasTexId
  r.batcher.beginBatch()
  for row in 0 ..< rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let cells = s.absoluteRowAt(absRow)
    if cells.len == 0: continue
    let py = 1.0 - (float32(row) * th)
    for col in 0 ..< min(cols, cells.len):
      let cell = cells[col]
      if cell.rune > 32:
        let glyph = r.atlas.getGlyph(cell.rune)
        let color = if cell.attrs.fg.kind == ckIndexed: tAnsi[cell.attrs.fg.index mod 16]
                    elif cell.attrs.fg.kind == ckRgb: rgba(cell.attrs.fg.r.float32/255.0, cell.attrs.fg.g.float32/255.0, cell.attrs.fg.b.float32/255.0, 1.0)
                    else: tFg
        r.batcher.addTile(-1.0 + (float32(col)*tw), py, tw, th, glyph.uvMin.x, glyph.uvMin.y, glyph.uvMax.x, glyph.uvMax.y, color)
  r.batcher.endBatch()
  glFlush()
  t.damage.clear()
