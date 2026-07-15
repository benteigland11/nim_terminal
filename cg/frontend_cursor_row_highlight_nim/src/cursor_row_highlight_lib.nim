## Reusable cursor-row highlight policy for terminal-style renderers.
##
## The widget only decides whether a cursor row should receive a viewport-wide
## visual affordance and where that rectangle belongs. Concrete renderers own
## the actual drawing backend.

import std/[options, strutils]

type
  HighlightColor* = object
    r*, g*, b*: uint8

  PixelRect* = object
    x*, y*, w*, h*: int

  CursorRowHighlightStyle* = object
    enabled*: bool
    onlyWhenCursorVisible*: bool
    color*: HighlightColor

  ComposerHighlightStyle* = object
    enabled*: bool
    onlyWhenCursorVisible*: bool
    color*: HighlightColor
    minRows*: int
    maxRows*: int

func highlightColor*(r, g, b: uint8): HighlightColor =
  HighlightColor(r: r, g: g, b: b)

func defaultCursorRowHighlightStyle*(): CursorRowHighlightStyle =
  CursorRowHighlightStyle(
    enabled: true,
    onlyWhenCursorVisible: true,
    color: highlightColor(54, 54, 56),
  )

func defaultComposerHighlightStyle*(): ComposerHighlightStyle =
  ComposerHighlightStyle(
    enabled: true,
    onlyWhenCursorVisible: true,
    color: highlightColor(54, 54, 56),
    minRows: 1,
    maxRows: 3,
  )

func cursorRowHighlightRect*(
    cursorViewportRow, visibleRows, cellHeight: int,
    viewport: PixelRect,
    cursorVisible = true,
    style = defaultCursorRowHighlightStyle(),
  ): Option[PixelRect] =
  if not style.enabled:
    return none(PixelRect)
  if style.onlyWhenCursorVisible and not cursorVisible:
    return none(PixelRect)
  if cursorViewportRow < 0 or cursorViewportRow >= visibleRows:
    return none(PixelRect)
  if cellHeight <= 0 or viewport.w <= 0 or viewport.h <= 0:
    return none(PixelRect)
  let rowY = viewport.y + cursorViewportRow * cellHeight
  if rowY >= viewport.y + viewport.h:
    return none(PixelRect)
  some(PixelRect(
    x: viewport.x,
    y: rowY,
    w: viewport.w,
    h: min(cellHeight, viewport.y + viewport.h - rowY),
  ))

func trimmedRow(row: string): string =
  row.strip(leading = true, trailing = true)

func isCodexPromptRow*(row: string): bool =
  ## Host-side heuristic for Codex-style user prompt rows.
  ##
  ## Codex draws transcript chrome in the cell grid when it can; this only
  ## matches common prompt lead-ins so hosts can paint a soft affordance when
  ## the child used plain text. It is not an official Codex protocol.
  ##
  ## Deliberately does **not** match a bare ASCII `>` lead-in. Shell-style
  ## agent harnesses (Antigravity, Gemini CLI, etc.) use `> /command` and
  ## `>` prompts; treating those as Codex chrome paints full-width gray bands
  ## over live TUI frames. Prefer the Codex `›` / `▌` markers, or a boxed
  ## `│ >` / `| >` prefix which plain shells do not emit.
  let text = row.trimmedRow()
  if text.len == 0:
    return false
  text.startsWith("›") or
    text.startsWith("▌") or
    text.startsWith("│ ›") or
    text.startsWith("| ›") or
    text.startsWith("│ >") or
    text.startsWith("| >")

func isCodexStatusRow(row: string): bool =
  let text = row.trimmedRow()
  (text.startsWith("gpt-") or text.startsWith("o") or text.startsWith("codex-")) and
    " · " in text

func isCodexAnswerLead(row: string): bool =
  let text = row.trimmedRow()
  text.startsWith("•") or text.startsWith("thinking") or text.startsWith("Working")

func codexPromptBlockEnd(visibleRows: openArray[string], promptRow, maxRows: int): int =
  ## Inclusive end is exclusive index: highlights [promptRow, result).
  result = min(visibleRows.len, promptRow + 1)
  let limit = min(visibleRows.len, promptRow + max(1, maxRows) + 1)
  for row in promptRow + 1 ..< limit:
    if isCodexStatusRow(visibleRows[row]) or isCodexAnswerLead(visibleRows[row]) or
        isCodexPromptRow(visibleRows[row]):
      return row
    result = row + 1
  result = min(visibleRows.len, result)

func promptHighlightRect(
    promptRow, rowCount, cellHeight: int,
    viewport: PixelRect,
  ): Option[PixelRect] =
  let rowY = viewport.y + promptRow * cellHeight
  if rowY >= viewport.y + viewport.h:
    return none(PixelRect)
  some(PixelRect(
    x: viewport.x,
    y: rowY,
    w: viewport.w,
    h: min(rowCount * cellHeight, viewport.y + viewport.h - rowY),
  ))

func codexComposerHighlightRect*(
    visibleRows: openArray[string],
    cursorViewportRow, cellHeight: int,
    viewport: PixelRect,
    cursorVisible = true,
    style = defaultComposerHighlightStyle(),
  ): Option[PixelRect] =
  if not style.enabled:
    return none(PixelRect)
  if style.onlyWhenCursorVisible and not cursorVisible:
    return none(PixelRect)
  if cursorViewportRow < 0 or cursorViewportRow >= visibleRows.len:
    return none(PixelRect)
  if cellHeight <= 0 or viewport.w <= 0 or viewport.h <= 0:
    return none(PixelRect)

  var promptRow = cursorViewportRow
  while promptRow >= 0 and promptRow >= cursorViewportRow - 2:
    if isCodexPromptRow(visibleRows[promptRow]):
      break
    dec promptRow
  if promptRow < 0 or not isCodexPromptRow(visibleRows[promptRow]):
    return none(PixelRect)

  let endRow = codexPromptBlockEnd(visibleRows, promptRow, style.maxRows)
  let rowCount = max(style.minRows, endRow - promptRow)
  promptHighlightRect(promptRow, rowCount, cellHeight, viewport)

func codexPromptHighlightRects*(
    visibleRows: openArray[string],
    cellHeight: int,
    viewport: PixelRect,
    cursorVisible = true,
    style = defaultComposerHighlightStyle(),
    requireCursorVisible = false,
  ): seq[PixelRect] =
  ## Return highlight rectangles for every visible Codex prompt block.
  ##
  ## Transcript prompts are independent of the live cursor: hiding the cursor
  ## during a long agent turn must not strip history affordances. Pass
  ## `requireCursorVisible = true` only when the host wants composer-gated paint.
  if not style.enabled:
    return @[]
  if requireCursorVisible and style.onlyWhenCursorVisible and not cursorVisible:
    return @[]
  if cellHeight <= 0 or viewport.w <= 0 or viewport.h <= 0:
    return @[]

  var row = 0
  while row < visibleRows.len:
    if not isCodexPromptRow(visibleRows[row]):
      inc row
      continue
    let endRow = codexPromptBlockEnd(visibleRows, row, style.maxRows)
    let rowCount = max(style.minRows, endRow - row)
    let rect = promptHighlightRect(row, rowCount, cellHeight, viewport)
    if rect.isSome:
      result.add rect.get()
    row = max(row + 1, endRow)
