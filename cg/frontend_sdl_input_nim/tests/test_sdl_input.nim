import std/[unittest, options]
import ../src/sdl_input_lib

suite "sdl input translator":

  test "toModifiers bitmask mapping":
    let mods = toModifiers(KmodShift or KmodCtrl)
    check modShift in mods
    check modCtrl in mods
    check modAlt notin mods

  test "toKeyCode mapping":
    check toKeyCode(ScUp) == kArrowUp
    check toKeyCode(ScEscape) == kEscape
    check toKeyCode(ScKpEnter) == kKeypadEnter
    check toKeyCode(ScReturn) == kEnter

  test "toMouseButton mapping":
    check toMouseButton(ButtonLeft) == mbLeft
    check toMouseButton(ButtonRight) == mbRight

  test "toPrintableRune maps ascii and keypad":
    check toPrintableRune(Key1).get() == uint32('1')
    check toPrintableRune(KeyA).get() == uint32('a')
    check toPrintableRune(KeyKp0).get() == uint32('0')
    check toPrintableRune(KeyKp1).get() == uint32('1')
    check toPrintableRune(KeyKp9).get() == uint32('9')
    check toPrintableRune(KeyKpPlus).get() == uint32('+')
    check toPrintableRune(KeyKpMinus).get() == uint32('-')
    check toPrintableRune(0x40000052'u32).isNone  # arrow up keycode

  test "toShortcutId unifies top-row and keypad digits":
    check toShortcutId(Key1).kind == siChar
    check toShortcutId(Key1).ch == '1'
    check toShortcutId(KeyKp1).kind == siChar
    check toShortcutId(KeyKp1).ch == '1'
    check toShortcutId(KeyKp9).ch == '9'

  test "toShortcutId unifies enter and operators":
    check toShortcutId(KeyReturn).kind == siEnter
    check toShortcutId(KeyKpEnter).kind == siEnter
    check toShortcutId(KeyMinus).kind == siMinus
    check toShortcutId(KeyKpMinus).kind == siMinus
    check toShortcutId(KeyKpPlus).kind == siPlus
    check toShortcutId(KeyEquals).kind == siEqual

  test "toShortcutId case-folds letters":
    check toShortcutId(KeyA).kind == siChar
    check toShortcutId(KeyA).ch == 'A'
