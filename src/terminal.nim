## Project glue: assemble PTY host, UTF-8 decoder, VT parser, VT command
## translator, and screen buffer into a single `Terminal` pipeline.

import std/[options]
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
import ../cg/universal_viewport_nim/src/viewport_lib
import ../cg/backend_pty_async_nim/src/pty_async_lib
import ../cg/universal_drag_controller_nim/src/drag_controller_lib
import ../cg/universal_shortcut_map_nim/src/shortcut_map_lib

# OS-Specific Backend Selection
when defined(posix):
  import pty/posix_backend
  type CurrentBackend* = PosixBackend
  import std/posix
elif defined(windows):
  import pty/windows_backend
  type CurrentBackend* = WindowsBackend
else:
  type CurrentBackend* = object

export pty_host_lib, screen_buffer_lib, input_vt_encoding_lib,
       damage_tracker_lib, selection_region_lib, vt_commands_lib, vt_reports_lib,
       fifo_buffer_lib, base64_codec, color_parser_lib, viewport_lib, pty_async_lib,
       drag_controller_lib, shortcut_map_lib, utf8_decoder_lib, vt_parser_lib

type
  Terminal* = ref object
    ## A live child process attached to an in-memory screen grid.
    backend*: CurrentBackend
    host*: PtyHost[CurrentBackend]
    async*: AsyncPty[CurrentBackend]
    decoder*: Utf8Decoder
    parser*: VtParser
    screen*: Screen
    inputMode*: InputMode
    damage*: Damage
    selection*: Selection
    viewport*: Viewport
    drag*: DragController
    shortcuts*: ShortcutMap
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
    scrollback: int = DefaultScrollback
): Terminal =
  when defined(posix):
    let backend = newPosixBackend()
  elif defined(windows):
    let backend = newWindowsBackend()
  else:
    let backend = CurrentBackend()

  let host = spawn(backend, program, args, cwd, rows, cols)
  let sMap = newShortcutMap()
  sMap.addStandardTerminalShortcuts()
  
  Terminal(
    backend: backend,
    host: host,
    async: newAsyncPty(backend, host.handle),
    decoder: newUtf8Decoder(),
    parser: newVtParser(),
    screen: newScreen(cols, rows, scrollback),
    inputMode: newInputMode(),
    damage: newDamage(rows),
    selection: newSelection(),
    viewport: newViewport(rows),
    drag: newDragController(rows),
    shortcuts: sMap,
    dcsActive: false,
  )

# ---------------------------------------------------------------------------
# Cross-widget type shims
# ---------------------------------------------------------------------------

func toDispatchParams(src: seq[VtParam]): seq[DispatchParam] =
  result = newSeqOfCap[DispatchParam](src.len)
  for p in src: result.add DispatchParam(value: p.value, subParams: p.subParams)

func toSgrParams(src: seq[DispatchParam]): seq[SgrParam] =
  result = newSeqOfCap[SgrParam](src.len)
  for p in src: result.add SgrParam(value: p.value, subParams: p.subParams)

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
    of 1:    t.inputMode.cursorApp = set
    of 7:    (if set: t.screen.modes.incl smAutoWrap else: t.screen.modes.excl smAutoWrap)
    of 9:    t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 47, 1047: (t.screen.useAlternateScreen(set); t.damage.markAll())
    of 66:   t.inputMode.keypadApp = set
    of 1000: t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 1003: t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 1006: t.inputMode.mouseMode = if set: mmSgr else: mmNone
    of 1004: t.inputMode.focusReporting = set
    of 1048: (if set: t.screen.saveCursor() else: t.screen.restoreCursor())
    of 1049:
      if set: (t.screen.saveCursor(); t.screen.useAlternateScreen(true))
      else: (t.screen.useAlternateScreen(false); t.screen.restoreCursor())
      t.damage.markAll()
    of 2004: t.inputMode.bracketedPaste = set
    else: discard
  else:
    case code
    of 4: (if set: t.screen.modes.incl smInsert else: t.screen.modes.excl smInsert)
    else: discard

