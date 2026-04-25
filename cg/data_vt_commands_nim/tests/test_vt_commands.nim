import std/unittest
import vt_commands_lib

proc p(v: int): DispatchParam = param(v)

proc bytesOf(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

suite "CSI cursor movement":
  test "CSI A defaults count to 1 and moves up":
    let c = translateCsi(@[], @[], byte('A'))
    check c.kind == cmdCursorUp
    check c.count == 1

  test "CSI 5 A moves up 5":
    let c = translateCsi(@[p(5)], @[], byte('A'))
    check c.count == 5

  test "CSI B C D E F map to directional moves":
    check translateCsi(@[p(2)], @[], byte('B')).kind == cmdCursorDown
    check translateCsi(@[p(2)], @[], byte('C')).kind == cmdCursorForward
    check translateCsi(@[p(2)], @[], byte('D')).kind == cmdCursorBackward
    check translateCsi(@[p(2)], @[], byte('E')).kind == cmdCursorNextLine
    check translateCsi(@[p(2)], @[], byte('F')).kind == cmdCursorPrevLine

  test "CSI G moves to column (1-indexed input → 0-indexed output)":
    let c = translateCsi(@[p(10)], @[], byte('G'))
    check c.kind == cmdCursorToColumn
    check c.absCol == 9

  test "CSI H without params goes to (0, 0)":
    let c = translateCsi(@[], @[], byte('H'))
    check c.kind == cmdCursorTo
    check c.row == 0 and c.col == 0

  test "CSI 5;10 H → (4, 9)":
    let c = translateCsi(@[p(5), p(10)], @[], byte('H'))
    check c.row == 4 and c.col == 9

suite "CSI erase":
  test "CSI J defaults to emToEnd":
    let c = translateCsi(@[], @[], byte('J'))
    check c.kind == cmdEraseInDisplay
    check c.eraseMode == emToEnd

  test "CSI 1 J → emToStart":
    check translateCsi(@[p(1)], @[], byte('J')).eraseMode == emToStart

  test "CSI 2 J → emAll":
    check translateCsi(@[p(2)], @[], byte('J')).eraseMode == emAll

  test "CSI K defaults to line-to-end":
    let c = translateCsi(@[], @[], byte('K'))
    check c.kind == cmdEraseInLine
    check c.eraseMode == emToEnd

suite "CSI scroll/insert/delete":
  test "CSI 3 L inserts 3 lines":
    let c = translateCsi(@[p(3)], @[], byte('L'))
    check c.kind == cmdInsertLines and c.count == 3

  test "CSI 2 @ inserts 2 chars":
    let c = translateCsi(@[p(2)], @[], byte('@'))
    check c.kind == cmdInsertChars and c.count == 2

  test "CSI r without params sets region from top to end":
    let c = translateCsi(@[], @[], byte('r'))
    check c.kind == cmdSetScrollRegion
    check c.regionTop == 0
    check c.regionBottom == DefaultScrollRegionBottom

  test "CSI 5;20 r sets region (4, 19)":
    let c = translateCsi(@[p(5), p(20)], @[], byte('r'))
    check c.regionTop == 4 and c.regionBottom == 19

suite "CSI SGR":
  test "CSI m with no params carries empty SGR list":
    let c = translateCsi(@[], @[], byte('m'))
    check c.kind == cmdSetSgr
    check c.sgrParams.len == 0

  test "CSI 1;31 m preserves params in order":
    let c = translateCsi(@[p(1), p(31)], @[], byte('m'))
    check c.sgrParams.len == 2
    check c.sgrParams[0].value == 1
    check c.sgrParams[1].value == 31

  test "colon-form sub-params survive translation":
    let c = translateCsi(@[param(38, @[2, -1, 255, 100, 0])], @[], byte('m'))
    check c.sgrParams[0].subParams == @[2, -1, 255, 100, 0]

suite "CSI modes":
  test "CSI ? 25 h is DECSET private show-cursor":
    let c = translateCsi(@[p(25)], @[byte('?')], byte('h'))
    check c.kind == cmdSetMode
    check c.privateMode
    check c.modeCode == 25

  test "CSI 4 l is reset IRM (non-private)":
    let c = translateCsi(@[p(4)], @[], byte('l'))
    check c.kind == cmdResetMode
    check not c.privateMode
    check c.modeCode == 4

  test "CSI g clears current tab stop; CSI 3 g clears all":
    check translateCsi(@[], @[], byte('g')).kind == cmdClearTabStop
    check translateCsi(@[p(3)], @[], byte('g')).kind == cmdClearAllTabStops

suite "ESC sequences":
  test "ESC 7 / 8 → save / restore":
    check translateEsc(@[], byte('7')).kind == cmdSaveCursor
    check translateEsc(@[], byte('8')).kind == cmdRestoreCursor

  test "ESC M → reverse index, ESC D → line feed":
    check translateEsc(@[], byte('M')).kind == cmdReverseIndex
    check translateEsc(@[], byte('D')).kind == cmdLineFeed

  test "ESC c → reset":
    check translateEsc(@[], byte('c')).kind == cmdReset

  test "ESC with intermediate falls through to unknown":
    check translateEsc(@[byte('(')], byte('B')).kind == cmdUnknown

suite "C0 execute":
  test "BS, HT, LF, CR, BEL map to named commands":
    check translateExecute(0x08'u8).kind == cmdBackspace
    check translateExecute(0x09'u8).kind == cmdHorizontalTab
    check translateExecute(0x0A'u8).kind == cmdLineFeed
    check translateExecute(0x0D'u8).kind == cmdCarriageReturn
    check translateExecute(0x07'u8).kind == cmdBell

  test "VT, FF, NEL also map to line feed":
    check translateExecute(0x0B'u8).kind == cmdLineFeed
    check translateExecute(0x0C'u8).kind == cmdLineFeed
    check translateExecute(0x85'u8).kind == cmdLineFeed

  test "unknown byte surfaces as cmdExecute with raw byte":
    let c = translateExecute(0x11'u8)
    check c.kind == cmdExecute
    check c.rawByte == 0x11'u8

suite "OSC":
  test "OSC 0 ; text → SetTitle":
    let c = translateOsc(bytesOf("0;My Title"))
    check c.kind == cmdSetTitle
    check c.text == "My Title"

  test "OSC 2 ; text → SetTitle":
    let c = translateOsc(bytesOf("2;another"))
    check c.kind == cmdSetTitle
    check c.text == "another"

  test "OSC 1 ; text → SetIconName":
    let c = translateOsc(bytesOf("1;icon"))
    check c.kind == cmdSetIconName
    check c.text == "icon"

  test "OSC 8 ; params ; uri → Hyperlink":
    let c = translateOsc(bytesOf("8;id=42;https://example.invalid/x"))
    check c.kind == cmdHyperlink
    check c.hyperlinkParams == "id=42"
    check c.uri == "https://example.invalid/x"

  test "OSC 999 (unrecognized) → ignored":
    check translateOsc(bytesOf("999;whatever")).kind == cmdIgnored

  test "OSC with no numeric prefix → unknown":
    check translateOsc(bytesOf("bogus")).kind == cmdUnknown

  test "OSC 133 Shell Integration":
    check translateOsc(bytesOf("133;A")).kind == cmdShellPromptStart
    check translateOsc(bytesOf("133;B")).kind == cmdShellCommandStart
    check translateOsc(bytesOf("133;C")).kind == cmdShellCommandExecuted
    let d = translateOsc(bytesOf("133;D;12"))
    check d.kind == cmdShellCommandFinished
    check d.exitCode == 12

suite "Print":
  test "translatePrint carries rune + width":
    let c = translatePrint(0x4E2D'u32, 2)
    check c.kind == cmdPrint
    check c.rune == 0x4E2D'u32
    check c.width == 2
