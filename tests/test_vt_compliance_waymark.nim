import std/[options, strutils, unittest]

import ../cg/data_screen_buffer_nim/src/screen_buffer_lib
import ../cg/data_vt_compliance_suite_nim/src/vt_compliance_suite_lib
import ../src/terminal

proc newMockTerminal(rows, cols: int): Terminal =
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
    syncUpdate: newSyncUpdateState(),
  )
  result.async = newAsyncPty[terminal.CurrentBackend](nil, 1)

proc feed(t: Terminal, value: openArray[byte]) =
  if value.len == 0:
    return
  t.feedBytes(value)

func colorHex(color: PaletteColor): string =
  "#" & color.r.toHex(2) & color.g.toHex(2) & color.b.toHex(2)

func colorSpec(color: Color): Option[string] =
  case color.kind
  of ckDefault:
    none(string)
  of ckIndexed:
    some($color.index)
  of ckRgb:
    some("#" & color.r.toHex(2) & color.g.toHex(2) & color.b.toHex(2))

proc complianceState(inputChunks: openArray[seq[byte]]): ActualState =
  let t = newMockTerminal(10, 20)
  var clipboardRequests: seq[tuple[selector: string, text: string]] = @[]
  t.onClipboardRequest = proc(selector, text: string) =
    clipboardRequests.add (selector: selector, text: text)
  for input in inputChunks:
    t.feed(input)

  result.cursorRow = some(t.screen.cursor.row)
  result.cursorCol = some(t.screen.cursor.col)
  result.title = some(t.screen.title)
  result.iconName = some(t.screen.iconName)
  result.usingAlt = some(t.screen.usingAlt)
  result.cursorVisible = some(t.screen.cursor.visible)
  result.autowrap = some(smAutoWrap in t.screen.modes)
  result.mouseMode = some($t.inputMode.mouseMode)
  result.sgrMouse = some(t.inputMode.sgrMouse)
  result.alternateScroll = some(t.inputMode.alternateScroll)
  result.bracketedPaste = some(t.inputMode.bracketedPaste)
  result.focusReporting = some(t.inputMode.focusReporting)
  result.reports = t.reports
  result.clipboardRequests = clipboardRequests
  for i in 0 .. 15:
    result.palette.add (index: i, color: colorHex(t.screen.theme.ansi[i]))
  result.theme = @[
    (item: "foreground", color: colorHex(t.screen.theme.foreground)),
    (item: "background", color: colorHex(t.screen.theme.background)),
    (item: "cursor", color: colorHex(t.screen.theme.cursor)),
  ]

  for row in 0 ..< t.screen.rows:
    result.lines.add (row: row, text: t.screen.lineText(row))
    for col in 0 ..< t.screen.cols:
      let cell = t.screen.cellAt(row, col)
      result.cells.add (
        row: row,
        col: col,
        cell: actualCell(
          rune = cell.rune,
          fg = colorSpec(cell.attrs.fg),
          bg = colorSpec(cell.attrs.bg),
          bold = afBold in cell.attrs.flags,
          dim = afDim in cell.attrs.flags,
          italic = afItalic in cell.attrs.flags,
          underline = afUnderline in cell.attrs.flags,
          inverse = afInverse in cell.attrs.flags,
          hidden = afHidden in cell.attrs.flags,
          strike = afStrike in cell.attrs.flags,
          overline = afOverline in cell.attrs.flags,
        ),
      )

suite "Waymark VT compliance":
  test "core vector suite passes":
    let cases = loadSuite("cg/data_vt_compliance_suite_nim/src/vectors/core_vt.json")
    let summary = runSuite(cases, ByteChunkedStateProvider(complianceState))

    check summaryLine(summary) == "VT compliance: " & $cases.len & "/" & $cases.len & " passed, 0 failed"
    if summary.failed > 0:
      for failure in summary.failures:
        checkpoint failure.caseName & " " & failure.path & " expected=" & failure.expected & " actual=" & failure.actual
    check summary.failed == 0
