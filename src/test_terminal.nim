## Integration tests for the Terminal pipeline.
##
## These tests verify that VT sequences result in the correct
## screen buffer state and damage tracking.

import std/[unittest, strutils, options]
import terminal

# ---------------------------------------------------------------------------
# Mock Backend for Logic Tests
# ---------------------------------------------------------------------------

type MockBackend = ref object
  data: seq[byte]

proc ptyOpen(b: MockBackend): tuple[handle: int, slaveId: string] = (1, "mock")
proc ptyRead(b: MockBackend, h: int, buf: var openArray[byte]): int =
  if b.data.len == 0: return 0
  let n = min(buf.len, b.data.len)
  for i in 0 ..< n: buf[i] = b.data[i]
  if n > 0:
    for i in 0 ..< b.data.len - n: b.data[i] = b.data[i + n]
    b.data.setLen(b.data.len - n)
  n
proc ptyWrite(b: MockBackend, h: int, data: openArray[byte]): int = data.len
proc ptyResize(b: MockBackend, h, r, c: int) = discard
proc ptySignal(b: MockBackend, p, s: int) = discard
proc ptyWait(b: MockBackend, p: int): int = 0
proc ptyClose(b: MockBackend, h: int) = discard
proc ptySetSize(b: MockBackend, h, r, c: int) = discard
proc ptyForkExec(b: MockBackend, s, p: string, a: openArray[string], c: string): int = 123

# ---------------------------------------------------------------------------
# Mock Terminal Initialization
# ---------------------------------------------------------------------------

proc newMockTerminal*(rows, cols: int): Terminal =
  result = Terminal(
    backend: nil,
    decoder: newUtf8Decoder(),
    parser: newVtParser(),
    screen: newScreen(cols, rows, 100),
    inputMode: newInputMode(),
    damage: newDamage(rows),
    selection: newSelection(),
    viewport: newViewport(rows),
    drag: newDragController(rows),
    shortcuts: newShortcutMap(),
    history: newSemanticHistory(),
    diagnostics: newVtDiagnostics(16),
    activeLink: none(ActiveLink),
    outputFootprint: newOutputFootprint(),
  )
  result.async = newAsyncPty[terminal.CurrentBackend](nil, 1)

