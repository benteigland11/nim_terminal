import std/unittest
import std/strutils
import screen_buffer_lib

# Trim trailing spaces from a row's rendered text for readable assertions.
proc trimmedLine(s: Screen, row: int): string =
  let raw = s.lineText(row)
  var e = raw.len
  while e > 0 and raw[e - 1] == ' ': dec e
  raw[0 ..< e]

suite "Writing and cursor":
  test "write advances cursor and lands characters":
    let s = newScreen(10, 3)
    s.writeString("hello")
    check s.cursor.row == 0
    check s.cursor.col == 5
    check s.trimmedLine(0) == "hello"

  test "newline/linefeed moves down and CR returns to col 0":
    let s = newScreen(10, 3)
    s.writeString("ab")
    s.carriageReturn()
    s.linefeed()
    s.writeString("cd")
    check s.cursor.row == 1
    check s.cursor.col == 2
    check s.trimmedLine(0) == "ab"
    check s.trimmedLine(1) == "cd"

  test "backspace retreats but does not erase":
    let s = newScreen(10, 1)
    s.writeString("abc")
    s.backspace()
    check s.cursor.col == 2
    check s.cellAt(0, 2).rune == uint32('c')

  test "tab advances to next multiple-of-8 stop":
    let s = newScreen(20, 1)
    s.writeChar('x')         # col 0 → 1
    s.tab()
    check s.cursor.col == 8
    s.tab()
    check s.cursor.col == 16

  test "autowrap wraps to next line on overflow":
    let s = newScreen(4, 2)
    s.writeString("abcd")     # fills row 0, cursor at col 3 with pendingWrap
    check s.cursor.pendingWrap
    s.writeChar('e')          # triggers wrap
    check s.cursor.row == 1
    check s.cursor.col == 1
    check s.trimmedLine(0) == "abcd"
    check s.trimmedLine(1) == "e"

  test "autowrap disabled clamps at last column":
    let s = newScreen(4, 2)
    s.modes.excl smAutoWrap
    s.writeString("abcdef")   # last letter overwrites col 3 repeatedly
    check s.cursor.row == 0
    check s.trimmedLine(1) == ""

suite "Scrolling":
  test "linefeed at bottom scrolls region up":
    let s = newScreen(4, 3)
    s.writeString("aaa"); s.carriageReturn(); s.linefeed()
    s.writeString("bbb"); s.carriageReturn(); s.linefeed()
    s.writeString("ccc"); s.carriageReturn(); s.linefeed()  # scrolls
    check s.trimmedLine(0) == "bbb"
    check s.trimmedLine(1) == "ccc"
    check s.trimmedLine(2) == ""

  test "scrolled-off lines land in scrollback":
    let s = newScreen(4, 2, scrollback = 10)
    s.writeString("one"); s.carriageReturn(); s.linefeed()
    s.writeString("two"); s.carriageReturn(); s.linefeed()  # 'one' → scrollback
    s.writeString("thr")
    check s.scrollbackLen == 1
    let old = s.scrollbackLine(0)
    var text = ""
    for c in old:
      if not c.isContinuation:
        text.add char(c.rune)
    check text.strip() == "one"

  test "scrollback respects cap":
    let s = newScreen(4, 1, scrollback = 3)
    for i in 0 ..< 10:
      s.writeChar(char(ord('0') + (i mod 10)))
      s.linefeed()
    check s.scrollbackLen == 3

  test "scroll region keeps outside lines untouched":
    let s = newScreen(4, 4)
    for r in 0 ..< 4:
      s.cursorTo(r, 0)
      s.writeChar(char(ord('A') + r))
    s.setScrollRegion(1, 2)           # regions rows 1 and 2; cursor moved to (1,0)
    s.cursorTo(2, 0)
    s.linefeed()                       # should scroll inside region only
    check s.trimmedLine(0) == "A"
    check s.trimmedLine(3) == "D"

suite "Erase":
  test "EL clear-to-end blanks from cursor":
    let s = newScreen(6, 1)
    s.writeString("abcdef")
    s.cursorTo(0, 3)
    s.eraseInLine(emToEnd)
    check s.trimmedLine(0) == "abc"

  test "EL clear-to-start blanks through cursor":
    let s = newScreen(6, 1)
    s.writeString("abcdef")
    s.cursorTo(0, 2)
    s.eraseInLine(emToStart)
    check s.lineText(0) == "   def"

  test "ED clear-all blanks the whole screen":
    let s = newScreen(4, 2)
    s.writeString("ab"); s.linefeed(); s.writeString("cd")
    s.eraseInDisplay(emAll)
    check s.trimmedLine(0) == ""
    check s.trimmedLine(1) == ""

