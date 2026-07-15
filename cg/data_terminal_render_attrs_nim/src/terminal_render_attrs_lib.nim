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
      index*: uint8
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
  TerminalColor(kind: tckIndexed, index: uint8(index))

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
    if color.index < 16:
      ansi[color.index]
    else:
      xterm256Color(color.index)
  of tckRgb:
    rgb(color.r, color.g, color.b)

func dim*(color: RenderColor, factor = 0.82): RenderColor =
  ## Soft intensity reduction for SGR dim. Kept mild so secondary body copy
  ## stays bright enough on near-black agent TUI backgrounds.
  rgb(
    uint8(max(0, min(255, int(float(color.r) * factor)))),
    uint8(max(0, min(255, int(float(color.g) * factor)))),
    uint8(max(0, min(255, int(float(color.b) * factor)))),
  )

func brighten*(color: RenderColor, amount = 0.28): RenderColor =
  ## Blend toward white. Used when bold cannot map through the bright ANSI half.
  rgb(
    uint8(max(0, min(255, int(float(color.r) + (255.0 - float(color.r)) * amount)))),
    uint8(max(0, min(255, int(float(color.g) + (255.0 - float(color.g)) * amount)))),
    uint8(max(0, min(255, int(float(color.b) + (255.0 - float(color.b)) * amount)))),
  )

func relativeLuma*(color: RenderColor): float =
  ## Rec. 709 relative luminance in 0..1.
  (0.2126 * float(color.r) + 0.7152 * float(color.g) + 0.0722 * float(color.b)) / 255.0

func isNearGray*(color: RenderColor, channelTolerance = 30): bool =
  ## True when RGB channels are close — body/secondary ink, not headings/links.
  let lo = min(color.r, min(color.g, color.b)).int
  let hi = max(color.r, max(color.g, color.b)).int
  hi - lo <= channelTolerance

func liftNearGrayOnDark*(
    foreground, background: RenderColor,
    minLuma = 0.82,
    channelTolerance = 30,
): RenderColor =
  ## Dark-theme readability: muddy mid-grays (common for markdown body in
  ## agent harnesses) are lifted toward white. Saturated colors (blue heads,
  ## cyan code) are left alone so chrome stays vivid.
  ##
  ## Only runs on neutral dark backgrounds — colored / inverse cells keep the
  ## app's exact palette so SGR reverse video and chip backgrounds stay correct.
  if relativeLuma(background) > 0.45:
    return foreground
  if not isNearGray(background, channelTolerance + 20):
    return foreground
  if not isNearGray(foreground, channelTolerance):
    return foreground
  let luma = relativeLuma(foreground)
  if luma >= minLuma:
    return foreground
  let denom = max(1e-6, 1.0 - luma)
  let amount = min(1.0, (minLuma - luma) / denom)
  brighten(foreground, amount)

func resolveRenderAttrs*(
    attrs: RenderAttrs,
    defaultForeground, defaultBackground: RenderColor,
    ansi: array[16, RenderColor],
    boldAsBright = true,
    boldBrightenAmount = 0.28,
    dimFactor = 0.82,
    liftNearGray = true,
    nearGrayMinLuma = 0.82,
): ResolvedRenderAttrs =
  ## Resolve cell attributes to concrete colors.
  ##
  ## Bold handling (classic terminal expectation):
  ## - Indexed colors 0..7 with bold → bright half 8..15 when `boldAsBright`.
  ## - Default / RGB / already-bright colors get a mild luminance boost so SGR 1
  ##   is visible without a second font weight.
  ## - Dim reduces intensity; when both bold and dim are set, dim wins after
  ##   any bold-as-bright palette remap.
  ## - Near-gray ink on dark backgrounds is lifted so agent markdown body copy
  ##   does not sit at unreadable mid-gray (pass `liftNearGray = false` to opt out).
  var fgSource = attrs.fg
  var boldMappedToBright = false
  if boldAsBright and rfBold in attrs.flags and fgSource.kind == tckIndexed and
      fgSource.index <= 7:
    fgSource = indexedColor(int(fgSource.index) + 8)
    boldMappedToBright = true

  let rawForeground = resolveColor(fgSource, defaultForeground, ansi)
  let rawBackground = resolveColor(attrs.bg, defaultBackground, ansi)

  var foreground =
    if rfHidden in attrs.flags:
      if rfInverse in attrs.flags: rawForeground else: rawBackground
    elif rfInverse in attrs.flags:
      rawBackground
    else:
      rawForeground

  if rfDim in attrs.flags:
    foreground = foreground.dim(dimFactor)
  elif rfBold in attrs.flags and not boldMappedToBright:
    foreground = foreground.brighten(boldBrightenAmount)

  let background =
    if rfInverse in attrs.flags:
      rawForeground
    else:
      rawBackground

  if liftNearGray and rfHidden notin attrs.flags and rfInverse notin attrs.flags:
    foreground = liftNearGrayOnDark(foreground, background, nearGrayMinLuma)

  # Bold stays in decorations so hosts can faux-bold / pick a bold face even
  # when intensity was already remapped via bold-as-bright.
  ResolvedRenderAttrs(
    foreground: foreground,
    background: background,
    drawBackground: attrs.bg.kind != tckDefault or rfInverse in attrs.flags,
    decorations: attrs.flags * {rfUnderline, rfStrike, rfOverline, rfBold},
  )
