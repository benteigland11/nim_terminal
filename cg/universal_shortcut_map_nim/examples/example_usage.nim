## Example usage of Shortcut Map.

import shortcut_map_lib
import std/options

# 1. Create a map
let m = newShortcutMap()

# 2. Bind actions
m.bindAction(key('C'), {modCtrl, modShift}, "copy")
m.bindAction(kEqual, {modCtrl}, "zoom-in")

# 3. Lookup actions
let a1 = m.lookup(key('C'), {modCtrl, modShift})
doAssert a1.isSome and a1.get() == "copy"

let a2 = m.lookup(kEqual, {modCtrl})
doAssert a2.isSome and a2.get() == "zoom-in"

echo "Shortcut-map example verified."
