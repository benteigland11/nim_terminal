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
import ../cg/data_semantic_history_nim/src/semantic_history_lib
import ../cg/universal_link_detector_nim/src/link_detector_lib
import ../cg/data_terminal_output_footprint_nim/src/terminal_output_footprint_lib
import ../cg/data_terminal_sync_update_nim/src/terminal_sync_update_lib
import ../cg/data_vt_diagnostics_nim/src/vt_diagnostics_lib as vt_diag

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
       drag_controller_lib, shortcut_map_lib, utf8_decoder_lib, vt_parser_lib,
       semantic_history_lib, link_detector_lib, terminal_output_footprint_lib,
       terminal_sync_update_lib
export vt_diag

type
  ActiveLink* = object
    link*: DetectedLink
    row*: int
    startCol*: int
    endCol*: int

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
    history*: SemanticHistory
    diagnostics*: vt_diag.VtDiagnostics
    activeLink*: Option[ActiveLink]
    outputFootprint*: OutputFootprint
    syncUpdate*: SyncUpdateState
    reports*: seq[string]
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
    diagnosticsCapacity: int = 128
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
    history: newSemanticHistory(),
    diagnostics: vt_diag.newVtDiagnostics(diagnosticsCapacity),
    activeLink: none(ActiveLink),
    outputFootprint: newOutputFootprint(),
    syncUpdate: newSyncUpdateState(),
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
  of vt_commands_lib.emScrollback: screen_buffer_lib.emScrollback

func toPaletteColor(c: color_parser_lib.RgbColor): screen_buffer_lib.PaletteColor =
  screen_buffer_lib.PaletteColor(r: c.r, g: c.g, b: c.b)

func absoluteCursorRow(t: Terminal): int =
  t.screen.absoluteCursorRow()

proc trackOutputFootprint(t: Terminal, row: int) =
  t.outputFootprint.recordRow(row, activeAlternate = t.screen.usingAlt)

proc trackOutputFootprint(t: Terminal, firstRow, lastRow: int) =
  t.outputFootprint.recordRows(firstRow, lastRow, activeAlternate = t.screen.usingAlt)

proc finishOutputFootprint(t: Terminal, force = false) =
  let action = t.outputFootprint.consumeResume(
    cursorRow = t.screen.cursor.row,
    screenRows = t.screen.rows,
    activeAlternate = t.screen.usingAlt,
    force = force,
  )
  if not action.shouldMove: return
  t.screen.carriageReturn()
  if action.scrollCount > 0:
    t.screen.scrollUp(action.scrollCount)
  t.screen.cursorTo(action.targetRow, 0)
  t.damage.markAll()

proc armOutputFootprintIfRestored(t: Terminal) =
  t.outputFootprint.armAfterCursorRestore(
    cursorRow = t.screen.cursor.row,
    activeAlternate = t.screen.usingAlt,
  )

proc applyScreenTransition(t: Terminal, transition: ScreenContextTransition) =
  if not transition.changed: return
  if transition.clearTransientUi:
    t.selection.clear()
    t.activeLink = none(ActiveLink)
  if transition.resetOutputFootprint:
    t.outputFootprint.reset()
  if transition.resetViewport:
    t.viewport.updateBufferHeight(t.screen.totalRows, true)
  t.damage.markAll()

# ---------------------------------------------------------------------------
# Command application
# ---------------------------------------------------------------------------

