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

import std/[posix, options]
import ../cg/backend_pty_host_nim/src/pty_host_lib
import ../cg/universal_utf8_decoder_nim/src/utf8_decoder_lib
import ../cg/data_vt_parser_nim/src/vt_parser_lib
import ../cg/data_vt_commands_nim/src/vt_commands_lib
import ../cg/data_screen_buffer_nim/src/screen_buffer_lib
import ../cg/data_input_vt_encoding_nim/src/input_vt_encoding_lib
import ../cg/universal_damage_tracker_nim/src/damage_tracker_lib
import ../cg/universal_selection_region_nim/src/selection_region_lib
import ../cg/data_vt_reports_nim/src/vt_reports_lib
import ../cg/universal_fifo_buffer_nim/src/fifo_buffer_lib
import ../cg/universal_base64_nim/src/base64_codec
import ../cg/universal_color_parser_nim/src/color_parser_lib
import pty/posix_backend

export pty_host_lib, screen_buffer_lib, posix_backend, input_vt_encoding_lib,
       damage_tracker_lib, selection_region_lib, vt_commands_lib, vt_reports_lib,
       fifo_buffer_lib, base64_codec, color_parser_lib

type
  Terminal* = ref object
    ## A live child process attached to an in-memory screen grid.
    backend*: PosixBackend
    host*: PtyHost[PosixBackend]
    decoder: Utf8Decoder
    parser: VtParser
    screen*: Screen
    inputMode*: InputMode
    damage*: Damage
    selection*: Selection
    # Output queue
    responseQueue*: FifoBuffer
    # DCS accumulation
    dcsActive: bool
    dcsParams: seq[VtParam]
    dcsIntermediates: seq[byte]
    dcsFinal: byte
    dcsData: seq[byte]
    # Callbacks
    onBell*: proc()
    onTitleChanged*: proc(title: string)
    onIconNameChanged*: proc(name: string)
    onDcsPassthrough*: proc(cmd: VtCommand)
    onClipboardRequest*: proc(selector, text: string)

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
    inputMode: newInputMode(),
    damage: newDamage(rows),
    selection: newSelection(),
    responseQueue: newFifoBuffer(4096),
    dcsActive: false,
  )

# ---------------------------------------------------------------------------
# Cross-widget type shims
# ---------------------------------------------------------------------------

func csi(body: string): string = "\e[" & body

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

func toPaletteColor(c: color_parser_lib.RgbColor): screen_buffer_lib.PaletteColor =
  screen_buffer_lib.PaletteColor(r: c.r, g: c.g, b: c.b)

# ---------------------------------------------------------------------------
# Command application
# ---------------------------------------------------------------------------