proc apply*(t: Terminal, cmd: VtCommand) =
  let rowBefore = t.screen.cursor.row
  case cmd.kind
  of cmdPrint:
    if t.screen.cursor.pendingWrap or t.screen.cursor.col + cmd.width > t.screen.cols:
      if t.screen.cursor.row == t.screen.scrollBottom: t.damage.markAll()
    t.screen.writeRune(cmd.rune, cmd.width)
    t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row)
  of cmdExecute:
    case char(cmd.rawByte)
    of '\L':
      if t.screen.cursor.row == t.screen.scrollBottom: t.damage.markAll()
      t.screen.lineFeed()
      t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row)
    of '\r': t.screen.carriageReturn()
    of '\b': t.screen.backspace()
    of '\t': t.screen.tab()
    of '\a': (if t.onBell != nil: t.onBell())
    else: discard
  of cmdLineFeed:
    if t.screen.cursor.row == t.screen.scrollBottom: t.damage.markAll()
    t.screen.lineFeed()
    t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row)
  of cmdReverseIndex:
    if t.screen.cursor.row == t.screen.scrollTop: t.damage.markAll()
    t.screen.reverseIndex()
    t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row)
  of cmdCarriageReturn: t.screen.carriageReturn()
  of cmdBackspace:      t.screen.backspace()
  of cmdHorizontalTab:  t.screen.tab()
  of cmdBell: (if t.onBell != nil: t.onBell())
  of cmdCursorUp:       t.screen.cursorUp(cmd.count); t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row)
  of cmdCursorDown:     t.screen.cursorDown(cmd.count); t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row)
  of cmdCursorForward:  t.screen.cursorForward(cmd.count); t.damage.markRow(t.screen.cursor.row)
  of cmdCursorBackward: t.screen.cursorBackward(cmd.count); t.damage.markRow(t.screen.cursor.row)
  of cmdCursorNextLine: (t.screen.cursorDown(cmd.count); t.screen.carriageReturn(); t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row))
  of cmdCursorPrevLine: (t.screen.cursorUp(cmd.count); t.screen.carriageReturn(); t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row))
  of cmdCursorTo:       (t.screen.cursorTo(cmd.row, cmd.col); t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row))
  of cmdCursorToColumn: (t.screen.cursorTo(t.screen.cursor.row, cmd.absCol); t.damage.markRow(t.screen.cursor.row))
  of cmdCursorToRow:    (t.screen.cursorTo(cmd.absRow, t.screen.cursor.col); t.damage.markRow(rowBefore); t.damage.markRow(t.screen.cursor.row))
  of cmdEraseInLine:    (t.screen.eraseInLine(toScreenErase(cmd.eraseMode)); t.damage.markRow(rowBefore))
  of cmdEraseInDisplay: (t.screen.eraseInDisplay(toScreenErase(cmd.eraseMode)); t.damage.markAll())
  of cmdEraseChars:
    let saved = t.screen.cursor; let k = min(cmd.count, t.screen.cols - saved.col)
    for i in 0 ..< k: (t.screen.cursorTo(saved.row, saved.col + i); t.screen.writeRune(uint32(' '), 1))
    t.screen.cursor = saved; t.damage.markRow(saved.row)
  of cmdInsertLines: (t.screen.insertLines(cmd.count); t.damage.markAll())
  of cmdDeleteLines: (t.screen.deleteLines(cmd.count); t.damage.markAll())
  of cmdInsertChars: (t.screen.insertChars(cmd.count); t.damage.markRow(rowBefore))
  of cmdDeleteChars: (t.screen.deleteChars(cmd.count); t.damage.markRow(rowBefore))
  of cmdScrollUp:    (t.screen.scrollUp(cmd.count); t.damage.markAll())
  of cmdScrollDown:  (t.screen.scrollDown(cmd.count); t.damage.markAll())
  of cmdSaveCursor:     t.screen.saveCursor()
  of cmdRestoreCursor:  t.screen.restoreCursor()
  of cmdSetSgr:         t.screen.applySgr(toSgrParams(cmd.sgrParams))
  of cmdSetScrollRegion: (let bot = if cmd.regionBottom == DefaultScrollRegionBottom: t.screen.rows - 1 else: cmd.regionBottom; t.screen.setScrollRegion(cmd.regionTop, bot))
  of cmdSetMode:        t.applyMode(cmd.modeCode, cmd.privateMode, true)
  of cmdResetMode:      t.applyMode(cmd.modeCode, cmd.privateMode, false)
  of cmdSetTabStop:     t.screen.setTabStop()
  of cmdClearTabStop:   t.screen.clearTabStop()
  of cmdClearAllTabStops: t.screen.clearAllTabStops()
  of cmdRequestStatusReport:
    let code = cmd.requestArgs.paramOr(0, 0)
    if not cmd.requestPrivate:
      case code
      of 5: discard t.async.send(cast[seq[byte]]("\e[0n"))
      of 6: discard t.async.send(cast[seq[byte]](reportCursorPosition(t.screen.cursor.row, t.screen.cursor.col)))
      else: discard
  of cmdRequestDeviceAttributes:
    if not cmd.requestPrivate: discard t.async.send(cast[seq[byte]](reportPrimaryDeviceAttributes({tfAnsiColor, tf256Color, tfTrueColor, tfMouse1000, tfMouse1006})))
    else: discard t.async.send(cast[seq[byte]](reportSecondaryDeviceAttributes(1)))
  of cmdRequestWindowReport:
    let code = cmd.requestArgs.paramOr(0, 0)
    case code
    of 18: discard t.async.send(cast[seq[byte]](reportWindowSize(t.screen.rows, t.screen.cols)))
    of 19: discard t.async.send(cast[seq[byte]](reportScreenSize(t.screen.rows, t.screen.cols)))
    of 21: discard t.async.send(cast[seq[byte]](reportWindowTitle(t.screen.title)))
    else: discard
  of cmdSetTitle: (t.screen.title = cmd.text; if t.onTitleChanged != nil: t.onTitleChanged(cmd.text))
  of cmdSetIconName: (t.screen.iconName = cmd.text; if t.onIconNameChanged != nil: t.onIconNameChanged(cmd.text))
  of cmdHyperlink: discard
  of cmdClipboardRequest: (if t.onClipboardRequest != nil: (try: (let decoded = decode(cmd.base64Data); t.onClipboardRequest(cmd.clipboardSelector, decoded)) except: discard))
  of cmdSetPaletteColor:
    let color = parseColor(cmd.paletteColorSpec)
    if color.isSome: (let idx = cmd.paletteIndex; if idx >= 0 and idx <= 15: (t.screen.theme.ansi[idx] = toPaletteColor(color.get); t.damage.markAll()))
  of cmdSetThemeColor:
    let color = parseColor(cmd.themeColorSpec)
    if color.isSome:
      let c = toPaletteColor(color.get)
      case cmd.themeColorItem
      of 10: t.screen.theme.foreground = c
      of 11: t.screen.theme.background = c
      of 12: t.screen.theme.cursor = c
      else: discard
      t.damage.markAll()
  of cmdDcsPassthrough: (if t.onDcsPassthrough != nil: t.onDcsPassthrough(cmd))
  of cmdReset: (t.screen.reset(); t.damage.markAll())
  of cmdIgnored, cmdUnknown: discard

