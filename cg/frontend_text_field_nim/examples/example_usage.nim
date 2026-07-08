## Example usage of Text Field.

import std/unicode
import text_field_lib

var field = newTextField()
field.insertText("search query")
field.moveHome()
field.moveRight()
field.insertRune("X".runeAt(0))
assert field.text == "sXearch query"

# Render helper: get the visible slice for a field 8 columns wide.
let view = field.viewport(8)
assert view.text.len <= 8
assert view.caretCol >= 0