proc applyMode(t: Terminal, code: int, private: bool, set: bool) =
  if private:
    case code
    of 1:
      # DECCKM — application cursor keys.
      t.inputMode.cursorApp = set
    of 7:
      if set: t.screen.modes.incl smAutoWrap
      else:   t.screen.modes.excl smAutoWrap
    of 9:
      # X10 Mouse tracking
      t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 47, 1047:
      t.screen.useAlternateScreen(set)
      t.damage.markAll
    of 66:
      # DECNKM (private-mode form of DECKPAM/DECKPNM).
      t.inputMode.keypadApp = set
    of 1000:
      # Basic mouse tracking (press/release)
      t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 1003:
      # Any-event mouse tracking (not fully implemented in encoder yet, but we track the mode)
      t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 1006:
      # SGR mouse tracking
      t.inputMode.mouseMode = if set: mmSgr else: mmNone
    of 1004:
      # Focus reporting mode
      t.inputMode.focusReporting = set
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
    of 2004:
      # Bracketed paste mode
      t.inputMode.bracketedPaste = set
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
  of cmdBell:
    if t.onBell != nil: t.onBell()
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
  of cmdRequestStatusReport:
    let code = cmd.requestArgs.paramOr(0, 0)
    if not cmd.requestPrivate:
      case code
      of 5: # Status report
        discard t.responseQueue.writeString(csi("0n"))
      of 6: # Cursor position report
        discard t.responseQueue.writeString(reportCursorPosition(t.screen.cursor.row, t.screen.cursor.col))
      else: discard
  of cmdRequestDeviceAttributes:
    if not cmd.requestPrivate:
      # Primary DA
      discard t.responseQueue.writeString(reportPrimaryDeviceAttributes({
        tfAnsiColor, tf256Color, tfTrueColor, tfMouse1000, tfMouse1006
      }))
    else:
      # Secondary DA (CSI > c)
      discard t.responseQueue.writeString(reportSecondaryDeviceAttributes(1)) # version 1
  of cmdRequestWindowReport:
    let code = cmd.requestArgs.paramOr(0, 0)
    case code
    of 18: discard t.responseQueue.writeString(reportWindowSize(t.screen.rows, t.screen.cols))
    of 19: discard t.responseQueue.writeString(reportScreenSize(t.screen.rows, t.screen.cols))
    of 21: discard t.responseQueue.writeString(reportWindowTitle(t.screen.title))
    else: discard
  of cmdSetTitle:
    t.screen.title = cmd.text
    if t.onTitleChanged != nil: t.onTitleChanged(cmd.text)
  of cmdSetIconName:
    t.screen.iconName = cmd.text
    if t.onIconNameChanged != nil: t.onIconNameChanged(cmd.text)
  of cmdHyperlink:      discard
  of cmdClipboardRequest:
    if t.onClipboardRequest != nil:
      try:
        let decoded = decode(cmd.base64Data)
        t.onClipboardRequest(cmd.clipboardSelector, decoded)
      except:
        discard # invalid base64
  of cmdSetPaletteColor:
    let color = parseColor(cmd.paletteColorSpec)
    if color.isSome:
      let idx = cmd.paletteIndex
      if idx >= 0 and idx <= 15:
        t.screen.theme.ansi[idx] = toPaletteColor(color.get)
        t.damage.markAll
      elif idx == 16: # Special case or just ignore for now if not supporting full 256 override
        discard
  of cmdSetThemeColor:
    let color = parseColor(cmd.themeColorSpec)
    if color.isSome:
      let c = toPaletteColor(color.get)
      case cmd.themeColorItem
      of 10: t.screen.theme.foreground = c
      of 11: t.screen.theme.background = c
      of 12: t.screen.theme.cursor = c
      else: discard
      t.damage.markAll
  of cmdDcsPassthrough:
    if t.onDcsPassthrough != nil: t.onDcsPassthrough(cmd)
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
        of '=': t.inputMode.keypadApp = true;  return
        of '>': t.inputMode.keypadApp = false; return
        else: discard
      t.apply(translateEsc(ev.escIntermediates, ev.escFinal))
    of veCsiDispatch:
      if ev.ignored: return
      t.apply(translateCsi(
        toDispatchParams(ev.params), ev.intermediates, ev.final))
    of veOscDispatch:
      t.apply(translateOsc(ev.oscData))
    of veDcsHook:
      t.dcsActive = true
      t.dcsParams = ev.params
      t.dcsIntermediates = ev.intermediates
      t.dcsFinal = ev.final
      t.dcsData = @[]
    of veDcsPut:
      if t.dcsActive:
        t.dcsData.add ev.byteVal
    of veDcsUnhook:
      if t.dcsActive:
        t.apply(translateDcs(
          toDispatchParams(t.dcsParams), t.dcsIntermediates, t.dcsFinal, t.dcsData))
        t.dcsActive = false
        t.dcsData = @[]

  t.parser.feed(data, vtEmit)

# ---------------------------------------------------------------------------
# Main loop primitives
# ---------------------------------------------------------------------------

proc flush*(t: Terminal): int =
  ## Write any pending terminal reports to the child. Returns the
  ## number of bytes written.
  if t.responseQueue.isEmpty: return 0
  var buf = newSeq[byte](t.responseQueue.len)
  let n = t.responseQueue.read(buf)
  if n <= 0: return 0
  t.host.write(buf.toOpenArray(0, n - 1))

