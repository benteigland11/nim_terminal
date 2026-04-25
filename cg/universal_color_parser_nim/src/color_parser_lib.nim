## Terminal color specification parser.
##
## Parses X11/xterm color strings like:
##   * #RGB
##   * #RRGGBB
##   * #RRRGGGBBB
##   * #RRRRGGGGBBBB
##   * rgb:RR/GG/BB
##   * rgb:RRRR/GGGG/BBBB

import std/[strutils, options]

type
  RgbColor* = object
    r*, g*, b*: uint8

func rgb*(r, g, b: uint8): RgbColor = RgbColor(r: r, g: g, b: b)

func hexToByte(h: string): uint8 =
  if h.len == 0: return 0
  if h.len == 1:
    let v = parseHexInt(h)
    return uint8(v or (v shl 4))
  if h.len == 2:
    return uint8(parseHexInt(h))
  # For 3 or 4 digits, we take the most significant 2.
  return uint8(parseHexInt(h[0..1]))

func parseColor*(spec: string): Option[RgbColor] =
  ## Parse a color specification string. Returns none() if malformed.
  let s = spec.strip()
  if s.len == 0: return none(RgbColor)
  
  try:
    if s.startsWith("#"):
      let hex = s[1..^1]
      case hex.len
      of 3:
        return some(rgb(hexToByte(hex[0..0]), hexToByte(hex[1..1]), hexToByte(hex[2..2])))
      of 6:
        return some(rgb(hexToByte(hex[0..1]), hexToByte(hex[2..3]), hexToByte(hex[4..5])))
      of 9:
        return some(rgb(hexToByte(hex[0..2]), hexToByte(hex[3..5]), hexToByte(hex[6..8])))
      of 12:
        return some(rgb(hexToByte(hex[0..3]), hexToByte(hex[4..7]), hexToByte(hex[8..11])))
      else:
        return none(RgbColor)
    
    if s.startsWith("rgb:"):
      let parts = s[4..^1].split('/')
      if parts.len == 3:
        return some(rgb(hexToByte(parts[0]), hexToByte(parts[1]), hexToByte(parts[2])))
  except:
    discard
    
  none(RgbColor)
