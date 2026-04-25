## Terminal theme representation.
##
## Defines a full color scheme for a terminal emulator, including
## background, foreground, cursor, and the 16 basic ANSI colors.

type
  RgbColor* = object
    r*, g*, b*: uint8

  TerminalTheme* = ref object
    background*: RgbColor
    foreground*: RgbColor
    cursor*: RgbColor
    selection*: RgbColor
    ansi*: array[16, RgbColor]

func rgb*(r, g, b: uint8): RgbColor = RgbColor(r: r, g: g, b: b)

# ---------------------------------------------------------------------------
# Default Theme (xterm-ish)
# ---------------------------------------------------------------------------

func defaultTheme*(): TerminalTheme =
  TerminalTheme(
    background: rgb(0, 0, 0),
    foreground: rgb(229, 229, 229),
    cursor:     rgb(255, 255, 255),
    selection:  rgb(173, 214, 255),
    ansi: [
      rgb(0, 0, 0),       # 0: Black
      rgb(205, 0, 0),     # 1: Red
      rgb(0, 205, 0),     # 2: Green
      rgb(205, 205, 0),   # 3: Yellow
      rgb(0, 0, 238),     # 4: Blue
      rgb(205, 0, 205),   # 5: Magenta
      rgb(0, 205, 205),   # 6: Cyan
      rgb(229, 229, 229), # 7: White
      rgb(127, 127, 127), # 8: Bright Black
      rgb(255, 0, 0),     # 9: Bright Red
      rgb(0, 255, 0),     # 10: Bright Green
      rgb(255, 255, 0),   # 11: Bright Yellow
      rgb(92, 92, 255),   # 12: Bright Blue
      rgb(255, 0, 255),   # 13: Bright Magenta
      rgb(0, 255, 255),   # 14: Bright Cyan
      rgb(255, 255, 255)  # 15: Bright White
    ]
  )

# ---------------------------------------------------------------------------
# Color Resolution
# ---------------------------------------------------------------------------

func getXterm256Color(index: uint8): RgbColor =
  if index >= 16 and index <= 231:
    let i = int(index - 16)
    let r = (i div 36) mod 6
    let g = (i div 6) mod 6
    let b = i mod 6
    let levels = [0'u8, 95, 135, 175, 215, 255]
    return rgb(levels[r], levels[g], levels[b])
  elif index >= 232:
    let i = int(index - 232)
    let v = uint8(8 + i * 10)
    return rgb(v, v, v)
  rgb(0, 0, 0)

func getColor*(theme: TerminalTheme, index: uint8): RgbColor =
  ## Get the RGB color for an index, using theme overrides for 0-15.
  if index < 16:
    return theme.ansi[index]
  return getXterm256Color(index)
