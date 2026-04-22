## Project glue: assemble PTY host, UTF-8 decoder, VT parser, VT command
## translator, and screen buffer into a single `Terminal` pipeline.
##
## Data flow:
##   PTY master bytes
##     → VtParser (state machine: print / execute / csi / esc / osc)
##     → vePrint bytes routed through Utf8Decoder → (rune, width)
##     → VtCommand typed translation
##     → Screen buffer mutations
##
## This file is not a widget — it is project-specific wiring between
## five independent widgets plus the project-level POSIX driver.

import std/posix
import ../cg/backend_pty_host_nim/src/pty_host_lib
import ../cg/universal_utf8_decoder_nim/src/utf8_decoder_lib
import ../cg/data_vt_parser_nim/src/vt_parser_lib
import ../cg/data_vt_commands_nim/src/vt_commands_lib
import ../cg/data_screen_buffer_nim/src/screen_buffer_lib
import ../cg/data_keyboard_vt_input_nim/src/keyboard_vt_input_lib
import ../cg/universal_damage_tracker_nim/src/damage_tracker_lib
import pty/posix_backend

export pty_host_lib, screen_buffer_lib, posix_backend, keyboard_vt_input_lib,
       damage_tracker_lib

type
  Terminal* = ref object
    ## A live child process attached to an in-memory screen grid.
    backend*: PosixBackend
    host*: PtyHost[PosixBackend]
    decoder: Utf8Decoder
    parser: VtParser
    screen*: Screen
    keyboardMode*: KeyboardMode
    damage*: Damage

proc newTerminal*(
    program: string,
    args: openArray[string] = [],
    cwd: string = "",
    cols: int = 80,
    rows: int = 24,
    scrollback: int = DefaultScrollback,
): Terminal =
  ## Spawn `program` under a pseudo-terminal and attach a fresh screen of
  ## the given dimensions. The child inherits the pty dimensions via
  ## TIOCSWINSZ; subsequent `resize` calls update both sides.
  let backend = newPosixBackend()
  let host = spawn(backend, program, args, cwd, rows, cols)
  Terminal(
    backend: backend,
    host: host,
    decoder: newUtf8Decoder(),
    parser: newVtParser(),
    screen: newScreen(cols, rows, scrollback),
    keyboardMode: newKeyboardMode(),
    damage: newDamage(rows),
  )

# ---------------------------------------------------------------------------
# Cross-widget type shims
# ---------------------------------------------------------------------------

func toDispatchParams(src: seq[VtParam]): seq[DispatchParam] =
  result = newSeqOfCap[DispatchParam](src.len)
  for p in src:
    result.add DispatchParam(value: p.value, subParams: p.subParams)

func toSgrParams(src: seq[DispatchParam]): seq[SgrParam] =
  result = newSeqOfCap[SgrParam](src.len)
  for p in src:
    result.add SgrParam(value: p.value, subParams: p.subParams)

func toScreenErase(m: vt_commands_lib.EraseMode): screen_buffer_lib.EraseMode =
  case m
  of vt_commands_lib.emToEnd:   screen_buffer_lib.emToEnd
  of vt_commands_lib.emToStart: screen_buffer_lib.emToStart
  of vt_commands_lib.emAll:     screen_buffer_lib.emAll

# ---------------------------------------------------------------------------
# Command application
# ---------------------------------------------------------------------------

proc applyMode(t: Terminal, code: int, private: bool, set: bool) =
  if private:
    case code
    of 1:
      # DECCKM — application cursor keys.
      t.keyboardMode.cursorApp = set
    of 7:
      if set: t.screen.modes.incl smAutoWrap
      else:   t.screen.modes.excl smAutoWrap
    of 47, 1047:
      t.screen.useAlternateScreen(set)
      t.damage.markAll
    of 66:
      # DECNKM (private-mode form of DECKPAM/DECKPNM).
      t.keyboardMode.keypadApp = set
    of 1048:
      if set: t.screen.saveCursor() else: t.screen.restoreCursor()
    of 1049:
      if set:
        t.screen.saveCursor()
        t.screen.useAlternateScreen(true)
      else:
        t.screen.useAlternateScreen(false)
        t.screen.restoreCursor()
      t.damage.markAll
    else: discard
  else:
    case code
    of 4:
      if set: t.screen.modes.incl smInsert
      else:   t.screen.modes.excl smInsert
    else: discard

