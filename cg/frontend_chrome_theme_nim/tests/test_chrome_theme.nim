import std/unittest
import chrome_theme_lib

suite "chrome theme":
  test "default dark theme populates all tokens":
    let theme = defaultDarkChromeTheme()
    check theme.accent.a == 1.0
    check theme.overlayDim.a < 1.0
    check theme.text.r > theme.muted.r

  test "withAlpha only changes alpha":
    let c = themeColor(0.2, 0.4, 0.6)
    let faded = c.withAlpha(0.5)
    check faded.r == c.r
    check faded.g == c.g
    check faded.b == c.b
    check faded.a == 0.5

  test "withAccent overrides accent token only":
    let theme = defaultDarkChromeTheme()
    let rebranded = theme.withAccent(themeColor(0.1, 0.5, 0.9))
    check rebranded.accent.b == 0.9
    check rebranded.panel == theme.panel
