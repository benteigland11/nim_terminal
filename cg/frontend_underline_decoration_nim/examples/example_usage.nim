import underline_decoration_lib

## Layout a curly underline under a 10x16 cell — a renderer would fill each seg.

let segs = underlineSegments(ukCurly, cellX = 0, cellY = 0, cellW = 10, cellH = 16)
doAssert segs.len >= 2
doAssert segs[0].w > 0

let single = underlineSegments(ukSingle, 0, 0, 10, 16)
doAssert single.len == 1

echo "underline-decoration example ok"
