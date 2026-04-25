import std/unittest
import vt_parser_lib

# -----------------------------------------------------------------
# Harness: collect every emitted event into a list for inspection.
# -----------------------------------------------------------------

type EventLog = ref object
  events: seq[VtEvent]

proc newLog(): EventLog = EventLog(events: @[])

proc collector(log: EventLog): VtEmit =
  result = proc (ev: VtEvent) =
    log.events.add ev

proc run(data: string; utf8Mode = true): seq[VtEvent] =
  var p = newVtParser(utf8Mode = utf8Mode)
  let log = newLog()
  p.feed(data, collector(log))
  log.events

# Utility: render a Print/Execute/DcsPut event's byte for readable assertions.
proc bv(ev: VtEvent): byte =
  case ev.kind
  of vePrint, veExecute, veDcsPut: ev.byteVal
  else: 0

suite "Ground state":
  test "plain ASCII prints one event per byte":
    let evs = run("abc")
    check evs.len == 3
    check evs[0].kind == vePrint and char(bv(evs[0])) == 'a'
    check evs[2].kind == vePrint and char(bv(evs[2])) == 'c'

  test "C0 controls execute":
    let evs = run("a\x08b\x0Ac")
    # 'a', BS, 'b', LF, 'c'
    check evs.len == 5
    check evs[1].kind == veExecute and bv(evs[1]) == 0x08
    check evs[3].kind == veExecute and bv(evs[3]) == 0x0A

  test "DEL (0x7F) prints in ground":
    # In ground, 7F falls into the print branch (caller decides how to render).
    # This matches xterm behavior where 7F is typically ignored by renderer,
    # but the parser still surfaces it as a byte.
    let evs = run("\x7F")
    check evs.len == 1
    check evs[0].kind == vePrint

suite "Escape sequences":
  test "simple ESC final dispatches":
    # ESC c  (RIS — reset)
    let evs = run("\x1Bc")
    check evs.len == 1
    check evs[0].kind == veEscDispatch
    check evs[0].escFinal == byte('c')
    check evs[0].escIntermediates.len == 0

  test "ESC with intermediate":
    # ESC ( B  (designate G0 = US ASCII)
    let evs = run("\x1B(B")
    check evs.len == 1
    check evs[0].kind == veEscDispatch
    check evs[0].escFinal == byte('B')
    check evs[0].escIntermediates == @[byte('(')]

  test "ESC cancelled by CAN returns to ground":
    let evs = run("\x1B\x18a")
    # CAN emits Execute then ground prints 'a'
    check evs.len == 2
    check evs[0].kind == veExecute and bv(evs[0]) == 0x18
    check evs[1].kind == vePrint and char(bv(evs[1])) == 'a'

suite "CSI sequences":
  test "CSI with no params":
    let evs = run("\x1B[H")  # cursor home
    check evs.len == 1
    check evs[0].kind == veCsiDispatch
    check evs[0].final == byte('H')
    check evs[0].params.len == 0

  test "CSI with single param":
    let evs = run("\x1B[5A")
    check evs.len == 1
    check evs[0].params.len == 1
    check evs[0].params[0].value == 5
    check evs[0].final == byte('A')

  test "CSI with multiple params":
    let evs = run("\x1B[1;31;42m")
    check evs.len == 1
    let ev = evs[0]
    check ev.kind == veCsiDispatch
    check ev.final == byte('m')
    check ev.params.len == 3
    check ev.params[0].value == 1
    check ev.params[1].value == 31
    check ev.params[2].value == 42
    check not ev.ignored

  test "CSI with missing (defaulted) leading param":
    let evs = run("\x1B[;5H")
    check evs.len == 1
    check evs[0].params.len == 2
    check evs[0].params[0].value == -1    # defaulted
    check evs[0].params[1].value == 5
    check paramOr(evs[0].params, 0, 1) == 1
    check paramOr(evs[0].params, 1, 1) == 5

  test "CSI with private-marker ('?') intermediate":
    # DEC private mode set: CSI ? 25 h  (show cursor)
    let evs = run("\x1B[?25h")
    check evs.len == 1
    let ev = evs[0]
    check ev.final == byte('h')
    check ev.params.len == 1
    check ev.params[0].value == 25
    check ev.intermediates == @[byte('?')]

  test "CSI with sub-parameters (colon-separated, ITU T.416-style)":
    # Truecolor foreground via colon form: CSI 38:2::255:100:0 m
    let evs = run("\x1B[38:2::255:100:0m")
    check evs.len == 1
    let ev = evs[0]
    check ev.final == byte('m')
    check ev.params.len == 1
    check ev.params[0].value == 38
    check ev.params[0].subParams.len == 5
    check ev.params[0].subParams[0] == 2
    check ev.params[0].subParams[1] == -1      # empty sub-param
    check ev.params[0].subParams[2] == 255
    check ev.params[0].subParams[3] == 100
    check ev.params[0].subParams[4] == 0

  test "CSI cancelled mid-sequence by ESC then re-issued":
    # Partial CSI, aborted by ESC, then a fresh full CSI.
    let evs = run("\x1B[12;\x1B[H")
    # Only the second (completed) CSI should dispatch.
    var csiCount = 0
    for e in evs:
      if e.kind == veCsiDispatch: inc csiCount
    check csiCount == 1
    check evs[^1].final == byte('H')

