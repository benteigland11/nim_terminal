## Example usage of Glfw Input.
##
## Demonstrates mapping raw GLFW constants to terminal types.

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

echo "Glfw input mapping verified."