proc apply(t: Terminal, cmd: VtCommand) =
  # Snapshot the cursor row before the command so we can flag the
  # starting row for commands that may shift the cursor as a side
  # effect (print-with-wrap, linefeed, tab across cells).
  let rowBefore = t.screen.cursor.row

  case cmd.kind
  of cmdPrint:
    t.screen.writeRune(cmd.rune, cmd.width)
    t.damage.markRow(rowBefore)
    t.damage.markRow(t.screen.cursor.row)  # may have wrapped
  of cmdExecute:        discard  # unspecialized C0/C1 byte — ignore
  of cmdLineFeed:
    t.screen.linefeed()
    # Conservative: linefeed at the bottom of the scroll region scrolls
    # the whole region. We don't have a cheap pre/post compare, so flag
    # both the old row (in case of trailing whitespace) and mark all
    # when cursor didn't actually move down (scroll happened).
    t.damage.markRow(rowBefore)
    if t.screen.cursor.row == rowBefore:
      t.damage.markAll
    else:
      t.damage.markRow(t.screen.cursor.row)
  of cmdReverseIndex:
    if t.screen.cursor.row == t.screen.scrollTop:
      t.screen.scrollDown(1)
      t.damage.markAll
    else:
      t.screen.cursorUp(1)
  of cmdCarriageReturn: t.screen.carriageReturn()
  of cmdBackspace:      t.screen.backspace()
  of cmdHorizontalTab:  t.screen.tab()
  of cmdBell:           discard
  of cmdCursorUp:       t.screen.cursorUp(cmd.count)
  of cmdCursorDown:     t.screen.cursorDown(cmd.count)
  of cmdCursorForward:  t.screen.cursorForward(cmd.count)
  of cmdCursorBackward: t.screen.cursorBackward(cmd.count)
  of cmdCursorNextLine:
    t.screen.cursorDown(cmd.count)
    t.screen.carriageReturn()
  of cmdCursorPrevLine:
    t.screen.cursorUp(cmd.count)
    t.screen.carriageReturn()
  of cmdCursorTo:       t.screen.cursorTo(cmd.row, cmd.col)
  of cmdCursorToColumn: t.screen.cursorTo(t.screen.cursor.row, cmd.absCol)
  of cmdCursorToRow:    t.screen.cursorTo(cmd.absRow, t.screen.cursor.col)
  of cmdEraseInLine:
    t.screen.eraseInLine(toScreenErase(cmd.eraseMode))
    t.damage.markRow(rowBefore)
  of cmdEraseInDisplay:
    t.screen.eraseInDisplay(toScreenErase(cmd.eraseMode))
    t.damage.markAll
  of cmdEraseChars:
    let saved = t.screen.cursor
    let row = saved.row
    let col = saved.col
    let k = min(cmd.count, t.screen.cols - col)
    for i in 0 ..< k:
      t.screen.cursorTo(row, col + i)
      t.screen.writeRune(uint32(' '), 1)
    t.screen.cursor = saved
    t.damage.markRow(row)
  of cmdInsertLines:
    t.screen.insertLines(cmd.count)
    t.damage.markAll
  of cmdDeleteLines:
    t.screen.deleteLines(cmd.count)
    t.damage.markAll
  of cmdInsertChars:
    t.screen.insertChars(cmd.count)
    t.damage.markRow(rowBefore)
  of cmdDeleteChars:
    t.screen.deleteChars(cmd.count)
    t.damage.markRow(rowBefore)
  of cmdScrollUp:
    t.screen.scrollUp(cmd.count)
    t.damage.markAll
  of cmdScrollDown:
    t.screen.scrollDown(cmd.count)
    t.damage.markAll
  of cmdSaveCursor:     t.screen.saveCursor()
  of cmdRestoreCursor:  t.screen.restoreCursor()
  of cmdSetSgr:         t.screen.applySgr(toSgrParams(cmd.sgrParams))
  of cmdSetScrollRegion:
    let bot = if cmd.regionBottom == DefaultScrollRegionBottom:
                t.screen.rows - 1
              else: cmd.regionBottom
    t.screen.setScrollRegion(cmd.regionTop, bot)
  of cmdSetMode:        t.applyMode(cmd.modeCode, cmd.privateMode, true)
  of cmdResetMode:      t.applyMode(cmd.modeCode, cmd.privateMode, false)
  of cmdSetTabStop:     t.screen.setTabStop()
  of cmdClearTabStop:   t.screen.clearTabStop()
  of cmdClearAllTabStops: t.screen.clearAllTabStops()
  of cmdSetTitle, cmdSetIconName, cmdHyperlink:
    discard  # no title/icon/hyperlink state yet; caller can subscribe later
  of cmdReset:
    t.screen.reset()
    t.damage.markAll
  of cmdIgnored, cmdUnknown: discard

