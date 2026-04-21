## Translate a handful of raw CSI / ESC / OSC dispatches into typed
## commands and pattern-match on the result.

import vt_commands_lib

# CSI 5;10 H  → cursor to row 4, col 9.
let moveCmd = translateCsi(@[param(5), param(10)], @[], byte('H'))
doAssert moveCmd.kind == cmdCursorTo
doAssert moveCmd.row == 4 and moveCmd.col == 9

# CSI ? 25 h  → DECSET private mode 25 (show cursor).
let modeCmd = translateCsi(@[param(25)], @[byte('?')], byte('h'))
doAssert modeCmd.kind == cmdSetMode and modeCmd.privateMode
doAssert modeCmd.modeCode == 25

# CSI 1;31 m  → SGR: bold red.
let sgrCmd = translateCsi(@[param(1), param(31)], @[], byte('m'))
doAssert sgrCmd.kind == cmdSetSgr
doAssert sgrCmd.sgrParams.len == 2

# ESC M  → reverse index.
doAssert translateEsc(@[], byte('M')).kind == cmdReverseIndex

# OSC 0 ; "window title"  → SetTitle.
var osc: seq[byte] = @[]
for c in "0;window title": osc.add byte(c)
let titleCmd = translateOsc(osc)
doAssert titleCmd.kind == cmdSetTitle
doAssert titleCmd.text == "window title"

# Execute byte 0x0A (LF).
doAssert translateExecute(0x0A'u8).kind == cmdLineFeed
