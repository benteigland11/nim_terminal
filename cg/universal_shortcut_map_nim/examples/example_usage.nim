## Example usage of Shortcut Map.

import shortcut_map_lib
import std/options

# 1. Create a map
let m = newShortcutMap()

# 2. Bind actions (canonical form; keypad aliases resolve at lookup)
m.bindAction(key('C'), {modCtrl, modShift}, "copy")
m.bindAction(kEqual, {modCtrl}, "zoom-in")
m.bindAction(digitKey(1), {modAlt}, "tab-1")

# 3. Lookup actions
let a1 = m.lookup(key('C'), {modCtrl, modShift})
doAssert a1.isSome and a1.get() == "copy"

let a2 = m.lookup(kEqual, {modCtrl})
doAssert a2.isSome and a2.get() == "zoom-in"

# 4. Keypad digit aliases match the same binding as top-row digits
let a3 = m.lookup(kKeypad1, {modAlt})
doAssert a3.isSome and a3.get() == "tab-1"

echo "Shortcut-map example verified."
