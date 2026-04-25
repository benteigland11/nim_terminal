import std/unittest
import ../src/glfw_input_lib
import staticglfw

suite "glfw input translator":

  test "toModifiers bitmask mapping":
    let mods = toModifiers(MOD_SHIFT or MOD_CONTROL)
    check modShift in mods
    check modCtrl in mods
    check modAlt notin mods

  test "toKeyCode mapping":
    check toKeyCode(KEY_UP) == kArrowUp
    check toKeyCode(KEY_ESCAPE) == kEscape

  test "toMouseButton mapping":
    check toMouseButton(MOUSE_BUTTON_LEFT) == mbLeft
