## Example usage of Glfw Input.
##
## Demonstrates mapping raw GLFW constants to terminal types and
## unified shortcut identity for top-row vs keypad digits.

import std/options
import glfw_input_lib
import staticglfw

# Mock a GLFW key event (Shift + Escape)
let mods = toModifiers(MOD_SHIFT)
let key = toKeyCode(KEY_ESCAPE)

doAssert modShift in mods
doAssert key == kEscape

# Mock a mouse event
let btn = toMouseButton(MOUSE_BUTTON_LEFT)
doAssert btn == mbLeft

# Top-row and keypad digits share shortcut identity
let row = toShortcutId(KEY_1)
let pad = toShortcutId(KEY_KP_1)
doAssert row.kind == siChar and pad.kind == siChar
doAssert row.ch == pad.ch and row.ch == '1'
doAssert toPrintableRune(KEY_KP_5, 0).get() == uint32('5')

echo "Glfw input mapping verified."