proc applyMode(t: Terminal, code: int, private: bool, set: bool) =
  if private:
    if t.screen.applyPrivateMode(code, set): return
    case code
    of 1:    t.inputMode.cursorApp = set
    of 9:    t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 47, 1047:
      let transition = t.screen.switchAlternateScreen(set)
      if set:
        t.screen.cursorTo(0, 0)
        t.screen.eraseInDisplay(screen_buffer_lib.emAll)
      t.applyScreenTransition(transition)
    of 66:   t.inputMode.keypadApp = set
    of 1000: t.inputMode.mouseMode = if set: mmX11 else: mmNone
    of 1002: t.inputMode.mouseMode = if set: mmButtonEvent else: mmNone
    of 1003: t.inputMode.mouseMode = if set: mmAnyEvent else: mmNone
    of 1006: t.inputMode.sgrMouse = set
    of 1007: t.inputMode.alternateScroll = set
    of 1004: t.inputMode.focusReporting = set
    of 1048:
      if set:
        t.screen.saveCursor()
      else:
        t.screen.restoreCursor()
        t.armOutputFootprintIfRestored()
    of 1049:
      if set:
        t.screen.saveCursor()
        let transition = t.screen.switchAlternateScreen(true)
        t.screen.cursorTo(0, 0)
        t.screen.eraseInDisplay(screen_buffer_lib.emAll)
        t.applyScreenTransition(transition)
      else:
        let transition = t.screen.switchAlternateScreen(false)
        t.screen.restoreCursor()
        t.applyScreenTransition(transition)
    of 2004: t.inputMode.bracketedPaste = set
    of 2026:
      let transition = t.syncUpdate.setActive(set)
      if transition.exited and transition.shouldPresent:
        t.damage.markAll()
    else: discard
  else:
    case code
    of 4: (if set: t.screen.modes.incl smInsert else: t.screen.modes.excl smInsert)
    else: discard

func modeStatus(t: Terminal, code: int, private: bool): ModeStatus =
  if private:
    let modes = [
      modeSupport(7, if smAutoWrap in t.screen.modes: msSet else: msReset),
      modeSupport(25, if t.screen.cursor.visible: msSet else: msReset),
      modeSupport(47, if t.screen.usingAlt: msSet else: msReset),
      modeSupport(1047, if t.screen.usingAlt: msSet else: msReset),
      modeSupport(1049, if t.screen.usingAlt: msSet else: msReset),
      modeSupport(1000, if t.inputMode.mouseMode == mmX11: msSet else: msReset),
      modeSupport(1002, if t.inputMode.mouseMode == mmButtonEvent: msSet else: msReset),
      modeSupport(1003, if t.inputMode.mouseMode == mmAnyEvent: msSet else: msReset),
      modeSupport(1004, if t.inputMode.focusReporting: msSet else: msReset),
      modeSupport(1006, if t.inputMode.sgrMouse or t.inputMode.mouseMode == mmSgr: msSet else: msReset),
      modeSupport(1007, if t.inputMode.alternateScroll: msSet else: msReset),
      modeSupport(2004, if t.inputMode.bracketedPaste: msSet else: msReset),
      modeSupport(2026, if t.syncUpdate.active: msSet else: msReset),
    ]
    modeStatusFrom(modes, code, privateMode = true)
  else:
    let modes = [modeSupport(4, if smInsert in t.screen.modes: msSet else: msReset, privateMode = false)]
    modeStatusFrom(modes, code, privateMode = false)

proc sendReport(t: Terminal, report: string): int =
  if report.len == 0: return 0
  t.reports.add report
  t.async.send(report.toOpenArrayByte(0, report.high))

proc recordDiagnostic(t: Terminal, kind: vt_diag.VtEventKind, name, detail: string) =
  if t.diagnostics != nil:
    t.diagnostics.record(kind, name, detail)

func stateStringReport(t: Terminal, request: string): string =
  case request
  of "m":
    reportStateString(t.screen.sgrReport())
  of " q":
    reportStateString($t.screen.cursorStyleReportCode() & " q")
  of "r":
    reportStateString(t.screen.scrollRegionReport())
  else:
    reportStateString("", valid = false)

