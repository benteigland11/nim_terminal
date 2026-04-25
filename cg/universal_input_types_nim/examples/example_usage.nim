## Example usage of Input Types.
##
## This file must compile and run cleanly with no user input.

import input_types_lib

# Create a simple key event
let k = keyChar(uint32('a'), {modCtrl})
doAssert k.code == kChar
doAssert k.mods == {modCtrl}

# Create a mouse event
let m = mouse(mePress, mbLeft, 10, 20, {modShift})
doAssert m.kind == mePress
doAssert m.button == mbLeft
doAssert m.row == 10
doAssert m.col == 20

echo "All input-types examples passed."
