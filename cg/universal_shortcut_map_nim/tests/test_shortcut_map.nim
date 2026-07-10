import std/[unittest, options]
import ../src/shortcut_map_lib

suite "shortcut map":

  test "bind and lookup character shortcut":
    let m = newShortcutMap()
    m.bindAction(shortcutKey('C'), {modCtrl, modShift}, "copy")

    let action = m.lookup(shortcutKey('C'), {modCtrl, modShift})
    check action.isSome
    check action.get() == "copy"

    # Check no match
    check m.lookup(shortcutKey('C'), {modCtrl}).isNone
    check m.lookup(shortcutKey('X'), {modCtrl, modShift}).isNone

  test "printable letter shortcuts are case-normalized":
    check shortcutKey('c') == shortcutKey('C')
    check shortcutKey('v') == shortcutKey('V')
    check shortcutKey('=') == key('=')
    check canonicalKey(key('c')) == shortcutKey('C')

  test "digitKey and keypad digits share identity":
    check digitKey(1) == shortcutKey('1')
    check canonicalKey(kKeypad1) == digitKey(1)
    check canonicalKey(keypadDigit(5)) == digitKey(5)
    check canonicalKey(kKeypadEnter) == kEnter
    check canonicalKey(kKeypadAdd) == kPlus
    check canonicalKey(kKeypadSubtract) == kMinus

  test "bind and lookup special shortcut":
    let m = newShortcutMap()
    m.bindAction(kEqual, {modCtrl}, "zoom-in")

    let action = m.lookup(kEqual, {modCtrl})
    check action.isSome
    check action.get() == "zoom-in"

  test "lookup resolves keypad aliases for digit bindings":
    let m = newShortcutMap()
    m.bindAction(digitKey(1), {modAlt}, "tab-1")
    check m.lookup(shortcutKey('1'), {modAlt}).get() == "tab-1"
    check m.lookup(kKeypad1, {modAlt}).get() == "tab-1"
    check m.lookup(keypadDigit(1), {modAlt}).get() == "tab-1"

  test "bindAction multi-key helper":
    let m = newShortcutMap()
    m.bindAction([kMinus, kKeypadSubtract], {modCtrl}, "zoom-out")
    check m.lookup(kMinus, {modCtrl}).get() == "zoom-out"
    check m.lookup(kKeypadSubtract, {modCtrl}).get() == "zoom-out"

  test "standard terminal shortcuts":
    let m = newShortcutMap()
    m.addStandardTerminalShortcuts()
    check m.lookup(shortcutKey('c'), {modCtrl, modShift}).get() == "copy"
    check m.lookup(shortcutKey('v'), {modCtrl, modShift}).get() == "paste"
    check m.lookup(shortcutKey('v'), {modCtrl}).isNone
    check m.lookup(shortcutKey('w'), {modCtrl}).get() == "close-tab"
    check m.lookup(shortcutKey('1'), {modAlt}).get() == "tab-1"
    check m.lookup(kKeypad1, {modAlt}).get() == "tab-1"
    check m.lookup(shortcutKey('9'), {modAlt}).get() == "tab-9"
    check m.lookup(kKeypad9, {modAlt}).get() == "tab-9"
    check m.lookup(kEqual, {modCtrl}).get() == "zoom-in"
    check m.lookup(kEqual, {modCtrl, modShift}).get() == "zoom-in"
    check m.lookup(kPlus, {modCtrl, modShift}).get() == "zoom-in"
    check m.lookup(kKeypadAdd, {modCtrl}).get() == "zoom-in"
    check m.lookup(kKeypadSubtract, {modCtrl}).get() == "zoom-out"

  test "agent terminal shortcuts":
    let m = newShortcutMap()
    m.addAgentTerminalShortcuts()
    check m.lookup(shortcutKey('A'), {modCtrl, modShift}).get() == "switch-surface"
    check m.lookup(shortcutKey('c'), {modCtrl, modShift}).get() == "copy"