proc feed*(t: Terminal, s: string) =
  if s.len == 0: return
  t.feedBytes(s.toOpenArrayByte(0, s.high))

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "terminal pipeline":

  test "plain printf lays out cells":
    let t = newMockTerminal(3, 10)
    t.feed("hello\r\nworld")
    check t.screen.lineText(0).strip() == "hello"
    check t.screen.lineText(1).strip() == "world"

  test "CSI cursor-back overwrites tail":
    let t = newMockTerminal(2, 10)
    t.feed("Abc\e[2Dxx")
    check t.screen.lineText(0).strip() == "Axx"

  test "erase-in-line to end clears tail":
    let t = newMockTerminal(2, 10)
    t.feed("abcdef\e[2D\e[0K")
    check t.screen.lineText(0).strip() == "abcd"

  test "absolute cursor position CSI H":
    let t = newMockTerminal(5, 10)
    t.feed("\e[2;3HX")
    check t.screen.cellAt(1, 2).rune == uint32('X')

  test "SGR bold sets attr flag on written cells":
    let t = newMockTerminal(2, 10)
    t.feed("\e[1mbold\e[0mplain")
    check afBold in t.screen.cellAt(0, 0).attrs.flags
    check afBold notin t.screen.cellAt(0, 4).attrs.flags

  test "utf-8 multibyte produces one rune":
    let t = newMockTerminal(2, 10)
    t.feed("\xC3\xA9X") 
    check t.screen.cellAt(0, 0).rune == 0x00E9'u32
    check t.screen.cellAt(0, 1).rune == uint32('X')

  test "utf-8 box drawing survives VT parser C1 range":
    let t = newMockTerminal(2, 10)
    t.feed("┌─┐")
    check t.screen.cellAt(0, 0).rune == 0x250C'u32
    check t.screen.cellAt(0, 1).rune == 0x2500'u32
    check t.screen.cellAt(0, 2).rune == 0x2510'u32

  test "alternate screen exit restores primary without stale app rows":
    let t = newMockTerminal(4, 10)
    t.feed("shell\r\n")
    t.feed("\e[?1049h┌─┐\e[?1049l")
    check not t.screen.usingAlt
    check t.screen.lineText(0).strip() == "shell"
    check t.screen.lineText(1).strip() == ""
    check t.screen.lineText(2).strip() == ""

  test "alternate screen mode works inside combined DECSET list":
    let t = newMockTerminal(4, 10)
    t.feed("shell\r\n")
    t.feed("\e[?1;1049;2004happ\e[?1;1049;2004l")
    check not t.screen.usingAlt
    check not t.inputMode.cursorApp
    check not t.inputMode.bracketedPaste
    check t.screen.lineText(0).strip() == "shell"
    check t.screen.lineText(1).strip() == ""

  test "alternate screen transition clears transient selection":
    let t = newMockTerminal(4, 10)
    t.feed("shell")
    t.selection.start(point(0, 0))
    t.selection.update(point(0, 2))
    check t.selection.isActive
    t.feed("\e[?1049h")
    check not t.selection.isActive

  test "inline command prompt resumes below output footprint":
    let t = newMockTerminal(6, 20)
    t.feed("sh$ claude\r\n")
    t.feed("\e]133;C\e\\")
    t.feed("\e[3;1HClaude UI")
    t.feed("\e[2;1Hprompt")
    t.feed("\e]133;D;0\e\\")
    t.feed("sh$ ")
    check t.screen.lineText(1).strip() == "prompt"
    check t.screen.lineText(2).strip() == "Claude UI"
    check t.screen.lineText(3).strip() == "sh$"

  test "cursor restore before prompt resumes below drawn footprint":
    let t = newMockTerminal(6, 20)
    t.feed("sh$ claude\r\n")
    t.feed("\e7")
    t.feed("\e[2J")
    t.feed("\e[3;1HClaude UI")
    t.feed("\e[5;1HStatus")
    t.feed("\e8")
    t.feed("sh$ ")
    check t.screen.lineText(2).strip() == "Claude UI"
    check t.screen.lineText(4).strip() == "Status"
    check t.screen.lineText(5).strip() == "sh$"

  test "cursor restore during inline repaint does not push input downward":
    let t = newMockTerminal(8, 30)
    t.feed("\e7")
    t.feed("\e[1;1HEnter submit")
    t.feed("\e[3;1Hf")
    t.feed("\e8")
    t.feed("\e[3;1Hfr")

    check t.screen.lineText(0).strip() == "Enter submit"
    check t.screen.lineText(2).strip() == "fr"
    check t.screen.lineText(3).strip() == ""

  test "DECTCEM toggles terminal cursor visibility":
    let t = newMockTerminal(4, 20)
    check t.screen.cursor.visible
    t.feed("\e[?25l")
    check not t.screen.cursor.visible
    t.feed("\e[?25h")
    check t.screen.cursor.visible

  test "DECSCUSR changes cursor style":
    let t = newMockTerminal(4, 20)
    check t.screen.cursor.style == csBlock
    t.feed("\e[4 q")
    check t.screen.cursor.style == csUnderline
    t.feed("\e[6 q")
    check t.screen.cursor.style == csBar

  test "SGR 4:0 clears underline through parser pipeline":
    let t = newMockTerminal(4, 20)
    t.feed("\e[4mA")
    check afUnderline in t.screen.absoluteRowAt(0)[0].attrs.flags
    t.feed("\e[4:0mB")
    check afUnderline notin t.screen.absoluteRowAt(0)[1].attrs.flags

  test "xterm key modifier options do not apply SGR underline":
    let t = newMockTerminal(4, 20)
    t.feed("\e[>4;2mA")
    check afUnderline notin t.screen.absoluteRowAt(0)[0].attrs.flags
    check afDim notin t.screen.absoluteRowAt(0)[0].attrs.flags

  test "kitty keyboard enable does not restore cursor":
    let t = newMockTerminal(5, 20)
    t.feed("\e7")
    t.feed("\e[3;1Hopen")
    t.feed("\e[>1u")
    t.feed("code")
    check t.screen.lineText(0).strip() == ""
    check t.screen.lineText(2).strip() == "opencode"

  test "DECRQM reports unsupported modern modes instead of timing out":
    let t = newMockTerminal(5, 20)
    t.feed("\e[?2026$p")
    check t.async.queueLen > 0

  test "OSC 52 ignores malformed base64 without hiding callback failures":
    let t = newMockTerminal(5, 20)
    var called = false
    t.onClipboardRequest = proc(selector, text: string) =
      called = true

    t.feed("\e]52;c;@@@\a")
    check not called

    t.feed("\e]52;c;aGVsbG8=\a")
    check called

    t.onClipboardRequest = proc(selector, text: string) =
      raise newException(ValueError, "callback failed")
    expect ValueError:
      t.feed("\e]52;c;aGVsbG8=\a")

  test "DECRQSS requests queue state-string replies":
    let t = newMockTerminal(5, 20)
    t.feed("\eP$qm\e\\")
    check t.async.queueLen > 0
    check t.diagnostics.snapshot().queryCount == 1

  test "unknown control sequences are retained for diagnostics":
    let t = newMockTerminal(5, 20)
    t.feed("\e[123x")
    let snap = t.diagnostics.snapshot()
    check snap.unknownCount == 1
    check snap.events[^1].name == "unknown"

  test "button-event and SGR mouse modes compose":
    let t = newMockTerminal(5, 20)
    t.feed("\e[?1002h\e[?1006h")
    check t.inputMode.mouseMode == mmButtonEvent
    check t.inputMode.sgrMouse
    discard t.sendMouse(mouse(meDrag, mbLeft, 1, 2))
    check t.async.queueLen > 0

  test "full display erase alone does not push prompt to bottom":
    let t = newMockTerminal(6, 20)
    t.feed("sh$ claude\r\n")
    t.feed("\e7")
    t.feed("\e[2J")
    t.feed("\e[3;1HClaude UI")
    t.feed("\e8")
    t.feed("sh$ ")
    check t.screen.lineText(2).strip() == "Claude UI"
    check t.screen.lineText(3).strip() == "sh$"
    check t.screen.lineText(5).strip() == ""

