import std/[options, unittest]
import ../src/cursor_row_highlight_lib

suite "cursor row highlight policy":
  test "default style highlights visible cursor row":
    let rect = cursorRowHighlightRect(
      cursorViewportRow = 2,
      visibleRows = 10,
      cellHeight = 18,
      viewport = PixelRect(x: 4, y: 8, w: 300, h: 200),
    )
    check rect.isSome
    check rect.get() == PixelRect(x: 4, y: 44, w: 300, h: 18)

  test "style can disable highlight":
    var style = defaultCursorRowHighlightStyle()
    style.enabled = false
    check cursorRowHighlightRect(0, 10, 18, PixelRect(x: 0, y: 0, w: 100, h: 100), style = style).isNone

  test "hidden cursor suppresses highlight when configured":
    check cursorRowHighlightRect(0, 10, 18, PixelRect(x: 0, y: 0, w: 100, h: 100), cursorVisible = false).isNone

  test "offscreen cursor row does not highlight":
    check cursorRowHighlightRect(-1, 10, 18, PixelRect(x: 0, y: 0, w: 100, h: 100)).isNone
    check cursorRowHighlightRect(10, 10, 18, PixelRect(x: 0, y: 0, w: 100, h: 100)).isNone

  test "last visible row clips to viewport height":
    let rect = cursorRowHighlightRect(2, 3, 18, PixelRect(x: 0, y: 0, w: 100, h: 50))
    check rect.isSome
    check rect.get() == PixelRect(x: 0, y: 36, w: 100, h: 14)

  test "codex composer highlights prompt through blank spacer before status row":
    let rows = [
      "  Tip: Use /mcp to list configured MCP tools.",
      "",
      "› Write tests for @filename",
      "",
      "  gpt-5.5 medium · ~/project",
    ]
    let rect = codexComposerHighlightRect(rows, 2, 20, PixelRect(x: 8, y: 10, w: 500, h: 120))
    check rect.isSome
    check rect.get() == PixelRect(x: 8, y: 50, w: 500, h: 40)

  test "codex composer can resolve cursor on continuation line":
    let rows = [
      "› first line",
      "  second line",
      "  gpt-5.5 medium · ~/project",
    ]
    let rect = codexComposerHighlightRect(rows, 1, 18, PixelRect(x: 0, y: 0, w: 400, h: 80))
    check rect.isSome
    check rect.get() == PixelRect(x: 0, y: 0, w: 400, h: 36)

  test "non-codex prompt rows are not highlighted":
    let rows = [
      "$ make test",
      "",
      "shell output",
    ]
    check codexComposerHighlightRect(rows, 0, 18, PixelRect(x: 0, y: 0, w: 400, h: 80)).isNone
