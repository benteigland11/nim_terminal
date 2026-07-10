## Example usage of Sdl Input.
##
## Demonstrates mapping SDL3-compatible constants to terminal types and
## unified shortcut identity for top-row vs keypad digits.

import std/options
import sdl_input_lib

let mods = toModifiers(KmodShift)
let key = toKeyCode(ScEscape)
doAssert modShift in mods
doAssert key == kEscape

let btn = toMouseButton(ButtonLeft)
doAssert btn == mbLeft

let row = toShortcutId(Key1)
let pad = toShortcutId(KeyKp1)
doAssert row.kind == siChar and pad.kind == siChar
doAssert row.ch == pad.ch and row.ch == '1'
doAssert toPrintableRune(KeyKp5).get() == uint32('5')

echo "Sdl input mapping verified."
