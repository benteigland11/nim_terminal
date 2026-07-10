import std/unittest
import ../src/underline_decoration_lib

suite "underline decoration segments":
  test "none and invalid geometry yield no segments":
    check underlineSegments(ukNone, 0, 0, 10, 16).len == 0
    check underlineSegments(ukSingle, 0, 0, 0, 16).len == 0
    check underlineSegments(ukSingle, 0, 0, 10, 0).len == 0

  test "single is one bottom-aligned bar":
    let segs = underlineSegments(ukSingle, 4, 10, 12, 16, thickness = 2)
    check segs.len == 1
    check segs[0].x == 4
    check segs[0].w == 12
    check segs[0].h == 2
    check segs[0].y == underlineBaselineY(10, 16, 2)

  test "double emits two parallel bars":
    let segs = underlineSegments(ukDouble, 0, 0, 20, 20, thickness = 1)
    check segs.len == 2
    check segs[0].y < segs[1].y
    check segs[0].w == 20 and segs[1].w == 20

  test "dotted leaves gaps across the cell":
    let segs = underlineSegments(ukDotted, 0, 0, 16, 14, thickness = 1)
    check segs.len >= 2
    for s in segs:
      check s.w >= 1
      check s.h == 1

  test "dashed uses longer runs than dotted for the same cell":
    let dotted = underlineSegments(ukDotted, 0, 0, 24, 16, thickness = 1)
    let dashed = underlineSegments(ukDashed, 0, 0, 24, 16, thickness = 1)
    check dashed.len >= 1
    check dashed[0].w >= dotted[0].w

  test "curly alternates vertical phases":
    let segs = underlineSegments(ukCurly, 0, 0, 20, 16, thickness = 1)
    check segs.len >= 2
    var sawHigh = false
    var sawLow = false
    let base = segs[0].y
    for s in segs:
      if s.y < base: sawHigh = true
      if s.y > base: sawLow = true
      if s.y != base: sawHigh = true  # either phase differs
    ## At least two distinct y values for a wave.
    var ys: seq[int] = @[]
    for s in segs:
      if s.y notin ys: ys.add s.y
    check ys.len >= 2
