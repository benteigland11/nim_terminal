## Vertical scrollbar model: thumb geometry, hit testing, and drag math.
##
## Pure logic — no rendering and no input backend. The host describes the
## scrollable content (total size, viewport size, current offset) and the track
## rectangle; this computes the thumb rect, converts pointer drags into new
## offsets, and handles track clicks. Sizes are in pixels but any consistent
## unit works. Decoupling scroll from wheel/key events lets a draggable
## scrollbar coexist with a surface that owns those events (e.g. a terminal).

type
  ScrollMetrics* = object
    contentSize*: int    ## Total scrollable content extent.
    viewportSize*: int   ## Visible extent.
    offset*: int         ## Current scroll offset, 0 .. maxScrollOffset.

  ScrollbarTrack* = object
    x*, y*, w*, h*: int

  ScrollbarThumb* = object
    x*, y*, w*, h*: int

  ScrollbarDrag* = object
    active*: bool
    grabDy*: int         ## Pointer offset from the thumb top when grabbed.

const DefaultMinThumb* = 24

func scrollMetrics*(contentSize, viewportSize, offset: int): ScrollMetrics =
  ScrollMetrics(contentSize: contentSize, viewportSize: viewportSize, offset: offset)

func maxScrollOffset*(m: ScrollMetrics): int =
  max(0, m.contentSize - m.viewportSize)

func clampScrollOffset*(m: ScrollMetrics): ScrollMetrics =
  result = m
  result.offset = max(0, min(m.offset, maxScrollOffset(m)))

func scrollbarVisible*(m: ScrollMetrics): bool =
  ## Whether content overflows the viewport (i.e. a scrollbar is meaningful).
  m.contentSize > m.viewportSize and m.viewportSize > 0

func thumbLength*(trackLength: int; m: ScrollMetrics; minThumb = DefaultMinThumb): int =
  if m.contentSize <= 0 or trackLength <= 0:
    return 0
  let raw = (trackLength * m.viewportSize) div max(1, m.contentSize)
  result = max(min(minThumb, trackLength), raw)
  result = min(result, trackLength)

func thumbTop*(trackLength: int; m: ScrollMetrics; thumbLen: int): int =
  ## Thumb top offset within the track (0-based) for the current offset.
  let travel = trackLength - thumbLen
  let maxOff = maxScrollOffset(m)
  if travel <= 0 or maxOff <= 0:
    0
  else:
    (travel * max(0, min(m.offset, maxOff))) div maxOff

func computeThumb*(
    track: ScrollbarTrack; m: ScrollMetrics; minThumb = DefaultMinThumb): ScrollbarThumb =
  let len = thumbLength(track.h, m, minThumb)
  ScrollbarThumb(
    x: track.x,
    y: track.y + thumbTop(track.h, m, len),
    w: track.w,
    h: len,
  )

func pointInThumb*(thumb: ScrollbarThumb; x, y: int): bool =
  thumb.w > 0 and thumb.h > 0 and
    x >= thumb.x and x < thumb.x + thumb.w and
    y >= thumb.y and y < thumb.y + thumb.h

func pointInTrack*(track: ScrollbarTrack; x, y: int): bool =
  track.w > 0 and track.h > 0 and
    x >= track.x and x < track.x + track.w and
    y >= track.y and y < track.y + track.h

func offsetForThumbTop*(
    track: ScrollbarTrack; m: ScrollMetrics; thumbTopWithinTrack: int;
    minThumb = DefaultMinThumb): int =
  ## Invert thumb geometry: the offset that places the thumb top at the given
  ## position within the track. Result is clamped to the valid range.
  let len = thumbLength(track.h, m, minThumb)
  let travel = track.h - len
  let maxOff = maxScrollOffset(m)
  if travel <= 0 or maxOff <= 0:
    return 0
  let clampedTop = max(0, min(thumbTopWithinTrack, travel))
  max(0, min(maxOff, (clampedTop * maxOff) div travel))

func beginThumbDrag*(
    track: ScrollbarTrack; m: ScrollMetrics; pointerY: int;
    minThumb = DefaultMinThumb): ScrollbarDrag =
  ## Start a drag from a pointer press. If the press is on the thumb, the grab
  ## offset preserves the grab point; otherwise the thumb centers on the pointer.
  let thumb = computeThumb(track, m, minThumb)
  if pointInThumb(thumb, thumb.x, pointerY):
    ScrollbarDrag(active: true, grabDy: pointerY - thumb.y)
  else:
    ScrollbarDrag(active: true, grabDy: thumb.h div 2)

func offsetForDrag*(
    drag: ScrollbarDrag; track: ScrollbarTrack; m: ScrollMetrics; pointerY: int;
    minThumb = DefaultMinThumb): int =
  ## New scroll offset for a drag update at pointerY.
  if not drag.active:
    return m.offset
  let thumbTopWithinTrack = pointerY - track.y - drag.grabDy
  offsetForThumbTop(track, m, thumbTopWithinTrack, minThumb)
