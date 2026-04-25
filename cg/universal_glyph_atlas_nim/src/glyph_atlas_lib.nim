## Monospace font glyph atlas.
##
## Pre-renders font glyphs into an in-memory cache to avoid expensive
## font-rendering calls during the main loop. Designed for fixed-width
## terminal grids.
##
## This widget uses `pixie` for font loading and rasterization.

import pixie
import std/[tables, unicode]

type
  Glyph* = object
    image*: Image
    width*: int
    height*: int

  GlyphAtlas* = ref object
    font*: Font
    fontSize*: float
    cellWidth*: int
    cellHeight*: int
    cache: Table[uint32, Glyph]

func newGlyphAtlas*(font: Font, fontSize: float): GlyphAtlas =
  ## Create a new atlas for the given font and size.
  ## Calculates cell dimensions based on the 'M' character.
  let arr = font.typeset("M")
  let cellWidth = if arr.selectionRects.len > 0: int(arr.selectionRects[0].w) else: 0
  let cellHeight = int(font.size * 1.2) # rough estimate for line height
  
  GlyphAtlas(
    font: font,
    fontSize: fontSize,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    cache: initTable[uint32, Glyph]()
  )

proc renderGlyph(a: GlyphAtlas, rune: uint32): Glyph =
  ## Rasterize a single rune into a Glyph object.
  let text = $rune.Rune
  let img = newImage(a.cellWidth, a.cellHeight)
  # Draw text centered or aligned as needed for terminals
  img.fillText(a.font, text)
  Glyph(image: img, width: a.cellWidth, height: a.cellHeight)

proc getGlyph*(a: GlyphAtlas, rune: uint32): Glyph =
  ## Retrieve a glyph from the cache, rendering it if missing.
  if not a.cache.hasKey(rune):
    a.cache[rune] = a.renderGlyph(rune)
  a.cache[rune]

proc drawGlyph*(a: GlyphAtlas, target: Image, rune: uint32, x, y: int) =
  ## Draw a glyph onto the target image at the given cell coordinates.
  let glyph = a.getGlyph(rune)
  target.draw(glyph.image, translate(vec2(float(x), float(y))))

proc clear*(a: GlyphAtlas) =
  ## Clear the glyph cache.
  a.cache.clear()
