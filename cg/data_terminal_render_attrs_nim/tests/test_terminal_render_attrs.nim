import std/unittest
import terminal_render_attrs_lib

const Ansi: array[16, RenderColor] = [
  rgb(0, 0, 0), rgb(200, 0, 0), rgb(0, 200, 0), rgb(200, 200, 0),
  rgb(0, 0, 200), rgb(200, 0, 200), rgb(0, 200, 200), rgb(220, 220, 220),
  rgb(120, 120, 120), rgb(255, 0, 0), rgb(0, 255, 0), rgb(255, 255, 0),
  rgb(80, 80, 255), rgb(255, 0, 255), rgb(0, 255, 255), rgb(255, 255, 255),
]

suite "Terminal Render Attributes":
  test "default colors resolve to caller defaults":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: defaultColor(), bg: defaultColor()),
      rgb(230, 230, 230),
      rgb(0, 0, 0),
      Ansi,
    )

    check resolved.foreground == rgb(230, 230, 230)
    check resolved.background == rgb(0, 0, 0)
    check not resolved.drawBackground

  test "indexed and rgb colors resolve":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(2), bg: rgbColor(10, 20, 30)),
      rgb(230, 230, 230),
      rgb(0, 0, 0),
      Ansi,
    )

    check resolved.foreground == rgb(0, 200, 0)
    check resolved.background == rgb(10, 20, 30)
    check resolved.drawBackground

  test "inverse swaps foreground and background":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(1), bg: defaultColor(), flags: {rfInverse}),
      rgb(230, 230, 230),
      rgb(1, 2, 3),
      Ansi,
    )

    check resolved.foreground == rgb(1, 2, 3)
    check resolved.background == rgb(200, 0, 0)
    check resolved.drawBackground

  test "hidden text resolves to effective background":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(1), bg: rgbColor(4, 5, 6), flags: {rfHidden}),
      rgb(230, 230, 230),
      rgb(0, 0, 0),
      Ansi,
    )

    check resolved.foreground == rgb(4, 5, 6)

  test "dim and decorations are exposed":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: rgbColor(100, 80, 60), flags: {rfDim, rfUnderline, rfStrike}),
      rgb(230, 230, 230),
      rgb(0, 0, 0),
      Ansi,
    )

    check resolved.foreground == rgb(55, 44, 33)
    check resolved.decorations == {rfUnderline, rfStrike}