proc apply*(t: Terminal, cmd: VtCommand) =
  let rowBefore = t.screen.cursor.row
  case cmd.kind
  of cmdPrint:
    if t.outputFootprint.isArmed:
      t.finishOutputFootprint()
    if t.screen.cursor.pendingWrap or t.screen.cursor.col + cmd.width > t.screen.cols:
      if t.screen.cursor.row == t.screen.scrollBottom: t.damage.markAll()
    t.screen.writeRune(cmd.rune, cmd.width)
    t.trackOutputFootprint(rowBefore, t.screen.cursor.row)
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
  of cmdCursorForwardTab: t.screen.tab(cmd.count)
  of cmdCursorBackwardTab: t.screen.backTab(cmd.count)
  of cmdShiftOut:       t.screen.shiftOut()
  of cmdShiftIn:        t.screen.shiftIn()
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
  of cmdEraseInLine:    (t.screen.eraseInLine(toScreenErase(cmd.eraseMode)); t.trackOutputFootprint(rowBefore); t.damage.markRow(rowBefore))
  of cmdEraseInDisplay:
    t.screen.eraseInDisplay(toScreenErase(cmd.eraseMode))
    if cmd.eraseMode == vt_commands_lib.emAll:
      t.outputFootprint.markFullDisplayErase(activeAlternate = t.screen.usingAlt)
    t.damage.markAll()
  of cmdEraseChars:
    t.screen.eraseChars(cmd.count)
    t.damage.markRow(rowBefore)
    t.trackOutputFootprint(rowBefore)
  of cmdInsertLines: (t.screen.insertLines(cmd.count); t.trackOutputFootprint(rowBefore, t.screen.scrollBottom); t.damage.markAll())
  of cmdDeleteLines: (t.screen.deleteLines(cmd.count); t.trackOutputFootprint(rowBefore, t.screen.scrollBottom); t.damage.markAll())
  of cmdInsertChars: (t.screen.insertChars(cmd.count); t.trackOutputFootprint(rowBefore); t.damage.markRow(rowBefore))
  of cmdDeleteChars: (t.screen.deleteChars(cmd.count); t.trackOutputFootprint(rowBefore); t.damage.markRow(rowBefore))
  of cmdRepeatPreviousChar: (t.screen.repeatPreviousChar(cmd.count); t.trackOutputFootprint(rowBefore); t.damage.markRow(rowBefore))
  of cmdScrollUp:    (t.screen.scrollUp(cmd.count); t.trackOutputFootprint(t.screen.scrollTop, t.screen.scrollBottom); t.damage.markAll())
  of cmdScrollDown:  (t.screen.scrollDown(cmd.count); t.trackOutputFootprint(t.screen.scrollTop, t.screen.scrollBottom); t.damage.markAll())
  of cmdSaveCursor:     t.screen.saveCursor()
  of cmdRestoreCursor:  t.screen.restoreCursor(); t.armOutputFootprintIfRestored()
  of cmdSetSgr:         t.screen.applySgr(toSgrParams(cmd.sgrParams))
  of cmdSetCursorStyle: t.screen.setCursorStyle(cmd.cursorStyleCode); t.damage.markRow(t.screen.cursor.row)
  of cmdSetScrollRegion: (let bot = if cmd.regionBottom == DefaultScrollRegionBottom: t.screen.rows - 1 else: cmd.regionBottom; t.screen.setScrollRegion(cmd.regionTop, bot))
  of cmdSetMode:
    t.recordDiagnostic(vt_diag.vekModeSet, "mode", $cmd.modeCodes)
    if cmd.modeCodes.len == 0:
      t.applyMode(cmd.modeCode, cmd.privateMode, true)
    else:
      for code in cmd.modeCodes:
        t.applyMode(code, cmd.privateMode, true)
  of cmdResetMode:
    t.recordDiagnostic(vt_diag.vekModeReset, "mode", $cmd.modeCodes)
    if cmd.modeCodes.len == 0:
      t.applyMode(cmd.modeCode, cmd.privateMode, false)
    else:
      for code in cmd.modeCodes:
        t.applyMode(code, cmd.privateMode, false)
  of cmdRequestMode:
    t.recordDiagnostic(vt_diag.vekModeQuery, "DECRQM", $cmd.modeCode)
    discard t.sendReport(reportModeStatus(cmd.modeCode, t.modeStatus(cmd.modeCode, cmd.privateMode), cmd.privateMode))
  of cmdSetTabStop:     t.screen.setTabStop()
  of cmdClearTabStop:   t.screen.clearTabStop()
  of cmdClearAllTabStops: t.screen.clearAllTabStops()
  of cmdRequestStatusReport:
    let code = cmd.requestArgs.paramOr(0, 0)
    if not cmd.requestPrivate:
      case code
      of 5:
        discard t.sendReport(reportTerminalOk())
        t.recordDiagnostic(vt_diag.vekReportSent, "DSR", "status")
      of 6:
        discard t.sendReport(reportCursorPosition(t.screen.cursor.row, t.screen.cursor.col))
        t.recordDiagnostic(vt_diag.vekReportSent, "DSR", "cursor")
      else: discard
  of cmdRequestDeviceAttributes:
    if not cmd.requestPrivate:
      discard t.sendReport(reportPrimaryDeviceAttributes({tfAnsiColor, tf256Color, tfTrueColor, tfMouse1000, tfMouse1006}))
      t.recordDiagnostic(vt_diag.vekReportSent, "DA", "primary")
    else:
      discard t.sendReport(reportSecondaryDeviceAttributes(1))
      t.recordDiagnostic(vt_diag.vekReportSent, "DA", "secondary")
  of cmdRequestWindowReport:
    let code = cmd.requestArgs.paramOr(0, 0)
    case code
    of 18:
      discard t.sendReport(reportWindowSize(t.screen.rows, t.screen.cols))
      t.recordDiagnostic(vt_diag.vekReportSent, "window", "text-area-size")
    of 19:
      discard t.sendReport(reportScreenSize(t.screen.rows, t.screen.cols))
      t.recordDiagnostic(vt_diag.vekReportSent, "window", "screen-size")
    of 21:
      discard t.sendReport(reportWindowTitle(t.screen.title))
      t.recordDiagnostic(vt_diag.vekReportSent, "window", "title")
    else: discard
  of cmdSetTitle: (t.screen.title = cmd.text; if t.onTitleChanged != nil: t.onTitleChanged(cmd.text))
  of cmdSetIconName: (t.screen.iconName = cmd.text; if t.onIconNameChanged != nil: t.onIconNameChanged(cmd.text))
  of cmdHyperlink: discard
  of cmdClipboardRequest:
    if t.onClipboardRequest != nil:
      let decoded = tryDecode(cmd.base64Data)
      if decoded.isSome:
        t.onClipboardRequest(cmd.clipboardSelector, decoded.get())
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
  of cmdScreenAlignmentTest:
    t.screen.screenAlignmentTest()
    t.damage.markAll()
  of cmdSelectCharset:
    let slot = if cmd.charsetSlot == ')': 1 else: 0
    case cmd.charsetFinal
    of byte('0'): t.screen.selectCharset(slot, scsDecSpecialGraphics)
    else: t.screen.selectCharset(slot, scsAscii)
  of cmdShellPromptStart:
    t.finishOutputFootprint(force = t.history.phase == sphOutput)
    t.history.markPromptStart(t.absoluteCursorRow())
  of cmdShellCommandStart:
    t.history.markCommandStart(t.absoluteCursorRow())
  of cmdShellCommandExecuted:
    t.outputFootprint.reset()
    t.history.markCommandExecuted(t.absoluteCursorRow())
  of cmdShellCommandFinished:
    t.finishOutputFootprint(force = t.history.phase == sphOutput)
    t.history.markCommandFinished(t.absoluteCursorRow(), cmd.exitCode)
  of cmdRequestStateString:
    t.recordDiagnostic(vt_diag.vekStateQuery, "DECRQSS", cmd.stateString)
    discard t.sendReport(t.stateStringReport(cmd.stateString))
  of cmdDcsPassthrough:
    t.recordDiagnostic(vt_diag.vekUnknownDcs, "DCS", $char(cmd.dcsFinal))
    if t.onDcsPassthrough != nil: t.onDcsPassthrough(cmd)
  of cmdReset: (t.screen.reset(); t.damage.markAll())
  of cmdIgnored: discard
  of cmdUnknown:
    t.recordDiagnostic(vt_diag.vekUnknownCsi, "unknown", $char(cmd.rawFinal))

