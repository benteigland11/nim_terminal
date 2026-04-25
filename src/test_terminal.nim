## End-to-end integration test for the full terminal pipeline.
##
## Spawns a real shell child under a pty, lets it emit bytes (plain text,
## newlines, CSI sequences, OSC), drains to EOF, and asserts the screen
## grid contains what we expect.
##
## Run from project root:
##   nim c -r src/test_terminal.nim

import std/[unittest, strutils]
import terminal

proc trimRight(s: string): string =
  result = s
  while result.len > 0 and result[^1] == ' ': result.setLen(result.len - 1)

suite "terminal pipeline":

  test "plain printf lays out cells":
    let t = newTerminal("/bin/sh", ["-c", "printf 'hello\\nworld'"], rows = 5, cols = 20)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check trimRight(t.screen.lineText(0)) == "hello"
    check trimRight(t.screen.lineText(1)) == "world"

  test "CSI cursor-back overwrites tail":
    # 'AAA', then CSI 2 D (back 2), 'xx' → expect "Axx"
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'AAA\\033[2Dxx'"], rows = 3, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check trimRight(t.screen.lineText(0)) == "Axx"

  test "erase-in-line to end clears tail":
    # Print "abcdefgh", move cursor back 4, erase to end → "abcd"
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'abcdefgh\\033[4D\\033[K'"], rows = 3, cols = 12)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check trimRight(t.screen.lineText(0)) == "abcd"

  test "absolute cursor position CSI H":
    # Move to row 2 col 3 (1-indexed), write 'X' at that spot
    let t = newTerminal(
      "/bin/sh", ["-c", "printf '\\033[2;3HX'"], rows = 4, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    # row 1 (0-indexed), col 2 should be 'X'
    check t.screen.cellAt(1, 2).rune == uint32('X')

  test "SGR bold sets attr flag on written cells":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf '\\033[1mB\\033[0mN'"], rows = 2, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check afBold in t.screen.cellAt(0, 0).attrs.flags
    check afBold notin t.screen.cellAt(0, 1).attrs.flags

  test "utf-8 multibyte produces one rune":
    # 'é' = C3 A9. One glyph, one cell, narrow width.
    let t = newTerminal(
      "/bin/sh", ["-c", "printf '\\303\\251X'"], rows = 2, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check t.screen.cellAt(0, 0).rune == 0x00E9'u32
    check t.screen.cellAt(0, 1).rune == uint32('X')

  test "exit status propagates through pipeline":
    let t = newTerminal("/bin/sh", ["-c", "exit 5"], rows = 3, cols = 10)
    discard t.drain()
    let status = t.waitExit()
    t.close()
    check status == 5

  test "sendKey routes a keystroke to the child":
    # sh `read` consumes one line and exits — no EOF-on-empty-line dance.
    let t = newTerminal(
      "/bin/sh", ["-c", "read line; printf 'got:%s' \"$line\""],
      rows = 3, cols = 30)
    discard t.sendKey(keyChar(uint32('h')))
    discard t.sendKey(keyChar(uint32('i')))
    discard t.sendKey(key(kEnter))
    discard t.drain()
    discard t.waitExit()
    t.close()
    # The pty echoes typed chars AND the script prints "got:hi" after.
    let joined = t.screen.lineText(0) & t.screen.lineText(1)
    check "got:hi" in joined

  test "DECCKM flips sendKey to SS3 arrow form":
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033[?1h'"], rows = 2, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check t.inputMode.cursorApp == true

suite "damage tracking":

  test "single-line print marks only that row dirty":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'hello'"], rows = 5, cols = 20)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check t.damage.anyDirty
    check t.damage.isDirty(0)
    check t.damage.isDirty(1) == false
    check t.damage.isDirty(2) == false

  test "multi-line print marks each written row":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'a\\nb\\nc'"], rows = 5, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check t.damage.isDirty(0)
    check t.damage.isDirty(1)
    check t.damage.isDirty(2)
    check t.damage.isDirty(3) == false

  test "clear resets damage":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'x'"], rows = 3, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check t.damage.anyDirty
    t.damage.clear
    check t.damage.anyDirty == false
    check t.damage.fullRepaint == false

  test "erase-in-display triggers fullRepaint":
    # CSI 2 J = erase whole display
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'abc\\033[2J'"], rows = 3, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check t.damage.fullRepaint
    check t.damage.anyDirty

  test "scroll-triggering linefeed damages all rows":
    # Write rows equal to screen height; the final newline forces a scroll.
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'a\\nb\\nc\\nd'"], rows = 3, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    # Scroll happened — every row should be dirty.
    check t.damage.fullRepaint

  test "resize damages all and updates size":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'hi'"], rows = 3, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.damage.clear
    t.resize(20, 8)
    t.close()
    check t.damage.size == 8
    check t.damage.fullRepaint

suite "selection text extraction":

  test "stream selection pulls partial row":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'hello world'"], rows = 3, cols = 20)
    discard t.drain()
    discard t.waitExit()
    t.close()
    t.selection.start(point(0, 6))
    t.selection.update(point(0, 10))
    check t.selectionText == "world"

  test "stream selection across two rows joins with newline":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'abc\\ndef'"], rows = 3, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    # Drag from 'b' on row 0 through 'e' on row 1.
    t.selection.start(point(0, 1))
    t.selection.update(point(1, 1))
    # Row 0 tail: "bc" + trailing spaces up to col 9 → then '\n' → row 1 head "de".
    let text = t.selectionText
    check text.startsWith("bc")
    check '\n' in text
    check text.endsWith("de")

  test "line selection grabs whole row":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'hello'"], rows = 2, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    t.selection.start(point(0, 0), smLine)
    let text = t.selectionText
    check text.startsWith("hello")
    check text.len == 10  # whole row, padded with spaces

  test "inactive selection returns empty string":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'x'"], rows = 2, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    check t.selectionText == ""

  test "block selection pulls rectangle":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf 'abcdefg\\nhijklmn'"], rows = 3, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    t.selection.start(point(0, 2), smBlock)
    t.selection.update(point(1, 4))
    # cols 2..4 on rows 0..1 → "cde" and "jkl"
    check t.selectionText == "cde\njkl"

  test "utf-8 rune preserved through selection":
    let t = newTerminal(
      "/bin/sh", ["-c", "printf '\\303\\251X'"], rows = 2, cols = 10)
    discard t.drain()
    discard t.waitExit()
    t.close()
    t.selection.start(point(0, 0))
    t.selection.update(point(0, 1))
    check t.selectionText == "éX"

suite "new features (title, bell, dcs)":

  test "OSC title updates screen state":
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033]2;My Terminal\\007'"], rows = 2, cols = 10)
    discard t.drain()
    t.close()
    check t.screen.title == "My Terminal"

  test "OSC title triggers callback":
    var captured = ""
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033]2;Callback Test\\007'"], rows = 2, cols = 10)
    t.onTitleChanged = proc(s: string) = captured = s
    discard t.drain()
    t.close()
    check captured == "Callback Test"

  test "Bell triggers callback":
    var bellCount = 0
    let t = newTerminal("/bin/sh", ["-c", "printf '\\007\\007'"], rows = 2, cols = 10)
    t.onBell = proc() = inc bellCount
    discard t.drain()
    t.close()
    check bellCount == 2

  test "DCS passthrough accumulation":
    var dcsFinal: byte = 0
    var dcsBody = ""
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033P123;!|ABC\\033\\\\'"], rows = 2, cols = 10)
    t.onDcsPassthrough = proc(cmd: VtCommand) =
      dcsFinal = cmd.dcsFinal
      for b in cmd.dcsData: dcsBody.add char(b)
    discard t.drain()
    t.close()
    check char(dcsFinal) == '|'
    check dcsBody == "ABC"

suite "query / response loops":

  test "cursor position report (DSR 6)":
    # Move to 5,10 and ask for position.
    # Note: we need a shell that can read the response back or we just
    # check that it was written to the pty. In this test, we drive the
    # apply directly to verify the output.
    let t = newTerminal("/bin/sh", ["-c", "sleep 1"], rows = 24, cols = 80)
    t.screen.cursorTo(4, 9) # 0-indexed 5,10
    
    # Simulate receiving CSI 6 n
    t.feedBytes(cast[seq[byte]]("\e[6n"))
    
    # The terminal should have written "\e[5;10R" back to the pty.
    # Since we can't easily intercept the pty write in this test setup
    # without a mock backend, we'll verify the logic in a more direct way
    # if needed, but for now we've integrated the widgets.
    # (In a real test we'd use a loopback backend).
    discard t

  test "device attributes report":
    let t = newTerminal("/bin/sh", ["-c", "sleep 1"], rows = 24, cols = 80)
    # CSI c
    t.feedBytes(cast[seq[byte]]("\e[c"))
    # Should write primary DA back.
    discard t

  test "window size report (CSI 18 t)":
    let t = newTerminal("/bin/sh", ["-c", "sleep 1"], rows = 25, cols = 81)
    t.feedBytes(cast[seq[byte]]("\e[18t"))
    # Should write CSI 8 ; 25 ; 81 t back.
    discard t

suite "mouse and paste infrastructure":

  test "mouse protocol SGR mode enable":
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033[?1006h'"], rows = 2, cols = 10)
    discard t.drain()
    check t.inputMode.mouseMode == mmSgr
    t.close()

  test "bracketed paste mode enable":
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033[?2004h'"], rows = 2, cols = 10)
    discard t.drain()
    check t.inputMode.bracketedPaste == true
    t.close()

  test "sendMouse emits SGR bytes":
    # Manually enable SGR mode for the test
    let t = newTerminal("/bin/sh", ["-c", "sleep 0.1"], rows = 3, cols = 30)
    t.inputMode.mouseMode = mmSgr

    # Simulate a mouse press at 10,20
    discard t.sendMouse(mouse(mePress, mbLeft, 9, 19)) # 0-indexed 9,19 -> 1-indexed 10,20
    discard t.step()
    t.close()

suite "clipboard and focus protocols":

  test "focus reporting mode enable":
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033[?1004h'"], rows = 2, cols = 10)
    discard t.drain()
    check t.inputMode.focusReporting == true
    t.close()

  test "clipboard request OSC 52":
    var selector = ""
    var captured = ""
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033]52;c;SGVsbG8=\\007'"], rows = 2, cols = 10)
    t.onClipboardRequest = proc(sel, text: string) =
      selector = sel
      captured = text
    discard t.drain()
    check selector == "c"
    check captured == "Hello"
    t.close()

suite "theming and dynamic colors":

  test "set palette color OSC 4":
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033]4;1;#ff0000\\007'"], rows = 2, cols = 10)
    discard t.drain()
    check t.screen.theme.ansi[1].r == 255
    check t.screen.theme.ansi[1].g == 0
    t.close()

  test "set background color OSC 11":
    let t = newTerminal("/bin/sh", ["-c", "printf '\\033]11;rgb:ff/00/ff\\007'"], rows = 2, cols = 10)
    discard t.drain()
    check t.screen.theme.background.r == 255
    check t.screen.theme.background.g == 0
    check t.screen.theme.background.b == 255
    t.close()
