import std/[os, unittest]
import pixie
import ../src/glyph_atlas_lib

const
  PrimaryFontEnv = "GLYPH_ATLAS_PRIMARY_FONT"
  FallbackFontEnv = "GLYPH_ATLAS_FALLBACK_FONT"
  PowerlineBranch = 0xE0A0'u32

suite "glyph atlas":

  test "atlas creation and glyph retrieval":
    let primaryFont = getEnv(PrimaryFontEnv)
    if primaryFont.len == 0:
      skip()
    elif fileExists(primaryFont):
      let font = readFont(primaryFont)
      font.size = 18
      let atlas = newGlyphAtlas(font, 18)
      let glyph = atlas.getGlyph(uint32('A'))
      check glyph.width == atlas.cellWidth
      check glyph.height == atlas.cellHeight
    else:
      skip()

  test "configured fallback reports glyph coverage":
    let primaryFont = getEnv(PrimaryFontEnv)
    let fallbackFont = getEnv(FallbackFontEnv)
    if primaryFont.len == 0 or fallbackFont.len == 0:
      skip()
    elif fileExists(primaryFont) and fileExists(fallbackFont):
      let font = readFont(primaryFont)
      font.size = 18
      let atlas = newGlyphAtlas(font, 18)
      check atlas.hasGlyphOrFallback(PowerlineBranch) == false
      atlas.setFallbackTypefaces([readTypeface(fallbackFont)])
      check atlas.hasGlyphOrFallback(PowerlineBranch)
    else:
      skip()
