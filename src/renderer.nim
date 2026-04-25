## Pixie-based terminal grid renderer.
##
## Translates the in-memory `Screen` buffer and `TerminalTheme` into
## a rendered `Image`. Uses `GlyphAtlas` for efficient text drawing.

import pixie
import ../cg/data_screen_buffer_nim/src/screen_buffer_lib
import ../cg/universal_glyph_atlas_nim/src/glyph_atlas_lib
import terminal

type
  TerminalRenderer* = ref object
    atlas*: GlyphAtlas
    surface*: Image

func newTerminalRenderer*(atlas: GlyphAtlas, width, height: int): TerminalRenderer =
  TerminalRenderer(
    atlas: atlas,
    surface: newImage(width, height)
  )

func toPixieColor(c: PaletteColor): pixie.Color =
  color(c.r.float / 255.0, c.g.float / 255.0, c.b.float / 255.0, 1.0)

proc draw*(r: TerminalRenderer, t: Terminal) =
  ## Render the current state of the terminal to the surface.
  ## Uses the damage tracker to only repaint dirty areas.
  if not t.damage.anyDirty: return

  let s = t.screen
  let theme = s.theme
  let cw = r.atlas.cellWidth
  let ch = r.atlas.cellHeight
  
  let ctx = r.surface.newContext()

  if t.damage.fullRepaint:
    r.surface.fill(toPixieColor(theme.background))
    # Full redraw will handle all rows below
  
  # Determine which rows to paint
  for row in 0 ..< s.rows:
    if not t.damage.isDirty(row) and not t.damage.fullRepaint:
      continue
    
    let y = row * ch
    
    # 1. Clear the row background if not fullRepaint (which already filled)
    if not t.damage.fullRepaint:
      ctx.fillStyle = toPixieColor(theme.background)
      ctx.fillRect(rect(vec2(0, float(y)), vec2(float(r.surface.width), float(ch))))

    # 2. Draw row cells
    for col in 0 ..< s.cols:
      let cell = s.cellAt(row, col)
      if cell.width == 0: continue # Skip continuation cells
      
      let x = col * cw
      
      # Draw background override if not default
      if cell.attrs.bg.kind != ckDefault:
        var bgPixie: pixie.Color
        if cell.attrs.bg.kind == ckIndexed:
          bgPixie = toPixieColor(theme.ansi[cell.attrs.bg.index mod 16])
        else:
          bgPixie = color(cell.attrs.bg.r.float / 255.0, cell.attrs.bg.g.float / 255.0, cell.attrs.bg.b.float / 255.0, 1.0)
        ctx.fillStyle = bgPixie
        ctx.fillRect(rect(vec2(float(x), float(y)), vec2(float(cw * int(cell.width)), float(ch))))
      
      # Draw glyph
      if cell.rune != 0 and cell.rune != uint32(' '):
        # Determine foreground color (Simple for now, atlas draws with font's color)
        r.atlas.drawGlyph(r.surface, cell.rune, x, y)

  # 3. Draw cursor (Redraw it every time something changed to ensure it's not buried)
  if not s.cursor.pendingWrap:
    let cx = s.cursor.col * cw
    let cy = s.cursor.row * ch
    ctx.fillStyle = toPixieColor(theme.cursor)
    ctx.fillRect(rect(vec2(float(cx), float(cy)), vec2(float(cw), float(ch))))
    
  # Mark everything clean for next frame
  t.damage.clear()
    # Redraw the character on top of cursor with inverted color?
    # (Simplified for now)
