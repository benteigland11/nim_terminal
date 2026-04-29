## VT compliance vector loader and generic assertion harness.
##
## The widget owns the declarative test format and comparison logic. Callers
## adapt their own terminal implementation into ActualState.

import std/[json, options, strutils]

type
  ExpectedCell* = object
    rune*: uint32
    fg*: Option[string]
    bg*: Option[string]
    bold*: Option[bool]
    dim*: Option[bool]
    italic*: Option[bool]
    underline*: Option[bool]
    inverse*: Option[bool]
    hidden*: Option[bool]
    strike*: Option[bool]
    overline*: Option[bool]

  ActualCell* = object
    rune*: uint32
    fg*: Option[string]
    bg*: Option[string]
    bold*: bool
    dim*: bool
    italic*: bool
    underline*: bool
    inverse*: bool
    hidden*: bool
    strike*: bool
    overline*: bool

  ExpectedState* = object
    cursorRow*: Option[int]
    cursorCol*: Option[int]
    title*: Option[string]
    iconName*: Option[string]
    usingAlt*: Option[bool]
    cursorVisible*: Option[bool]
    autowrap*: Option[bool]
    mouseMode*: Option[string]
    sgrMouse*: Option[bool]
    alternateScroll*: Option[bool]
    bracketedPaste*: Option[bool]
    focusReporting*: Option[bool]
    palette*: seq[tuple[index: int, color: string]]
    theme*: seq[tuple[item: string, color: string]]
    reports*: seq[string]
    clipboardRequests*: seq[tuple[selector: string, text: string]]
    cells*: seq[tuple[row, col: int, cell: ExpectedCell]]
    lines*: seq[tuple[row: int, text: string]]

  ActualState* = object
    cursorRow*: Option[int]
    cursorCol*: Option[int]
    title*: Option[string]
    iconName*: Option[string]
    usingAlt*: Option[bool]
    cursorVisible*: Option[bool]
    autowrap*: Option[bool]
    mouseMode*: Option[string]
    sgrMouse*: Option[bool]
    alternateScroll*: Option[bool]
    bracketedPaste*: Option[bool]
    focusReporting*: Option[bool]
    palette*: seq[tuple[index: int, color: string]]
    theme*: seq[tuple[item: string, color: string]]
    reports*: seq[string]
    clipboardRequests*: seq[tuple[selector: string, text: string]]
    cells*: seq[tuple[row, col: int, cell: ActualCell]]
    lines*: seq[tuple[row: int, text: string]]

  ComplianceCase* = object
    name*: string
    input*: string
    expect*: ExpectedState

  ComplianceFailure* = object
    caseName*: string
    path*: string
    expected*: string
    actual*: string

  ComplianceResult* = object
    caseName*: string
    passed*: bool
    failures*: seq[ComplianceFailure]

  ComplianceSummary* = object
    total*: int
    passed*: int
    failed*: int
    failures*: seq[ComplianceFailure]

  StateProvider* = proc(input: string): ActualState {.closure.}

func actualCell*(
    rune: uint32,
    fg: Option[string] = none(string),
    bg: Option[string] = none(string),
    bold = false,
    dim = false,
    italic = false,
    underline = false,
    inverse = false,
    hidden = false,
    strike = false,
    overline = false
): ActualCell =
  ActualCell(
    rune: rune,
    fg: fg,
    bg: bg,
    bold: bold,
    dim: dim,
    italic: italic,
    underline: underline,
    inverse: inverse,
    hidden: hidden,
    strike: strike,
    overline: overline,
  )

