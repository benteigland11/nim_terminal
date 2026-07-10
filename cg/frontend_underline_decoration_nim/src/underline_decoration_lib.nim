## Pixel-segment layouts for terminal-style text underlines.
##
## Given a cell rectangle and an underline kind (single, double, curly, dotted,
## dashed), returns axis-aligned segments a renderer can fill. No color, no
## GPU, no font metrics beyond the cell box the caller provides.

type
  UnderlineKind* = enum
    ukNone
    ukSingle
    ukDouble
    ukCurly
    ukDotted
    ukDashed

  PixelSeg* = object
    x*, y*, w*, h*: int

func underlineThickness*(cellH: int): int =
  max(1, cellH div 14)

func underlineBaselineY*(cellY, cellH, thickness: int): int =
  ## Bottom-aligned baseline for underlines (inside the cell).
  cellY + cellH - max(1, thickness) - max(0, cellH div 16)

func underlineSegments*(
    kind: UnderlineKind;
    cellX, cellY, cellW, cellH: int;
    thickness = 0,
): seq[PixelSeg] =
  ## Layout underline segments covering `cellW x cellH` at origin `(cellX, cellY)`.
  ## Returns an empty seq for `ukNone` or non-positive geometry.
  result = @[]
  if kind == ukNone or cellW <= 0 or cellH <= 0:
    return
  let th = if thickness > 0: thickness else: underlineThickness(cellH)
  let baseY = underlineBaselineY(cellY, cellH, th)

  case kind
  of ukNone:
    discard
  of ukSingle:
    result.add PixelSeg(x: cellX, y: baseY, w: cellW, h: th)
  of ukDouble:
    let gap = max(th + 1, cellH div 10)
    result.add PixelSeg(x: cellX, y: baseY - gap, w: cellW, h: th)
    result.add PixelSeg(x: cellX, y: baseY, w: cellW, h: th)
  of ukDotted:
    ## Dot / gap ~ equal width, at least 1px.
    let dot = max(1, min(th * 2, cellW))
    let gap = max(1, dot)
    var x = cellX
    while x < cellX + cellW:
      let w = min(dot, cellX + cellW - x)
      if w > 0:
        result.add PixelSeg(x: x, y: baseY, w: w, h: th)
      x += dot + gap
  of ukDashed:
    let dash = max(2, cellW div 3)
    let gap = max(1, dash div 2)
    var x = cellX
    while x < cellX + cellW:
      let w = min(dash, cellX + cellW - x)
      if w > 0:
        result.add PixelSeg(x: x, y: baseY, w: w, h: th)
      x += dash + gap
  of ukCurly:
    ## Approximate a wave with short horizontal steps at two heights.
    let amp = max(1, th)
    let step = max(2, min(cellW, max(2, cellW div 4)))
    var x = cellX
    var phase = 0
    while x < cellX + cellW:
      let w = min(step, cellX + cellW - x)
      let y =
        if phase mod 2 == 0: baseY - amp
        else: baseY
      if w > 0:
        result.add PixelSeg(x: x, y: y, w: w, h: th)
      x += step
      inc phase
