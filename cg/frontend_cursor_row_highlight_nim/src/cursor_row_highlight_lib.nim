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

func isCodexPromptRow(row: string): bool =
  let text = row.trimmedRow()
  text.startsWith("›") or text.startsWith(">")

func isCodexStatusRow(row: string): bool =
  let text = row.trimmedRow()
  (text.startsWith("gpt-") or text.startsWith("o") or text.startsWith("codex-")) and
    " · " in text

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

  var endRow = min(visibleRows.len, promptRow + max(1, style.maxRows))
  for row in promptRow + 1 ..< min(visibleRows.len, promptRow + max(1, style.maxRows) + 1):
    if isCodexStatusRow(visibleRows[row]):
      endRow = row
      break

  let rowCount = max(style.minRows, endRow - promptRow)
  let rowY = viewport.y + promptRow * cellHeight
  if rowY >= viewport.y + viewport.h:
    return none(PixelRect)
  some(PixelRect(
    x: viewport.x,
    y: rowY,
    w: viewport.w,
    h: min(rowCount * cellHeight, viewport.y + viewport.h - rowY),
  ))