proc feedBytes*(t: Terminal, data: openArray[byte]) =
  if data.len > 0:
    t.syncUpdate.markDirty()
  proc vtEmit(ev: VtEvent) =
    case ev.kind
    of vePrint: (t.decoder.feed([ev.byteVal]) do (rune: uint32, width: int): t.apply(VtCommand(kind: cmdPrint, rune: rune, width: width)))
    of veExecute: t.apply(translateExecute(ev.byteVal))
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
  var buf = newSeq[byte](bufSize)
  let read = t.async.readResult(buf)
  case read.kind
  of arData:
    if read.count > 0: t.feedBytes(buf.toOpenArray(0, read.count - 1))
    discard t.async.flush()
    read.count
  of arWouldBlock:
    discard t.async.flush()
    -1
  of arEof:
    t.host.eof = true
    t.host.close()
    0

proc drain*(t: Terminal, maxBytes: int = 1_000_000): int =
  var total = 0
  while total < maxBytes: (let n = t.step(); if n == 0: break; if n < 0: continue; total += n)
  discard t.flush(); total

proc returnToLiveInput*(t: Terminal): bool =
  ## Move a scrolled-back viewport to the live edge before sending child input.
  if t.viewport.isAtLiveEnd:
    return false
  t.viewport.scrollToLiveEnd()
  t.selection.clear()
  t.damage.markAll()
  true

