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
    check toKeyCode(KEY_KP_ENTER) == kKeypadEnter

  test "toMouseButton mapping":
    check toMouseButton(MOUSE_BUTTON_LEFT) == mbLeft

  test "toPrintableRune maps unshifted printable keys":
    check toPrintableRune(KEY_A, 0).get() == uint32('a')
    check toPrintableRune(KEY_5, 0).get() == uint32('5')
    check toPrintableRune(KEY_MINUS, 0).get() == uint32('-')
    check toPrintableRune(KEY_SLASH, 0).get() == uint32('/')

  test "toPrintableRune maps shifted printable keys":
    check toPrintableRune(KEY_A, MOD_SHIFT).get() == uint32('A')
    check toPrintableRune(KEY_5, MOD_SHIFT).get() == uint32('%')
    check toPrintableRune(KEY_SLASH, MOD_SHIFT).get() == uint32('?')

  test "toPrintableRune maps keypad digits and operators":
    check toPrintableRune(KEY_KP_0, 0).get() == uint32('0')
    check toPrintableRune(KEY_KP_1, 0).get() == uint32('1')
    check toPrintableRune(KEY_KP_9, 0).get() == uint32('9')
    check toPrintableRune(KEY_KP_DECIMAL, 0).get() == uint32('.')
    check toPrintableRune(KEY_KP_DIVIDE, 0).get() == uint32('/')
    check toPrintableRune(KEY_KP_MULTIPLY, 0).get() == uint32('*')
    check toPrintableRune(KEY_KP_SUBTRACT, 0).get() == uint32('-')
    check toPrintableRune(KEY_KP_ADD, 0).get() == uint32('+')

  test "toPrintableRune ignores non-printable keys":
    check toPrintableRune(KEY_UP, 0).isNone

  test "toShortcutId unifies top-row and keypad digits":
    check toShortcutId(KEY_1).kind == siChar
    check toShortcutId(KEY_1).ch == '1'
    check toShortcutId(KEY_KP_1).kind == siChar
    check toShortcutId(KEY_KP_1).ch == '1'
    check toShortcutId(KEY_KP_9).ch == '9'

  test "toShortcutId unifies enter and operators":
    check toShortcutId(KEY_ENTER).kind == siEnter
    check toShortcutId(KEY_KP_ENTER).kind == siEnter
    check toShortcutId(KEY_MINUS).kind == siMinus
    check toShortcutId(KEY_KP_SUBTRACT).kind == siMinus
    check toShortcutId(KEY_KP_ADD).kind == siPlus
    check toShortcutId(KEY_EQUAL).kind == siEqual

  test "toShortcutId case-folds letters":
    check toShortcutId(KEY_C).kind == siChar
    check toShortcutId(KEY_C).ch == 'C'