suite "damage tracking":

  test "single-line print marks only that row dirty":
    let t = newMockTerminal(5, 20)
    t.feed("hello")
    check t.damage.anyDirty
    check t.damage.isDirty(0)
    check t.damage.isDirty(1) == false

  test "multi-line print marks each written row":
    let t = newMockTerminal(5, 10)
    t.feed("a\r\nb\r\nc")
    check t.damage.isDirty(0)
    check t.damage.isDirty(1)
    check t.damage.isDirty(2)
    check t.damage.isDirty(3) == false

  test "erase-in-display triggers fullRepaint":
    let t = newMockTerminal(3, 10)
    t.feed("abc\e[2J")
    check t.damage.fullRepaint

  test "scroll-triggering linefeed damages all rows":
    let t = newMockTerminal(3, 10)
    t.feed("a\r\nb\r\nc\r\nd")
    check t.damage.fullRepaint

suite "selection text extraction":

  test "stream selection pulls partial row":
    let t = newMockTerminal(3, 20)
    t.feed("hello world")
    t.selection.start(point(0, 6))
    t.selection.update(point(0, 10))
    check t.selectionText == "world"

  test "block selection pulls rectangle":
    let t = newMockTerminal(3, 10)
    t.feed("abcdefg\r\nhijklmn")
    t.selection.start(point(0, 2), smBlock)
    t.selection.update(point(1, 4))
    check t.selectionText == "cde\njkl"

suite "theming and dynamic colors":

  test "set palette color OSC 4":
    let t = newMockTerminal(2, 10)
    t.feed("\e]4;1;rgb:ff/00/00\e\\")
    check t.screen.theme.ansi[1].r == 255

  test "set background color OSC 11":
    let t = newMockTerminal(2, 10)
    t.feed("\e]11;rgb:ff/00/ff\e\\")
    check t.screen.theme.background.r == 255
    check t.screen.theme.background.b == 255

suite "semantic history":

  test "OSC 133 sequences populate semantic history":
    let t = newMockTerminal(10, 80)
    # Start prompt
    t.feed("\e]133;A\e\\")
    t.feed("$ ")
    # Command start
    t.feed("\e]133;B\e\\")
    t.feed("echo hello\r\n")
    # Command executed
    t.feed("\e]133;C\e\\")
    t.feed("hello\r\n")
    # Command finished (exit 0)
    t.feed("\e]133;D;0\e\\")
    
    check t.history.blocks.len == 1
    let b = t.history.blocks[0]
    check b.promptStartRow == 0
    check b.commandStartRow == 0
    check b.outputStartRow == 1
    check b.outputEndRow == 2
    check b.exitCode.get() == 0