# ---------------------------------------------------------------------------
# Feeding bytes
# ---------------------------------------------------------------------------

proc feedBytes*(t: Terminal, data: openArray[byte]) =
  ## Drive the full pipeline with a chunk of raw pty bytes. Safe to call
  ## repeatedly with arbitrary boundary cuts — parser and decoder both
  ## carry continuation state.
  let utfEmit: Utf8Emit = proc (rune: uint32, width: int) =
    t.apply(translatePrint(rune, width))

  let vtEmit: VtEmit = proc (ev: VtEvent) =
    case ev.kind
    of vePrint:
      t.decoder.advance(ev.byteVal, utfEmit)
    of veExecute:
      t.apply(translateExecute(ev.byteVal))
    of veEscDispatch:
      # DECKPAM / DECKPNM live outside the vt-commands translator —
      # intercept their raw ESC forms here before falling through.
      if ev.escIntermediates.len == 0:
        case char(ev.escFinal)
        of '=': t.keyboardMode.keypadApp = true;  return
        of '>': t.keyboardMode.keypadApp = false; return
        else: discard
      t.apply(translateEsc(ev.escIntermediates, ev.escFinal))
    of veCsiDispatch:
      if ev.ignored: return
      t.apply(translateCsi(
        toDispatchParams(ev.params), ev.intermediates, ev.final))
    of veOscDispatch:
      t.apply(translateOsc(ev.oscData))
    of veDcsHook, veDcsPut, veDcsUnhook:
      discard  # DCS passthrough not wired into the screen model

  t.parser.feed(data, vtEmit)

# ---------------------------------------------------------------------------
# Main loop primitives
# ---------------------------------------------------------------------------

proc step*(t: Terminal, bufSize: int = 4096): int =
  ## Perform one read→feed cycle. Returns the number of bytes applied.
  ## Returns 0 on EOF (child closed the slave) and -1 when a nonblocking
  ## backend would have blocked.
  if t.host.closed: return 0
  var buf = newSeq[byte](bufSize)
  let n = t.host.read(buf)
  if n <= 0: return n
  t.feedBytes(buf.toOpenArray(0, n - 1))
  n

proc drain*(t: Terminal, maxBytes: int = 1_000_000): int =
  ## Blocking-read loop until EOF or `maxBytes` consumed. Returns total
  ## bytes applied. Useful for tests that spawn a command expected to
  ## exit quickly.
  var total = 0
  while total < maxBytes:
    let n = t.step()
    if n == 0: break
    if n < 0: continue
    total += n
  total

proc write*(t: Terminal, data: openArray[byte]): int =
  ## Send bytes to the child (keyboard input, paste, etc).
  t.host.write(data)

proc writeString*(t: Terminal, s: string): int =
  t.host.writeString(s)

proc sendKey*(t: Terminal, ev: KeyEvent): int =
  ## Encode a keystroke through the keyboard widget (respecting the
  ## current DECCKM / DECKPAM mode bits) and send it to the child.
  let bytes = encode(ev, t.keyboardMode)
  if bytes.len == 0: return 0
  t.host.write(bytes)

proc sendPaste*(t: Terminal, text: string): int =
  ## Write a string to the child as if pasted — no per-character
  ## modifier handling.
  t.writeString(text)

proc resize*(t: Terminal, cols, rows: int) =
  ## Resize both the pty (so the child gets SIGWINCH) and the screen grid.
  t.host.resize(cols, rows)
  t.screen.resize(cols, rows)
  t.damage.resize(rows)

proc kill*(t: Terminal, signum: int = int(SIGTERM)) =
  t.host.kill(signum)

proc waitExit*(t: Terminal): int = t.host.waitExit()

proc close*(t: Terminal) = t.host.close()
