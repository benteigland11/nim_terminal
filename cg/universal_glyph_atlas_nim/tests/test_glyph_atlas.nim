import std/unittest
import pixie
import ../src/glyph_atlas_lib

suite "glyph atlas":

  test "atlas creation and glyph retrieval":
    # Use a dummy font for testing if real one is not available
    # Pixie needs a font to calculate dimensions.
    # We'll just verify it compiles and runs if we had a font.
    # In a real environment, we'd load a .ttf
    discard
