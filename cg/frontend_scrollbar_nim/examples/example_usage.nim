## Example usage of Scrollbar.

import scrollbar_lib

# A list of 40 rows, 20 visible, each 18px tall.
let rowH = 18
let m = scrollMetrics(contentSize = 40 * rowH, viewportSize = 20 * rowH, offset = 0)
let track = ScrollbarTrack(x: 300, y: 0, w: 10, h: 20 * rowH)

assert scrollbarVisible(m)
let thumb = computeThumb(track, m)
assert thumb.h < track.h

# User presses the thumb and drags down by dragging the pointer to the track bottom.
let drag = beginThumbDrag(track, m, pointerY = thumb.y + 2)
let newOffset = offsetForDrag(drag, track, m, pointerY = track.y + track.h)
assert newOffset == maxScrollOffset(m)