proc step*(t: Terminal, bufSize: int = 4096): int =
  ## Perform one read→feed cycle. Returns the number of bytes applied.
  ## Returns 0 on EOF (child closed the slave) and -1 when a nonblocking
  ## backend would have blocked.
  if t.host.closed: return 0
  var buf = newSeq[byte](bufSize)
  let n = t.host.read(buf)
  if n > 0:
    t.feedBytes(buf.toOpenArray(0, n - 1))
  
  # Always attempt to flush outgoing reports after processing input.
  discard t.flush()
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
  
  # Final flush after drain.
  discard t.flush()
  total

proc write*(t: Terminal, data: openArray[byte]): int =
  ## Send bytes to the child (keyboard input, paste, etc).
  t.host.write(data)

proc writeString*(t: Terminal, s: string): int =
  t.host.writeString(s)

proc sendKey*(t: Terminal, ev: KeyEvent): int =
  ## Encode a keystroke through the input encoder (respecting the
  ## current DECCKM / DECKPAM mode bits) and send it to the child.
  let bytes = encodeKeyEvent(ev, t.inputMode)
  if bytes.len == 0: return 0
  t.host.write(bytes)

proc sendMouse*(t: Terminal, ev: MouseEvent): int =
  ## Encode a mouse event through the active mouse protocol (X11, SGR)
  ## and send it to the child.
  let bytes = encodeMouseEvent(ev, t.inputMode)
  if bytes.len == 0: return 0
  t.host.write(bytes)

proc sendPaste*(t: Terminal, text: string): int =
  ## Write a string to the child, wrapping in bracketed-paste sequences
  ## if enabled.
  let bytes = encodePaste(text, t.inputMode)
  if bytes.len == 0: return 0
  t.host.write(bytes)

proc sendFocus*(t: Terminal, gained: bool): int =
  ## Send a Focus In/Out report if enabled.
  if not t.inputMode.focusReporting: return 0
  discard t.host.writeString(reportFocus(gained))

proc sendClipboardResponse*(t: Terminal, selector, text: string): int =
  ## Send a clipboard response (OSC 52) back to the child.
  let encoded = encode(text)
  discard t.host.writeString(reportClipboard(selector, encoded))

proc resize*(t: Terminal, cols, rows: int) =
  ## Resize both the pty (so the child gets SIGWINCH) and the screen grid.
  t.host.resize(cols, rows)
  t.screen.resize(cols, rows)
  t.damage.resize(rows)

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func appendRuneUtf8(buf: var string, rune: uint32) =
  if rune < 0x80'u32:
    buf.add char(rune)
  elif rune < 0x800'u32:
    buf.add char(0xC0'u32 or (rune shr 6))
    buf.add char(0x80'u32 or (rune and 0x3F'u32))
  elif rune < 0x10000'u32:
    buf.add char(0xE0'u32 or (rune shr 12))
    buf.add char(0x80'u32 or ((rune shr 6) and 0x3F'u32))
    buf.add char(0x80'u32 or (rune and 0x3F'u32))
  else:
    buf.add char(0xF0'u32 or (rune shr 18))
    buf.add char(0x80'u32 or ((rune shr 12) and 0x3F'u32))
    buf.add char(0x80'u32 or ((rune shr 6) and 0x3F'u32))
    buf.add char(0x80'u32 or (rune and 0x3F'u32))

proc selectionText*(t: Terminal): string =
  ## Walk the current selection's spans against the screen grid and
  ## return the covered text. Row boundaries inject '\n'. Continuation
  ## cells (right half of a wide char) are skipped so we emit one rune
  ## per glyph, not one per cell.
  if not t.selection.isActive or t.selection.isEmpty: return
  let spans = t.selection.spans(t.screen.cols)
  var lastRow = -1
  for sp in spans:
    if lastRow >= 0: result.add '\n'
    for col in sp.startCol ..< sp.endCol:
      let cell = t.screen.cellAt(sp.row, col)
      if cell.width == 0: continue   # right half of double-wide
      appendRuneUtf8(result, cell.rune)
    lastRow = sp.row

proc kill*(t: Terminal, signum: int = int(SIGTERM)) =
  t.host.kill(signum)

proc waitExit*(t: Terminal): int = t.host.waitExit()

proc close*(t: Terminal) = t.host.close()
