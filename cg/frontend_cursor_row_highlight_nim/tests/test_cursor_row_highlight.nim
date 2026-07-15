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

  test "bare ASCII > shell and agent-harness prompts are not Codex chrome":
    ## Antigravity / Gemini CLI / plain shells use `>` — must not light up.
    check isCodexPromptRow("> /skills") == false
    check isCodexPromptRow("> /add-dir") == false
    check isCodexPromptRow(">") == false
    check isCodexPromptRow("> Write a summary") == false
    check isCodexPromptRow("  > markdown blockquote") == false
    let rows = [
      "### Skill Folder Structure",
      "> /skills",
      "  tree content under the command chrome",
      "  more residual line",
      "  status · Gemini 3.5 Flash (Medium)",
    ]
    check codexPromptHighlightRects(rows, 18, PixelRect(x: 0, y: 0, w: 500, h: 120)).len == 0
    check codexComposerHighlightRect(rows, 1, 18, PixelRect(x: 0, y: 0, w: 500, h: 120)).isNone

  test "boxed ASCII > still counts as Codex-style chrome":
    check isCodexPromptRow("│ > draft a plan")
    check isCodexPromptRow("| > draft a plan")

  test "codex prompt highlights include transcript prompts":
    let rows = [
      "› earlier request",
      "",
      "• earlier answer",
      "",
      "› current request",
      "",
      "  gpt-5.5 medium · ~/project",
    ]
    let rects = codexPromptHighlightRects(rows, 20, PixelRect(x: 2, y: 4, w: 500, h: 180))
    check rects.len == 2
    ## Historic prompt includes the blank spacer before the answer lead.
    check rects[0] == PixelRect(x: 2, y: 4, w: 500, h: 40)
    check rects[1] == PixelRect(x: 2, y: 84, w: 500, h: 40)

  test "transcript prompt highlights keep showing when cursor is hidden":
    let rows = [
      "› earlier request",
      "",
      "  gpt-5.5 medium · ~/project",
    ]
    ## Default path is for history chrome — agent turns hide the cursor.
    check codexPromptHighlightRects(
      rows,
      20,
      PixelRect(x: 0, y: 0, w: 500, h: 100),
      cursorVisible = false,
    ).len == 1

  test "composer-gated path can still require a visible cursor":
    let rows = [
      "› earlier request",
      "",
      "  gpt-5.5 medium · ~/project",
    ]
    check codexPromptHighlightRects(
      rows,
      20,
      PixelRect(x: 0, y: 0, w: 500, h: 100),
      cursorVisible = false,
      requireCursorVisible = true,
    ).len == 0
