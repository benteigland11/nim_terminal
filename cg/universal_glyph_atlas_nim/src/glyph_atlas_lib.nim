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
    uvMin*, uvMax*: Vec2    ## UV coordinates in the atlas texture (0.0 to 1.0)
    width*, height*: int   ## Pixel dimensions

  GlyphAtlas* = ref object
    font*: Font
    fontSize*: float
    cellWidth*, cellHeight*: int
    atlasImage*: Image     ## The single big image containing all rendered glyphs
    cache: Table[uint32, Glyph]
    nextX, nextY: int      ## Current packing position in the atlas
    isDirty*: bool         ## True if the atlas image changed since last sync

func newGlyphAtlas*(font: Font, fontSize: float, atlasSize: int = 1024): GlyphAtlas =
  ## Create a new atlas. atlasSize determines the texture dimensions (e.g. 1024x1024).
  let arr = font.typeset("M")
  let cellWidth = if arr.selectionRects.len > 0: int(arr.selectionRects[0].w) else: 0
  let cellHeight = int(font.size * 1.2)
  
  GlyphAtlas(
    font: font,
    fontSize: fontSize,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    atlasImage: newImage(atlasSize, atlasSize),
    cache: initTable[uint32, Glyph](),
    nextX: 0,
    nextY: 0,
    isDirty: true
  )

proc getGlyph*(a: GlyphAtlas, rune: uint32): Glyph =
  ## Retrieve a glyph's UVs. Renders to the atlas if missing.
  if not a.cache.hasKey(rune):
    # Simple row-based packing
    if a.nextX + a.cellWidth > a.atlasImage.width:
      a.nextX = 0
      a.nextY += a.cellHeight
    
    if a.nextY + a.cellHeight > a.atlasImage.height:
      # Atlas full!
      return Glyph()

    # Draw the rune into the atlas at (nextX, nextY)
    let text = $rune.Rune
    a.atlasImage.fillText(a.font, text, translate(vec2(float(a.nextX), float(a.nextY))))
    a.isDirty = true
    
    # Calculate UVs
    let invW = 1.0 / float(a.atlasImage.width)
    let invH = 1.0 / float(a.atlasImage.height)
    
    let glyph = Glyph(
      uvMin: vec2(float(a.nextX) * invW, float(a.nextY) * invH),
      uvMax: vec2(float(a.nextX + a.cellWidth) * invW, float(a.nextY + a.cellHeight) * invH),
      width: a.cellWidth,
      height: a.cellHeight
    )
    
    a.cache[rune] = glyph
    a.nextX += a.cellWidth
    
  a.cache[rune]

proc setFallbackTypefaces*(a: GlyphAtlas, fallbacks: openArray[Typeface]) =
  ## Replace the atlas font's fallback chain.
  ##
  ## Pixie resolves glyph paths through the primary typeface and then this
  ## fallback list, so callers can keep one monospace cell metric while
  ## filling symbol/emoji/private-use gaps from other typefaces.
  a.font.typeface.fallbacks.setLen(0)
  for fallback in fallbacks:
    if fallback != nil:
      a.font.typeface.fallbacks.add fallback
  a.cache.clear()
  a.nextX = 0
  a.nextY = 0
  a.atlasImage.fill(color(0, 0, 0, 0))
  a.isDirty = true

func hasGlyphOrFallback*(a: GlyphAtlas, rune: uint32): bool =
  ## True when the primary typeface or any configured fallback has a glyph.
  a.font.typeface.fallbackTypeface(Rune(rune)) != nil

proc clear*(a: GlyphAtlas) =
  a.cache.clear()
  a.nextX = 0
  a.nextY = 0
  a.atlasImage.fill(color(0, 0, 0, 0))
  a.isDirty = true