proc sendKey*(t: Terminal, ev: KeyEvent): int =
  let bytes = encodeKeyEvent(ev, t.inputMode)
  if bytes.len == 0:
    return 0
  discard t.returnToLiveInput()
  t.async.send(bytes)

proc sendMouse*(t: Terminal, ev: MouseEvent): int =
  let bytes = encodeMouseEvent(ev, t.inputMode)
  if bytes.len == 0:
    return 0
  discard t.returnToLiveInput()
  t.async.send(bytes)

proc sendPaste*(t: Terminal, text: string): int =
  let bytes = encodePaste(text, t.inputMode)
  if bytes.len == 0:
    return 0
  discard t.returnToLiveInput()
  t.async.send(bytes)
proc sendFocus*(t: Terminal, gained: bool): int = (if not t.inputMode.focusReporting: 0 else: t.sendReport(reportFocus(gained)))
proc sendClipboardResponse*(t: Terminal, selector, text: string): int = (let encoded = encode(text); t.sendReport(reportClipboard(selector, encoded)))
func synchronizedUpdateActive*(t: Terminal): bool = t.syncUpdate.shouldDeferPresent()
proc refreshViewport*(t: Terminal, stickToBottom: bool = true) = t.viewport.updateBufferHeight(t.screen.totalRows, stickToBottom)
proc resize*(t: Terminal, cols, rows: int) = (t.host.resize(cols, rows); t.screen.resize(cols, rows); t.damage.resize(rows); t.viewport.height = rows; t.refreshViewport())
proc resizeView*(t: Terminal, cols, rows: int) = (t.screen.resizePreserveBottom(cols, rows); t.damage.resize(rows); t.viewport.height = rows; t.drag.height = rows; t.refreshViewport())

proc termSignal*(): int =
  when defined(posix): int(SIGTERM)
  else: 15

proc kill*(t: Terminal, signum: int = -1) = 
  let s = if signum == -1: termSignal() else: signum
  t.host.kill(s)

proc waitExit*(t: Terminal): int = t.host.waitExit()
proc close*(t: Terminal) =
  if t == nil or t.host == nil or t.host.closed:
    return
  t.kill()
  t.host.close()
  discard t.waitExit()