suite "Insert/delete":
  test "insertChars shifts right and blanks":
    let s = newScreen(6, 1)
    s.writeString("abcdef")
    s.cursorTo(0, 2)
    s.insertChars(2)
    check s.lineText(0) == "ab  cd"

  test "deleteChars shifts left and pads":
    let s = newScreen(6, 1)
    s.writeString("abcdef")
    s.cursorTo(0, 2)
    s.deleteChars(2)
    check s.lineText(0) == "abef  "

  test "insertLines pushes rows down within scroll region":
    let s = newScreen(4, 4)
    for r in 0 ..< 4:
      s.cursorTo(r, 0)
      s.writeChar(char(ord('A') + r))
    s.cursorTo(1, 0)
    s.insertLines(1)
    check s.trimmedLine(0) == "A"
    check s.trimmedLine(1) == ""
    check s.trimmedLine(2) == "B"
    check s.trimmedLine(3) == "C"

  test "deleteLines pulls rows up":
    let s = newScreen(4, 4)
    for r in 0 ..< 4:
      s.cursorTo(r, 0)
      s.writeChar(char(ord('A') + r))
    s.cursorTo(1, 0)
    s.deleteLines(1)
    check s.trimmedLine(0) == "A"
    check s.trimmedLine(1) == "C"
    check s.trimmedLine(2) == "D"
    check s.trimmedLine(3) == ""

suite "Alternate screen":
  test "alt buffer is isolated from primary":
    let s = newScreen(4, 2)
    s.writeString("main")
    s.useAlternateScreen(true)
    s.cursorTo(0, 0)                           # xterm alt-screen convention: home
    check s.trimmedLine(0) == ""               # alt is blank
    s.writeString("alt")
    check s.trimmedLine(0) == "alt"
    s.useAlternateScreen(false)
    check s.trimmedLine(0) == "main"

suite "Save / restore cursor":
  test "save/restore round-trips position and attrs":
    let s = newScreen(10, 3)
    s.cursorTo(1, 4)
    s.applySgr([sgr(1), sgr(31)])
    s.saveCursor()
    s.cursorTo(2, 0)
    s.applySgr([])
    s.restoreCursor()
    check s.cursor.row == 1
    check s.cursor.col == 4
    check afBold in s.cursor.attrs.flags
    check s.cursor.attrs.fg.kind == ckIndexed
    check s.cursor.attrs.fg.index == 1

suite "SGR":
  test "reset clears everything":
    let s = newScreen(4, 1)
    s.applySgr([sgr(1), sgr(31), sgr(0)])
    check s.cursor.attrs.flags == {}
    check s.cursor.attrs.fg.kind == ckDefault

  test "basic 16-color foreground and background":
    let s = newScreen(4, 1)
    s.applySgr([sgr(33), sgr(44)])
    check s.cursor.attrs.fg.kind == ckIndexed and s.cursor.attrs.fg.index == 3
    check s.cursor.attrs.bg.kind == ckIndexed and s.cursor.attrs.bg.index == 4

  test "bright colors map to palette 8..15":
    let s = newScreen(4, 1)
    s.applySgr([sgr(91)])          # bright red → index 9
    check s.cursor.attrs.fg.kind == ckIndexed and s.cursor.attrs.fg.index == 9

  test "256-color via semicolon form":
    let s = newScreen(4, 1)
    s.applySgr([sgr(38), sgr(5), sgr(214)])
    check s.cursor.attrs.fg.kind == ckIndexed and s.cursor.attrs.fg.index == 214

  test "truecolor via semicolon form":
    let s = newScreen(4, 1)
    s.applySgr([sgr(38), sgr(2), sgr(10), sgr(20), sgr(30)])
    check s.cursor.attrs.fg.kind == ckRgb
    check s.cursor.attrs.fg.r == 10
    check s.cursor.attrs.fg.g == 20
    check s.cursor.attrs.fg.b == 30

  test "truecolor via colon-packed form (ITU T.416 with empty color space)":
    let s = newScreen(4, 1)
    # Equivalent to CSI 38:2::10:20:30 m
    s.applySgr([sgr(38, @[2, -1, 10, 20, 30])])
    check s.cursor.attrs.fg.kind == ckRgb
    check s.cursor.attrs.fg.r == 10 and s.cursor.attrs.fg.b == 30

  test "colon-packed 256-color":
    let s = newScreen(4, 1)
    s.applySgr([sgr(48, @[5, 123])])
    check s.cursor.attrs.bg.kind == ckIndexed and s.cursor.attrs.bg.index == 123

suite "Resize":
  test "growing preserves content and adds blank rows":
    let s = newScreen(4, 2)
    s.writeString("hi")
    s.linefeed(); s.carriageReturn()
    s.writeString("yo")
    s.resize(6, 4)
    check s.cols == 6 and s.rows == 4
    check s.trimmedLine(0) == "hi"
    check s.trimmedLine(1) == "yo"
    check s.trimmedLine(3) == ""

  test "shrinking rows pushes oldest to scrollback":
    let s = newScreen(4, 3, scrollback = 10)
    s.writeString("aaa"); s.linefeed(); s.carriageReturn()
    s.writeString("bbb"); s.linefeed(); s.carriageReturn()
    s.writeString("ccc")
    s.resize(4, 2)
    check s.scrollbackLen >= 1

suite "Wide characters":
  test "wide char occupies two cells and advances by 2":
    let s = newScreen(6, 1)
    s.writeRune(0x4E2D, 2)   # '中'
    check s.cellAt(0, 0).width == 2
    check s.cellAt(0, 1).isContinuation
    check s.cursor.col == 2

  test "wide char at end of line wraps to next line":
    let s = newScreen(4, 2)
    s.writeString("abc")          # cursor at col 3 with pendingWrap after last col? col=3 no pending
    s.cursorTo(0, 3)
    s.writeRune(0x4E2D, 2)        # would overflow; wrap
    check s.cursor.row == 1
    check s.cellAt(1, 0).width == 2
