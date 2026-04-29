## Coordinate-mapping viewport manager.
##
## Tracks a "view window" into a larger buffer with history (scrollback).
## Translates viewport-relative row indices (0 to height-1) into
## absolute buffer-relative indices.
##
## This widget is pure math/logic for managing scroll offsets and
## visibility.

type
  Viewport* = object
    height*: int           ## Number of rows visible at once
    totalRows*: int        ## Total rows currently in the buffer (history + active)
    scrollOffset*: int     ## How many rows we are scrolled up (0 = bottom)

  ViewAnchor* = object
    topRow*: int
    targetRow*: int
    targetViewportRow*: int
    atBottom*: bool

func newViewport*(height: int): Viewport =
  Viewport(height: height, totalRows: height, scrollOffset: 0)

func maxScroll*(v: Viewport): int =
  ## Maximum valid scrollOffset.
  max(0, v.totalRows - v.height)

func hasMeaningfulHistory*(v: Viewport, minRows: int = 3): bool =
  ## True when the viewport has enough retained rows that wheel input can
  ## reasonably scroll terminal-owned history instead of incidental churn.
  v.maxScroll >= max(1, minRows)

func scrollUp*(v: var Viewport, count: int = 1) =
  ## Scroll up (towards history).
  v.scrollOffset = min(v.maxScroll, v.scrollOffset + count)

func scrollDown*(v: var Viewport, count: int = 1) =
  ## Scroll down (towards active grid).
  v.scrollOffset = max(0, v.scrollOffset - count)

func scrollToBottom*(v: var Viewport) =
  v.scrollOffset = 0

func isAtBottom*(v: Viewport): bool = v.scrollOffset == 0

func scrollToLiveEnd*(v: var Viewport) =
  ## Return the viewport to the live edge of the buffer.
  v.scrollToBottom()

func isAtLiveEnd*(v: Viewport): bool =
  ## True when the viewport is following the newest rows in the buffer.
  v.isAtBottom

func updateBufferHeight*(v: var Viewport, totalRows: int, stickToBottom: bool = true) =
  ## Update total buffer size. If `stickToBottom` is true and we were
  ## at the bottom, stay at the bottom.
  let wasAtBottom = v.isAtBottom
  v.totalRows = totalRows
  if stickToBottom and wasAtBottom:
    v.scrollToBottom()
  else:
    # Ensure offset is still valid
    v.scrollOffset = min(v.maxScroll, v.scrollOffset)

func viewportToBuffer*(v: Viewport, viewportRow: int): int =
  ## Map a row index from the viewport (0 = top row visible) to an
  ## absolute index in the buffer (0 = oldest history row).
  ## Returns -1 if out of visible range.
  if viewportRow < 0 or viewportRow >= v.height: return -1
  
  # Absolute bottom row index = totalRows - 1
  # Current bottom row index = (totalRows - 1) - scrollOffset
  # Current top row index    = currentBottom - (height - 1)
  let currentBottom = v.totalRows - 1 - v.scrollOffset
  let currentTop = currentBottom - (v.height - 1)
  currentTop + viewportRow

func bufferToViewport*(v: Viewport, bufferRow: int): int =
  ## Map an absolute buffer index to a viewport-relative index.
  ## Returns -1 if the buffer row is not currently visible.
  let currentBottom = v.totalRows - 1 - v.scrollOffset
  let currentTop = currentBottom - (v.height - 1)
  if bufferRow < currentTop or bufferRow > currentBottom: return -1
  bufferRow - currentTop

proc ensureVisible*(v: var Viewport, bufferRow: int, contextRowsAbove: int = 0) =
  ## Scroll just enough to make `bufferRow` visible.
  ##
  ## When the row is outside the current view, prefer keeping a small amount of
  ## context above it. Already-visible rows are left untouched.
  if bufferRow < 0: return
  v.updateBufferHeight(v.totalRows, false)
  if v.bufferToViewport(bufferRow) != -1: return
  let context = max(0, min(contextRowsAbove, bufferRow))
  let preferredTop = max(0, min(bufferRow - context, max(0, v.totalRows - v.height)))
  let desiredOffset = v.totalRows - v.height - preferredTop
  v.scrollOffset = max(0, min(v.maxScroll, desiredOffset))

func captureAnchor*(v: Viewport, targetBufferRow: int): ViewAnchor =
  ## Capture a row to keep visible across a viewport/total-height change.
  ViewAnchor(
    topRow: v.viewportToBuffer(0),
    targetRow: targetBufferRow,
    targetViewportRow: v.bufferToViewport(targetBufferRow),
    atBottom: v.isAtBottom,
  )

func captureResizeAnchor*(v: Viewport, targetBufferRow: int): ViewAnchor =
  ## Capture a stable resize anchor.
  ##
  ## If the target row is visible, preserve that row. If it is not visible,
  ## preserve the current top row instead so scrolled-back views do not snap
  ## back to an off-screen cursor during zoom or resize.
  let targetViewport = v.bufferToViewport(targetBufferRow)
  ViewAnchor(
    topRow: v.viewportToBuffer(0),
    targetRow: if targetViewport >= 0: targetBufferRow else: -1,
    targetViewportRow: targetViewport,
    atBottom: v.isAtBottom,
  )

proc restoreAnchor*(
    v: var Viewport,
    totalRows, height: int,
    anchor: ViewAnchor,
    contextRowsAbove: int = 0,
    preserveTopWhilePossible: bool = true,
    pinBottom: bool = true
) =
  ## Restore viewport position after dimensions changed.
  ##
  ## When possible, preserves the old top row. If that would hide the target
  ## row, keeps `contextRowsAbove` rows above the target instead.
  v.height = max(1, height)
  v.updateBufferHeight(max(1, totalRows), false)
  if anchor.targetRow < 0:
    if anchor.topRow >= 0:
      let desiredOffset = v.totalRows - v.height - anchor.topRow
      v.scrollOffset = max(0, min(v.maxScroll, desiredOffset))
    else:
      v.scrollToBottom()
    return
  if pinBottom and anchor.atBottom:
    v.scrollToBottom()
    return

  let context = max(0, min(contextRowsAbove, anchor.targetRow))
  let oldTopShowsTarget =
    preserveTopWhilePossible and
    anchor.topRow >= 0 and
    anchor.targetRow - anchor.topRow >= context and
    anchor.targetRow - anchor.topRow < v.height
  let preferredTop =
    if oldTopShowsTarget: anchor.topRow
    else: anchor.targetRow - context
  let desiredOffset = v.totalRows - v.height - preferredTop
  v.scrollOffset = max(0, min(v.maxScroll, desiredOffset))