suite "OSC sequences":
  test "OSC terminated by BEL":
    # OSC 0 ; window-title BEL   (set window title)
    let evs = run("\x1B]0;hello\x07")
    check evs.len == 1
    check evs[0].kind == veOscDispatch
    check evs[0].bellTerminated
    # Payload: "0;hello"
    var s = ""
    for b in evs[0].oscData: s.add char(b)
    check s == "0;hello"

  test "OSC terminated by 7-bit ST (ESC \\)":
    let evs = run("\x1B]2;title\x1B\\")
    check evs.len == 1
    check evs[0].kind == veOscDispatch
    check not evs[0].bellTerminated
    var s = ""
    for b in evs[0].oscData: s.add char(b)
    check s == "2;title"

  test "OSC terminated by 8-bit ST (0x9C)":
    let evs = run("\x1B]8;;https://example\x9C", utf8Mode = false)
    check evs.len == 1
    check evs[0].kind == veOscDispatch
    check evs[0].oscData.len > 0

suite "Legacy 8-bit C1 controls":
  test "8-bit CSI works when UTF-8 mode is disabled":
    let evs = run("\x9B31m", utf8Mode = false)
    check evs.len == 1
    check evs[0].kind == veCsiDispatch
    check evs[0].params.len == 1
    check evs[0].params[0].value == 31
    check evs[0].final == byte('m')

  test "8-bit CSI bytes print in default UTF-8 mode":
    let evs = run("\x9B31m")
    check evs.len == 4
    check evs[0].kind == vePrint and bv(evs[0]) == 0x9B

suite "DCS sequences":
  test "DCS hook + put + unhook":
    # DCS 1 $ q m ST   — typical DECRQSS-style
    let evs = run("\x1BP1$qm\x1B\\")
    var hooked = false
    var unhooked = false
    var putBytes: seq[byte]
    for e in evs:
      case e.kind
      of veDcsHook:
        hooked = true
        check e.params.len == 1
        check e.params[0].value == 1
        check e.intermediates == @[byte('$')]
        check e.final == byte('q')
      of veDcsPut:
        putBytes.add e.byteVal
      of veDcsUnhook:
        unhooked = true
      else: discard
    check hooked
    check unhooked
    check putBytes == @[byte('m')]

suite "Stream resumption":
  test "split across feed boundaries":
    # Split a CSI SGR in half; parser state must persist.
    var p = newVtParser()
    let log = newLog()
    p.feed("\x1B[1;", collector(log))
    check log.events.len == 0
    check not p.inGround
    p.feed("31m", collector(log))
    check log.events.len == 1
    check log.events[0].kind == veCsiDispatch
    check log.events[0].final == byte('m')
    check p.inGround

  test "parser returns to ground after each complete sequence":
    var p = newVtParser()
    let log = newLog()
    p.feed("\x1B[H\x1B[2J", collector(log))
    check p.inGround
    check log.events.len == 2
    check log.events[0].final == byte('H')
    check log.events[1].final == byte('J')

suite "Overflow and error paths":
  test "excess parameters flag sequence as ignored but still dispatch":
    # Build a CSI with MaxParams+5 params.
    var s = "\x1B["
    for i in 0 ..< MaxParams + 5:
      if i > 0: s.add ';'
      s.add '1'
    s.add 'm'
    let evs = run(s)
    check evs.len == 1
    check evs[0].kind == veCsiDispatch
    check evs[0].ignored
    check evs[0].params.len == MaxParams

  test "CSI with unexpected '<' after param enters ignore and no dispatch":
    # '<' (0x3C) appearing in sCsiParam should kill the sequence.
    let evs = run("\x1B[1<m")
    # The 'm' terminates the ignored sequence without dispatching.
    var csiCount = 0
    for e in evs:
      if e.kind == veCsiDispatch: inc csiCount
    check csiCount == 0

suite "UTF-8 passthrough":
  test "multi-byte UTF-8 prints each byte":
    # 'é' is 0xC3 0xA9 — the parser passes bytes through; UTF-8 reassembly
    # is the caller's responsibility.
    let evs = run("é")
    check evs.len == 2
    check evs[0].kind == vePrint and bv(evs[0]) == 0xC3
    check evs[1].kind == vePrint and bv(evs[1]) == 0xA9

  test "box drawing bytes are not mistaken for C1 controls":
    # U+2500 BOX DRAWINGS LIGHT HORIZONTAL: E2 94 80.
    let evs = run("─")
    check evs.len == 3
    check evs[0].kind == vePrint and bv(evs[0]) == 0xE2
    check evs[1].kind == vePrint and bv(evs[1]) == 0x94
    check evs[2].kind == vePrint and bv(evs[2]) == 0x80