func actualState*(
    cursorRow: Option[int] = none(int),
    cursorCol: Option[int] = none(int),
    title: Option[string] = none(string),
    iconName: Option[string] = none(string),
    usingAlt: Option[bool] = none(bool),
    cursorVisible: Option[bool] = none(bool),
    autowrap: Option[bool] = none(bool),
    mouseMode: Option[string] = none(string),
    sgrMouse: Option[bool] = none(bool),
    alternateScroll: Option[bool] = none(bool),
    bracketedPaste: Option[bool] = none(bool),
    focusReporting: Option[bool] = none(bool),
    palette: seq[tuple[index: int, color: string]] = @[],
    theme: seq[tuple[item: string, color: string]] = @[],
    reports: seq[string] = @[],
    clipboardRequests: seq[tuple[selector: string, text: string]] = @[],
    cells: seq[tuple[row, col: int, cell: ActualCell]] = @[],
    lines: seq[tuple[row: int, text: string]] = @[]
): ActualState =
  ActualState(
    cursorRow: cursorRow,
    cursorCol: cursorCol,
    title: title,
    iconName: iconName,
    usingAlt: usingAlt,
    cursorVisible: cursorVisible,
    autowrap: autowrap,
    mouseMode: mouseMode,
    sgrMouse: sgrMouse,
    alternateScroll: alternateScroll,
    bracketedPaste: bracketedPaste,
    focusReporting: focusReporting,
    palette: palette,
    theme: theme,
    reports: reports,
    clipboardRequests: clipboardRequests,
    cells: cells,
    lines: lines,
  )

func parseExpectedCell(node: JsonNode): ExpectedCell =
  result.rune = node["rune"].getInt().uint32
  if node.hasKey("fg"): result.fg = some(node["fg"].getStr())
  if node.hasKey("bg"): result.bg = some(node["bg"].getStr())
  if node.hasKey("bold"): result.bold = some(node["bold"].getBool())
  if node.hasKey("dim"): result.dim = some(node["dim"].getBool())
  if node.hasKey("italic"): result.italic = some(node["italic"].getBool())
  if node.hasKey("underline"): result.underline = some(node["underline"].getBool())
  if node.hasKey("inverse"): result.inverse = some(node["inverse"].getBool())
  if node.hasKey("hidden"): result.hidden = some(node["hidden"].getBool())
  if node.hasKey("strike"): result.strike = some(node["strike"].getBool())
  if node.hasKey("overline"): result.overline = some(node["overline"].getBool())

func parseExpectedState(node: JsonNode): ExpectedState =
  if node.hasKey("cursor"):
    result.cursorRow = some(node["cursor"][0].getInt())
    result.cursorCol = some(node["cursor"][1].getInt())
  if node.hasKey("title"): result.title = some(node["title"].getStr())
  if node.hasKey("iconName"): result.iconName = some(node["iconName"].getStr())
  if node.hasKey("usingAlt"): result.usingAlt = some(node["usingAlt"].getBool())
  if node.hasKey("cursorVisible"): result.cursorVisible = some(node["cursorVisible"].getBool())
  if node.hasKey("autowrap"): result.autowrap = some(node["autowrap"].getBool())
  if node.hasKey("mouseMode"): result.mouseMode = some(node["mouseMode"].getStr())
  if node.hasKey("sgrMouse"): result.sgrMouse = some(node["sgrMouse"].getBool())
  if node.hasKey("alternateScroll"): result.alternateScroll = some(node["alternateScroll"].getBool())
  if node.hasKey("bracketedPaste"): result.bracketedPaste = some(node["bracketedPaste"].getBool())
  if node.hasKey("focusReporting"): result.focusReporting = some(node["focusReporting"].getBool())
  if node.hasKey("palette"):
    for key, val in node["palette"].pairs:
      result.palette.add (index: parseInt(key), color: val.getStr())
  if node.hasKey("theme"):
    for key, val in node["theme"].pairs:
      result.theme.add (item: key, color: val.getStr())
  if node.hasKey("reports"):
    for item in node["reports"]:
      result.reports.add item.getStr()
  if node.hasKey("clipboardRequests"):
    for item in node["clipboardRequests"]:
      result.clipboardRequests.add (selector: item["selector"].getStr(), text: item["text"].getStr())

  if node.hasKey("cells"):
    for key, val in node["cells"].pairs:
      let parts = key.split(',')
      if parts.len == 2:
        result.cells.add (parseInt(parts[0]), parseInt(parts[1]), parseExpectedCell(val))

  if node.hasKey("lines"):
    for key, val in node["lines"].pairs:
      result.lines.add (parseInt(key), val.getStr())

