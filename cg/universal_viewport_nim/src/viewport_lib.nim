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

func newViewport*(height: int): Viewport =
  Viewport(height: height, totalRows: height, scrollOffset: 0)

func maxScroll*(v: Viewport): int =
  ## Maximum valid scrollOffset.
  max(0, v.totalRows - v.height)

func scrollUp*(v: var Viewport, count: int = 1) =
  ## Scroll up (towards history).
  v.scrollOffset = min(v.maxScroll, v.scrollOffset + count)

func scrollDown*(v: var Viewport, count: int = 1) =
  ## Scroll down (towards active grid).
  v.scrollOffset = max(0, v.scrollOffset - count)

func scrollToBottom*(v: var Viewport) =
  v.scrollOffset = 0

func isAtBottom*(v: Viewport): bool = v.scrollOffset == 0

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
