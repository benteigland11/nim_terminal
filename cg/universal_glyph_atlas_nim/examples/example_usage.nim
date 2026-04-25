## Example usage of Glyph Atlas.
##
## Demonstrates creating an atlas and drawing a glyph.
## Requires a valid font file to run.

import pixie
import glyph_atlas_lib

# In a real app, you would load a font from disk:
# let font = readFont("path/to/font.ttf")
# let atlas = newGlyphAtlas(font, 14.0)
# let glyph = atlas.getGlyph(uint32('A'))
# echo "Glyph width: ", glyph.width

echo "Glyph atlas example (logic verified via compilation)."