func parseComplianceCase*(node: JsonNode): ComplianceCase =
  result.name = node["name"].getStr()
  result.input = node["input"].getStr()
  result.expect = parseExpectedState(node["expect"])

proc loadSuite*(path: string): seq[ComplianceCase] =
  let data = parseFile(path)
  for item in data:
    result.add parseComplianceCase(item)

func rstripLine(value: string): string =
  value.strip(leading = false, trailing = true)

func findLine(state: ActualState, row: int): Option[string] =
  for item in state.lines:
    if item.row == row:
      return some(item.text)
  none(string)

func findCell(state: ActualState, row, col: int): Option[ActualCell] =
  for item in state.cells:
    if item.row == row and item.col == col:
      return some(item.cell)
  none(ActualCell)

func findPalette(state: ActualState, index: int): Option[string] =
  for item in state.palette:
    if item.index == index:
      return some(item.color)
  none(string)

func findTheme(state: ActualState, item: string): Option[string] =
  for value in state.theme:
    if value.item == item:
      return some(value.color)
  none(string)

func addFailure(
    failures: var seq[ComplianceFailure],
    caseName, path, expected, actual: string
) =
  failures.add ComplianceFailure(
    caseName: caseName,
    path: path,
    expected: expected,
    actual: actual,
  )

func compareCell(caseName: string, row, col: int, expected: ExpectedCell, actual: ActualCell): seq[ComplianceFailure] =
  if actual.rune != expected.rune:
    result.add ComplianceFailure(
      caseName: caseName,
      path: "cells[" & $row & "," & $col & "].rune",
      expected: $expected.rune,
      actual: $actual.rune,
    )
  if expected.bold.isSome and actual.bold != expected.bold.get():
    result.add ComplianceFailure(
      caseName: caseName,
      path: "cells[" & $row & "," & $col & "].bold",
      expected: $expected.bold.get(),
      actual: $actual.bold,
    )

  template compareFlag(fieldName: untyped, label: string) =
    if expected.fieldName.isSome and actual.fieldName != expected.fieldName.get():
      result.add ComplianceFailure(
        caseName: caseName,
        path: "cells[" & $row & "," & $col & "]." & label,
        expected: $expected.fieldName.get(),
        actual: $actual.fieldName,
      )

  compareFlag(dim, "dim")
  compareFlag(italic, "italic")
  compareFlag(underline, "underline")
  compareFlag(inverse, "inverse")
  compareFlag(hidden, "hidden")
  compareFlag(strike, "strike")
  compareFlag(overline, "overline")

  if expected.fg.isSome and actual.fg != expected.fg:
    result.add ComplianceFailure(
      caseName: caseName,
      path: "cells[" & $row & "," & $col & "].fg",
      expected: expected.fg.get(),
      actual: if actual.fg.isSome: actual.fg.get() else: "",
    )
  if expected.bg.isSome and actual.bg != expected.bg:
    result.add ComplianceFailure(
      caseName: caseName,
      path: "cells[" & $row & "," & $col & "].bg",
      expected: expected.bg.get(),
      actual: if actual.bg.isSome: actual.bg.get() else: "",
    )