proc feedBytes*(t: Terminal, data: openArray[byte]) =
  proc vtEmit(ev: VtEvent) =
    case ev.kind
    of vePrint: (t.decoder.feed([ev.byteVal]) do (rune: uint32, width: int): t.apply(VtCommand(kind: cmdPrint, rune: rune, width: width)))
    of veExecute: t.apply(VtCommand(kind: cmdExecute, rawByte: ev.byteVal))
    of veEscDispatch:
      if ev.escIntermediates.len == 0:
        case char(ev.escFinal)
        of '=': (t.inputMode.keypadApp = true; return)
        of '>': (t.inputMode.keypadApp = false; return)
        else: discard
      t.apply(translateEsc(ev.escIntermediates, ev.escFinal))
    of veCsiDispatch: (if not ev.ignored: t.apply(translateCsi(toDispatchParams(ev.params), ev.intermediates, ev.final)))
    of veOscDispatch: t.apply(translateOsc(ev.oscData))
    of veDcsHook: (t.dcsActive = true; t.dcsParams = ev.params; t.dcsIntermediates = ev.intermediates; t.dcsFinal = ev.final; t.dcsData = @[])
    of veDcsPut: (if t.dcsActive: t.dcsData.add ev.byteVal)
    of veDcsUnhook: (if t.dcsActive: (t.apply(translateDcs(toDispatchParams(t.dcsParams), t.dcsIntermediates, t.dcsFinal, t.dcsData)); t.dcsActive = false; t.dcsData = @[]))
  t.parser.feed(data, vtEmit)

