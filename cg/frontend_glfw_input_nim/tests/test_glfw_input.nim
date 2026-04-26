import std/unittest
import std/options
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

  test "toPrintableRune maps unshifted printable keys":
    check toPrintableRune(KEY_A, 0).get() == uint32('a')
    check toPrintableRune(KEY_5, 0).get() == uint32('5')
    check toPrintableRune(KEY_SLASH, 0).get() == uint32('/')

  test "toPrintableRune maps shifted printable keys":
    check toPrintableRune(KEY_A, MOD_SHIFT).get() == uint32('A')
    check toPrintableRune(KEY_5, MOD_SHIFT).get() == uint32('%')
    check toPrintableRune(KEY_SLASH, MOD_SHIFT).get() == uint32('?')

  test "toPrintableRune ignores non-printable keys":
    check toPrintableRune(KEY_UP, 0).isNone
