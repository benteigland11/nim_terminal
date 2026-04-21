## Construct a screen, write styled text, move the cursor, and scroll.
##
## Demonstrates: newScreen, writeString, applySgr (16-color + truecolor),
## cursorTo, alternate screen, and rendering a row back out.

import std/strutils
import screen_buffer_lib

let screen = newScreen(40, 5, scrollback = 100)

# Write a bold red heading.
screen.applySgr([sgr(1), sgr(31)])
screen.writeString("Status")
screen.applySgr([])
screen.carriageReturn(); screen.linefeed()

# Write a truecolor line.
screen.applySgr([sgr(38), sgr(2), sgr(100), sgr(150), sgr(200)])
screen.writeString("colored")
screen.applySgr([])
screen.carriageReturn(); screen.linefeed()

screen.writeString("row two")
screen.carriageReturn(); screen.linefeed()
screen.writeString("row three")

doAssert screen.lineText(0).startsWith("Status")
doAssert screen.lineText(1).startsWith("colored")
doAssert screen.lineText(2).startsWith("row two")
doAssert screen.lineText(3).startsWith("row three")

# Scroll the whole screen up once; the top row moves into scrollback.
screen.cursorTo(screen.rows - 1, 0)
screen.linefeed()
doAssert screen.scrollbackLen == 1
doAssert screen.lineText(0).startsWith("colored")

# Alternate screen preserves the primary.
screen.useAlternateScreen(true)
screen.cursorTo(0, 0)
screen.writeString("(alt)")
doAssert screen.lineText(0).startsWith("(alt)")
screen.useAlternateScreen(false)
doAssert screen.lineText(0).startsWith("colored")