proc selectionText*(t: Terminal): string =
  ## Convenience: Get the currently selected text.
  t.selection.extractText(t.screen.cols) do (r: int) -> seq[CellData]:
    let row = t.screen.absoluteRowAt(r)
    var res = newSeq[CellData](row.len)
    for i, c in row: res[i] = CellData(rune: c.rune, width: int(c.width))
    res

proc flush*(t: Terminal): int = t.async.flush()
proc step*(t: Terminal, bufSize: int = 4096): int =
  if t.host.closed: return 0
  var buf = newSeq[byte](bufSize); let n = t.async.read(buf)
  if n > 0: t.feedBytes(buf.toOpenArray(0, n - 1))
  discard t.async.flush(); n

proc drain*(t: Terminal, maxBytes: int = 1_000_000): int =
  var total = 0
  while total < maxBytes: (let n = t.step(); if n == 0: break; if n < 0: continue; total += n)
  discard t.flush(); total

proc sendKey*(t: Terminal, ev: KeyEvent): int = (let bytes = encodeKeyEvent(ev, t.inputMode); if bytes.len == 0: 0 else: t.async.send(bytes))
proc sendMouse*(t: Terminal, ev: MouseEvent): int = (let bytes = encodeMouseEvent(ev, t.inputMode); if bytes.len == 0: 0 else: t.async.send(bytes))
proc sendPaste*(t: Terminal, text: string): int = (let bytes = encodePaste(text, t.inputMode); if bytes.len == 0: 0 else: t.async.send(bytes))
proc sendFocus*(t: Terminal, gained: bool): int = (if not t.inputMode.focusReporting: 0 else: t.async.send(cast[seq[byte]](reportFocus(gained))))
proc sendClipboardResponse*(t: Terminal, selector, text: string): int = (let encoded = encode(text); t.async.send(cast[seq[byte]](reportClipboard(selector, encoded))))
proc refreshViewport*(t: Terminal, stickToBottom: bool = true) = t.viewport.updateBufferHeight(t.screen.totalRows, stickToBottom)
proc resize*(t: Terminal, cols, rows: int) = (t.host.resize(cols, rows); t.screen.resize(cols, rows); t.damage.resize(rows); t.viewport.height = rows; t.refreshViewport())

proc termSignal*(): int =
  when defined(posix): int(SIGTERM)
  else: 15

proc kill*(t: Terminal, signum: int = -1) = 
  let s = if signum == -1: termSignal() else: signum
  t.host.kill(s)

proc waitExit*(t: Terminal): int = t.host.waitExit()
proc close*(t: Terminal) = t.host.close()
