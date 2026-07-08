## Semantic color tokens for application chrome (panels, rails, overlays).
##
## Keeps a single source of truth for the surface palette so consumers stop
## sprinkling raw color literals across their renderer. Values are plain
## normalized RGBA (0.0 .. 1.0) so any backend can map them to its own color
## type. Every token has a sensible dark default and is fully overridable.

type
  ThemeColor* = object
    r*, g*, b*, a*: float

  ChromeTheme* = object
    background*: ThemeColor   ## Deepest app backdrop (behind everything).
    panel*: ThemeColor        ## Raised surfaces: dialogs, footers, bars.
    rail*: ThemeColor         ## Side rails / list backgrounds.
    surface*: ThemeColor      ## Inset content wells (code panes, fields).
    accent*: ThemeColor       ## Brand / highlight stroke.
    text*: ThemeColor         ## Primary foreground text.
    muted*: ThemeColor        ## Secondary / disabled text.
    border*: ThemeColor       ## Hairline separators and outlines.
    selection*: ThemeColor    ## Selected row / active item fill.
    overlayDim*: ThemeColor   ## Scrim drawn behind modal layers.

func themeColor*(r, g, b: float; a = 1.0): ThemeColor =
  ThemeColor(r: r, g: g, b: b, a: a)

func withAlpha*(color: ThemeColor; a: float): ThemeColor =
  ThemeColor(r: color.r, g: color.g, b: color.b, a: a)

func defaultDarkChromeTheme*(): ChromeTheme =
  ## Neutral dark palette with a warm accent. Matches a typical terminal-chrome
  ## look; override any field to rebrand.
  ChromeTheme(
    background: themeColor(0.05, 0.06, 0.08),
    panel: themeColor(0.10, 0.12, 0.16),
    rail: themeColor(0.08, 0.09, 0.11),
    surface: themeColor(0.08, 0.09, 0.11),
    accent: themeColor(0.95, 0.76, 0.23),
    text: themeColor(0.88, 0.91, 0.92),
    muted: themeColor(0.58, 0.63, 0.67),
    border: themeColor(0.24, 0.28, 0.32),
    selection: themeColor(0.16, 0.18, 0.22),
    overlayDim: themeColor(0.02, 0.03, 0.05, 0.72),
  )

func withAccent*(theme: ChromeTheme; accent: ThemeColor): ChromeTheme =
  result = theme
  result.accent = accent
