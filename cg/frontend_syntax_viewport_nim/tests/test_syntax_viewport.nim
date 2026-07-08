import std/unittest
import syntax_viewport_lib

suite "syntax viewport":
  test "wraps and colors source lines":
    let source = "proc main() =\n  echo 42"
    let spans = @[
      (0, 4, tvKeyword),
      (12, 13, tvOperator),
      (17, 19, tvNumber),
    ]
    let viewport = buildSourceViewport(source, spans, cols = 16, maxRows = 2, scrollRow = 0)
    check viewport.totalLines == 2
    check viewport.lines.len == 2
    check viewport.lines[0].runs.len > 0

  test "clips to scroll window":
    let source = "a\nb\nc\nd"
    let viewport = buildSourceViewport(source, @[], cols = 4, maxRows = 2, scrollRow = 1)
    check viewport.lines.len == 2
    check viewport.scrollRow == 1