func compare*(tc: ComplianceCase, actual: ActualState): ComplianceResult =
  result.caseName = tc.name

  if tc.expect.cursorRow.isSome:
    let actualRow = if actual.cursorRow.isSome: $actual.cursorRow.get() else: ""
    if actual.cursorRow != tc.expect.cursorRow:
      result.failures.addFailure(tc.name, "cursor.row", $tc.expect.cursorRow.get(), actualRow)

  if tc.expect.cursorCol.isSome:
    let actualCol = if actual.cursorCol.isSome: $actual.cursorCol.get() else: ""
    if actual.cursorCol != tc.expect.cursorCol:
      result.failures.addFailure(tc.name, "cursor.col", $tc.expect.cursorCol.get(), actualCol)

  template compareOption(fieldName: untyped, label: string) =
    if tc.expect.fieldName.isSome:
      let actualValue = if actual.fieldName.isSome: $actual.fieldName.get() else: ""
      if actual.fieldName != tc.expect.fieldName:
        result.failures.addFailure(tc.name, label, $tc.expect.fieldName.get(), actualValue)

  compareOption(title, "title")
  compareOption(iconName, "iconName")
  compareOption(usingAlt, "usingAlt")
  compareOption(cursorVisible, "cursorVisible")
  compareOption(autowrap, "autowrap")
  compareOption(mouseMode, "mouseMode")
  compareOption(sgrMouse, "sgrMouse")
  compareOption(alternateScroll, "alternateScroll")
  compareOption(bracketedPaste, "bracketedPaste")
  compareOption(focusReporting, "focusReporting")

  for item in tc.expect.palette:
    let actualColor = actual.findPalette(item.index)
    if actualColor.isNone:
      result.failures.addFailure(tc.name, "palette[" & $item.index & "]", item.color, "")
    elif actualColor.get() != item.color:
      result.failures.addFailure(tc.name, "palette[" & $item.index & "]", item.color, actualColor.get())

  for item in tc.expect.theme:
    let actualColor = actual.findTheme(item.item)
    if actualColor.isNone:
      result.failures.addFailure(tc.name, "theme[" & item.item & "]", item.color, "")
    elif actualColor.get() != item.color:
      result.failures.addFailure(tc.name, "theme[" & item.item & "]", item.color, actualColor.get())

  for i, expectedReport in tc.expect.reports:
    let actualReport = if i < actual.reports.len: actual.reports[i] else: ""
    if actualReport != expectedReport:
      result.failures.addFailure(tc.name, "reports[" & $i & "]", expectedReport, actualReport)

  for i, expectedRequest in tc.expect.clipboardRequests:
    if i >= actual.clipboardRequests.len:
      result.failures.addFailure(tc.name, "clipboardRequests[" & $i & "]", expectedRequest.selector & ":" & expectedRequest.text, "")
    else:
      let actualRequest = actual.clipboardRequests[i]
      if actualRequest != expectedRequest:
        result.failures.addFailure(
          tc.name,
          "clipboardRequests[" & $i & "]",
          expectedRequest.selector & ":" & expectedRequest.text,
          actualRequest.selector & ":" & actualRequest.text,
        )

  for item in tc.expect.lines:
    let actualLine = actual.findLine(item.row)
    if actualLine.isNone:
      result.failures.addFailure(tc.name, "lines[" & $item.row & "]", item.text, "")
    elif rstripLine(actualLine.get()) != item.text:
      result.failures.addFailure(tc.name, "lines[" & $item.row & "]", item.text, rstripLine(actualLine.get()))

  for item in tc.expect.cells:
    let actualCellValue = actual.findCell(item.row, item.col)
    if actualCellValue.isNone:
      result.failures.addFailure(tc.name, "cells[" & $item.row & "," & $item.col & "]", $item.cell.rune, "")
    else:
      result.failures.add compareCell(tc.name, item.row, item.col, item.cell, actualCellValue.get())

  result.passed = result.failures.len == 0

proc runCase*(tc: ComplianceCase, provider: StateProvider): ComplianceResult =
  tc.compare(provider(tc.input))

proc runSuite*(cases: openArray[ComplianceCase], provider: StateProvider): ComplianceSummary =
  for tc in cases:
    inc result.total
    let item = tc.runCase(provider)
    if item.passed:
      inc result.passed
    else:
      inc result.failed
      result.failures.add item.failures

func summaryLine*(summary: ComplianceSummary): string =
  "VT compliance: " & $summary.passed & "/" & $summary.total & " passed, " & $summary.failed & " failed"
