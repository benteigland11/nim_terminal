import std/unittest
import scrollbar_lib

suite "scrollbar":
  test "visibility and max offset":
    check scrollbarVisible(scrollMetrics(200, 100, 0))
    check not scrollbarVisible(scrollMetrics(80, 100, 0))
    check maxScrollOffset(scrollMetrics(200, 100, 0)) == 100
    check maxScrollOffset(scrollMetrics(50, 100, 0)) == 0

  test "offset clamps into range":
    check clampScrollOffset(scrollMetrics(200, 100, 500)).offset == 100
    check clampScrollOffset(scrollMetrics(200, 100, -5)).offset == 0

  test "thumb length is proportional with a floor":
    let track = ScrollbarTrack(x: 0, y: 0, w: 8, h: 100)
    check thumbLength(track.h, scrollMetrics(200, 100, 0)) == 50
    check thumbLength(track.h, scrollMetrics(10000, 100, 0), minThumb = 24) == 24
    check thumbLength(track.h, scrollMetrics(100, 100, 0)) == 100

  test "thumb slides from top to bottom with offset":
    let track = ScrollbarTrack(x: 0, y: 10, w: 8, h: 100)
    let atTop = computeThumb(track, scrollMetrics(200, 100, 0))
    check atTop.y == 10
    let atBottom = computeThumb(track, scrollMetrics(200, 100, 100))
    check atBottom.y == 10 + (100 - atBottom.h)

  test "drag maps pointer back to offset":
    let track = ScrollbarTrack(x: 0, y: 0, w: 8, h: 100)
    let m = scrollMetrics(200, 100, 0)
    let drag = beginThumbDrag(track, m, pointerY = 0)
    check drag.active
    ## Dragging to the bottom of the travel yields the max offset.
    check offsetForDrag(drag, track, m, pointerY = 100) == 100
    check offsetForDrag(drag, track, m, pointerY = 0) == 0

  test "no scroll when content fits":
    let track = ScrollbarTrack(x: 0, y: 0, w: 8, h: 100)
    let m = scrollMetrics(50, 100, 0)
    check offsetForThumbTop(track, m, 40) == 0
