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
  ## Upload the current atlas image to the GPU only if it changed.
  if not r.atlas.isDirty: return
  
  glBindTexture(GL_TEXTURE_2D, r.atlasTexId)
  let img = r.atlas.atlasImage
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, cint(img.width), cint(img.height),
               0, GL_RGBA, GL_UNSIGNED_BYTE, addr img.data[0])
  r.atlas.isDirty = false

func toRgba(c: PaletteColor): RgbaColor =
  rgba(c.r.float32 / 255.0, c.g.float32 / 255.0, c.b.float32 / 255.0, 1.0)

proc preRenderAscii*(r: GpuTerminalRenderer) =
  ## Warm up the atlas with common ASCII characters.
  for i in 32..126:
    discard r.atlas.getGlyph(uint32(i))
  r.updateAtlasTexture()

proc newGpuTerminalRenderer*(atlas: GlyphAtlas): GpuTerminalRenderer =
  var ids: array[2, uint32]
  glGenTextures(2, addr ids[0])
  
  # Setup Atlas Texture
  glBindTexture(GL_TEXTURE_2D, ids[0])
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  
  # Setup Background Texture (1x1 white)
  glBindTexture(GL_TEXTURE_2D, ids[1])
  var whitePixel: uint32 = 0xFFFFFFFF'u32
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.cint, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr whitePixel)
  
  result = GpuTerminalRenderer(
    atlas: atlas,
    batcher: newTileBatcher(ids[0]),
    atlasTexId: ids[0],
    bgTexId: ids[1]
  )
  result.preRenderAscii()

proc draw*(r: GpuTerminalRenderer, t: Terminal, winWidth, winHeight: int) =
  ## Render the terminal to the current OpenGL context.
  let s = t.screen
  let theme = s.theme
  
  # Ensure state is set
  glEnable(GL_TEXTURE_2D)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  
  let cw = float32(r.atlas.cellWidth)
  let ch = float32(r.atlas.cellHeight)
  let screenW = float32(winWidth)
  let screenH = float32(winHeight)
  
  let tw = (cw / screenW) * 2.0
  let th = (ch / screenH) * 2.0
  
  # 1. Draw backgrounds
  r.batcher.textureId = r.bgTexId
  r.batcher.beginBatch()
  
  # Full theme background
  r.batcher.addTile(-1.0, 1.0, 2.0, 2.0, 0, 0, 1, 1, toRgba(theme.background))
  
  for row in 0 ..< s.rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let py = 1.0 - (float32(row) * th)
    
    for col in 0 ..< s.cols:
      let cell = s.absoluteCellAt(absRow, col)
      if cell.attrs.bg.kind != ckDefault:
        var c: RgbaColor
        if cell.attrs.bg.kind == ckIndexed:
          c = toRgba(theme.ansi[cell.attrs.bg.index mod 16])
        else:
          c = rgba(cell.attrs.bg.r.float32 / 255.0, cell.attrs.bg.g.float32 / 255.0, cell.attrs.bg.b.float32 / 255.0, 1.0)
        
        let px = -1.0 + (float32(col) * tw)
        r.batcher.addTile(px, py, tw * float32(cell.width), th, 0, 0, 1, 1, c)
  
  # Cursor background
  let cursorViewportRow = t.viewport.bufferToViewport(s.scrollback.len + s.cursor.row)
  if cursorViewportRow != -1 and not s.cursor.pendingWrap:
    let px = -1.0 + (float32(s.cursor.col) * tw)
    let py = 1.0 - (float32(cursorViewportRow) * th)
    r.batcher.addTile(px, py, tw, th, 0, 0, 1, 1, toRgba(theme.cursor))
    
  r.batcher.endBatch()
  
  # 2. Draw Glyphs
  r.batcher.textureId = r.atlasTexId
  r.batcher.beginBatch()
  
  for row in 0 ..< s.rows:
    let absRow = t.viewport.viewportToBuffer(row)
    let py = 1.0 - (float32(row) * th)
    
    for col in 0 ..< s.cols:
      let cell = s.absoluteCellAt(absRow, col)
      if cell.rune != 0 and cell.rune != uint32(' '):
        let glyph = r.atlas.getGlyph(cell.rune)
        let px = -1.0 + (float32(col) * tw)
        
        var fg: RgbaColor
        if cell.attrs.fg.kind == ckIndexed:
          fg = toRgba(theme.ansi[cell.attrs.fg.index mod 16])
        elif cell.attrs.fg.kind == ckRgb:
          fg = rgba(cell.attrs.fg.r.float32 / 255.0, cell.attrs.fg.g.float32 / 255.0, cell.attrs.fg.b.float32 / 255.0, 1.0)
        else:
          fg = toRgba(theme.foreground)
        
        r.batcher.addTile(
          px, py, tw, th,
          glyph.uvMin.x, glyph.uvMin.y,
          glyph.uvMax.x, glyph.uvMax.y,
          fg
        )
        
  r.batcher.endBatch()
  glFlush()
