import std/[unittest, options]
import ../src/shortcut_map_lib

suite "shortcut map":

  test "bind and lookup character shortcut":
    let m = newShortcutMap()
    m.bindAction(key('C'), {modCtrl, modShift}, "copy")
    
    let action = m.lookup(key('C'), {modCtrl, modShift})
    check action.isSome
    check action.get() == "copy"
    
    # Check no match
    check m.lookup(key('C'), {modCtrl}).isNone
    check m.lookup(key('X'), {modCtrl, modShift}).isNone

  test "bind and lookup special shortcut":
    let m = newShortcutMap()
    m.bindAction(kEqual, {modCtrl}, "zoom-in")
    
    let action = m.lookup(kEqual, {modCtrl})
    check action.isSome
    check action.get() == "zoom-in"

  test "standard terminal shortcuts":
    let m = newShortcutMap()
    m.addStandardTerminalShortcuts()
    check m.lookup(key('C'), {modCtrl, modShift}).get() == "copy"
    check m.lookup(kEqual, {modCtrl}).get() == "zoom-in"
