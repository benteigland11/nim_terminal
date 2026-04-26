## Terminal render-attribute resolver.
##
## Converts terminal cell attributes into concrete foreground/background colors
## and decoration flags for a renderer. The widget is deliberately renderer
## agnostic: callers decide how to draw resolved colors, cursor shapes, and
## decorations.

type
  RenderColor* = object
    r*, g*, b*: uint8

  TerminalColorKind* = enum
    tckDefault
    tckIndexed
    tckRgb

  TerminalColor* = object
    case kind*: TerminalColorKind
    of tckDefault:
      discard
    of tckIndexed:
      index*: int
    of tckRgb:
      r*, g*, b*: uint8

  RenderFlag* = enum
    rfBold
    rfDim
    rfItalic
    rfUnderline
    rfStrike
    rfInverse
    rfHidden
    rfOverline

  RenderAttrs* = object
    fg*, bg*: TerminalColor
    flags*: set[RenderFlag]

  ResolvedRenderAttrs* = object
    foreground*: RenderColor
    background*: RenderColor
    drawBackground*: bool
    decorations*: set[RenderFlag]

func rgb*(r, g, b: uint8): RenderColor =
  RenderColor(r: r, g: g, b: b)

func defaultColor*(): TerminalColor =
  TerminalColor(kind: tckDefault)

func indexedColor*(index: int): TerminalColor =
  TerminalColor(kind: tckIndexed, index: index)

func rgbColor*(r, g, b: uint8): TerminalColor =
  TerminalColor(kind: tckRgb, r: r, g: g, b: b)

func xterm256Color*(index: uint8): RenderColor =
  if index < 16:
    const base = [
      rgb(0x00, 0x00, 0x00), rgb(0xcd, 0x00, 0x00),
      rgb(0x00, 0xcd, 0x00), rgb(0xcd, 0xcd, 0x00),
      rgb(0x00, 0x00, 0xee), rgb(0xcd, 0x00, 0xcd),
      rgb(0x00, 0xcd, 0xcd), rgb(0xe5, 0xe5, 0xe5),
      rgb(0x7f, 0x7f, 0x7f), rgb(0xff, 0x00, 0x00),
      rgb(0x00, 0xff, 0x00), rgb(0xff, 0xff, 0x00),
      rgb(0x5c, 0x5c, 0xff), rgb(0xff, 0x00, 0xff),
      rgb(0x00, 0xff, 0xff), rgb(0xff, 0xff, 0xff),
    ]
    return base[index]
  if index <= 231:
    let i = int(index - 16)
    let levels = [0'u8, 95, 135, 175, 215, 255]
    return rgb(levels[(i div 36) mod 6], levels[(i div 6) mod 6], levels[i mod 6])
  let gray = uint8(8 + int(index - 232) * 10)
  rgb(gray, gray, gray)

func resolveColor*(color: TerminalColor, default: RenderColor, ansi: array[16, RenderColor]): RenderColor =
  case color.kind
  of tckDefault:
    default
  of tckIndexed:
    if color.index >= 0 and color.index < 16:
      ansi[color.index]
    else:
      xterm256Color(uint8(max(0, min(255, color.index))))
  of tckRgb:
    rgb(color.r, color.g, color.b)

func dim*(color: RenderColor, factor = 0.55): RenderColor =
  rgb(
    uint8(max(0, min(255, int(float(color.r) * factor)))),
    uint8(max(0, min(255, int(float(color.g) * factor)))),
    uint8(max(0, min(255, int(float(color.b) * factor)))),
  )

func resolveRenderAttrs*(
    attrs: RenderAttrs,
    defaultForeground, defaultBackground: RenderColor,
    ansi: array[16, RenderColor],
): ResolvedRenderAttrs =
  let rawForeground = resolveColor(attrs.fg, defaultForeground, ansi)
  let rawBackground = resolveColor(attrs.bg, defaultBackground, ansi)

  var foreground =
    if rfHidden in attrs.flags:
      if rfInverse in attrs.flags: rawForeground else: rawBackground
    elif rfInverse in attrs.flags:
      rawBackground
    else:
      rawForeground
  if rfDim in attrs.flags:
    foreground = foreground.dim()

  let background =
    if rfInverse in attrs.flags:
      rawForeground
    else:
      rawBackground

  ResolvedRenderAttrs(
    foreground: foreground,
    background: background,
    drawBackground: attrs.bg.kind != tckDefault or rfInverse in attrs.flags,
    decorations: attrs.flags * {rfUnderline, rfStrike, rfOverline},
  )
