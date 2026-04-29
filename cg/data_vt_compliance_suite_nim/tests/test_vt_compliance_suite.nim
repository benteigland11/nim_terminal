import std/[options, unittest]
import vt_compliance_suite_lib

suite "Vt Compliance Suite":
  test "loads declarative vector suite":
    let cases = loadSuite("src/vectors/core_vt.json")

    check cases.len >= 10
    check cases[0].name == "Plain text layout"
    check cases[0].expect.lines.len == 2

  test "compares passing actual state":
    let tc = ComplianceCase(
      name: "example",
      input: "abc",
      expect: ExpectedState(
        cursorRow: some(0),
        cursorCol: some(3),
        lines: @[(row: 0, text: "abc")],
        cells: @[(row: 0, col: 0, cell: ExpectedCell(rune: uint32('a')))],
      ),
    )

    let actual = actualState(
      cursorRow = some(0),
      cursorCol = some(3),
      lines = @[(row: 0, text: "abc   ")],
      cells = @[(row: 0, col: 0, cell: actualCell(uint32('a')))],
    )

    let result = tc.compare(actual)

    check result.passed
    check result.failures.len == 0

  test "reports cursor, line, and cell failures":
    let tc = ComplianceCase(
      name: "example",
      input: "abc",
      expect: ExpectedState(
        cursorRow: some(0),
        cursorCol: some(3),
        lines: @[(row: 0, text: "abc")],
        cells: @[(row: 0, col: 0, cell: ExpectedCell(rune: uint32('a'), bold: some(true)))],
      ),
    )

    let actual = actualState(
      cursorRow = some(1),
      cursorCol = some(2),
      lines = @[(row: 0, text: "xyz")],
      cells = @[(row: 0, col: 0, cell: actualCell(uint32('x'), bold = false))],
    )

    let result = tc.compare(actual)

    check not result.passed
    check result.failures.len == 5
    check result.failures[0].caseName == "example"

  test "runs suite through provider":
    let cases = @[
      ComplianceCase(
        name: "ok",
        input: "abc",
        expect: ExpectedState(lines: @[(row: 0, text: "abc")]),
      )
    ]

    let summary = runSuite(cases) do (input: string) -> ActualState:
      actualState(lines = @[(row: 0, text: input)])

    check summary.total == 1
    check summary.passed == 1
    check summary.failed == 0
    check summaryLine(summary) == "VT compliance: 1/1 passed, 0 failed"
