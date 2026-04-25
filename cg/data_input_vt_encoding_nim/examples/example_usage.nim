## Example usage of Input Vt Encoding.
##
## This file must compile and run cleanly with no user input.

import input_vt_encoding_lib
import std/strutils

# Setup mode
var mode = newInputMode()
mode.mouseMode = mmSgr
mode.bracketedPaste = true

# Encode a key press (Ctrl+C)
let k = keyChar(uint32('c'), {modCtrl})
let kBytes = encodeKeyEvent(k, mode)
doAssert kBytes == @[3'u8] # ASCII ETX

# Encode a mouse press at 10,20
let m = mouse(mePress, mbLeft, 10, 20)
let mBytes = encodeMouseEvent(m, mode)
doAssert cast[string](mBytes) == "\e[<0;21;11M"

# Encode a paste
let pBytes = encodePaste("pasted text", mode)
doAssert cast[string](pBytes).startsWith("\e[200~")

echo "All input-vt-encoding examples passed."
