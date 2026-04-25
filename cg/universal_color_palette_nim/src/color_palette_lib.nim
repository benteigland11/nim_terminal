## Standard terminal color palettes.
##
## Provides the standard xterm-256 color table and utilities for
## converting between indexed colors and 24-bit RGB.
##
## This widget is pure logic/data and carries no I/O.

type
  RgbColor* = object
    r*, g*, b*: uint8

func rgb*(r, g, b: uint8): RgbColor = RgbColor(r: r, g: g, b: b)

# ---------------------------------------------------------------------------
# The xterm-256 Table
# ---------------------------------------------------------------------------

const
  AnsiBaseColors: array[16, RgbColor] = [
    rgb(0x00, 0x00, 0x00), # 0: Black
    rgb(0xcd, 0x00, 0x00), # 1: Red
    rgb(0x00, 0xcd, 0x00), # 2: Green
    rgb(0xcd, 0xcd, 0x00), # 3: Yellow
    rgb(0x00, 0x00, 0xee), # 4: Blue
    rgb(0xcd, 0x00, 0xcd), # 5: Magenta
    rgb(0x00, 0xcd, 0xcd), # 6: Cyan
    rgb(0xe5, 0xe5, 0xe5), # 7: White
    rgb(0x7f, 0x7f, 0x7f), # 8: Bright Black (Gray)
    rgb(0xff, 0x00, 0x00), # 9: Bright Red
    rgb(0x00, 0xff, 0x00), # 10: Bright Green
    rgb(0xff, 0xff, 0x00), # 11: Bright Yellow
    rgb(0x5c, 0x5c, 0xff), # 12: Bright Blue
    rgb(0xff, 0x00, 0xff), # 13: Bright Magenta
    rgb(0x00, 0xff, 0xff), # 14: Bright Cyan
    rgb(0xff, 0xff, 0xff)  # 15: Bright White
  ]

func getXterm256Color*(index: uint8): RgbColor =
  ## Map an index (0-255) to its standard xterm RGB value.
  if index < 16:
    return AnsiBaseColors[index]
  
  if index >= 16 and index <= 231:
    # 16-231: 6x6x6 color cube
    let i = int(index - 16)
    let r = (i div 36) mod 6
    let g = (i div 6) mod 6
    let b = i mod 6
    let levels = [0'u8, 95, 135, 175, 215, 255]
    return rgb(levels[r], levels[g], levels[b])
  
  if index >= 232:
    # 232-255: grayscale ramp
    let i = int(index - 232)
    let v = uint8(8 + i * 10)
    return rgb(v, v, v)
  
  return rgb(0, 0, 0)

# ---------------------------------------------------------------------------
# Quantization (RGB -> Index)
# ---------------------------------------------------------------------------

func distSq(c1, c2: RgbColor): int =
  let dr = int(c1.r) - int(c2.r)
  let dg = int(c1.g) - int(c2.g)
  let db = int(c1.b) - int(c2.b)
  (dr * dr) + (dg * dg) + (db * db)

func findClosestXterm256*(color: RgbColor): uint8 =
  ## Find the closest xterm-256 index for a given RGB color
  ## using simple Euclidean distance in RGB space.
  var bestIdx = 0'u8
  var minDist = int.high
  
  for i in 0 .. 255:
    let d = distSq(color, getXterm256Color(uint8(i)))
    if d < minDist:
      minDist = d
      bestIdx = uint8(i)
      if d == 0: break
      
  bestIdx

# ---------------------------------------------------------------------------
# Luminance / Contrast
# ---------------------------------------------------------------------------

func luminance*(c: RgbColor): float =
  ## Calculate relative luminance per W3C (0.0 to 1.0).
  0.2126 * (float(c.r) / 255.0) +
  0.7152 * (float(c.g) / 255.0) +
  0.0722 * (float(c.b) / 255.0)

func isDark*(c: RgbColor): bool = c.luminance < 0.5
