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
      rgb(245, 246, 248),
      rgb(5, 6, 7),
      Ansi,
    )

    check resolved.foreground == rgb(245, 246, 248)
    check resolved.background == rgb(5, 6, 7)
    check not resolved.drawBackground

  test "indexed and rgb colors resolve":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(2), bg: rgbColor(10, 20, 30)),
      rgb(245, 246, 248),
      rgb(0, 0, 0),
      Ansi,
    )

    check resolved.foreground == rgb(0, 200, 0)
    check resolved.background == rgb(10, 20, 30)
    check resolved.drawBackground

  test "inverse swaps foreground and background":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(1), bg: defaultColor(), flags: {rfInverse}),
      rgb(245, 246, 248),
      rgb(1, 2, 3),
      Ansi,
    )

    check resolved.foreground == rgb(1, 2, 3)
    check resolved.background == rgb(200, 0, 0)
    check resolved.drawBackground

  test "hidden text resolves to effective background":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(1), bg: rgbColor(4, 5, 6), flags: {rfHidden}),
      rgb(245, 246, 248),
      rgb(0, 0, 0),
      Ansi,
    )

    check resolved.foreground == rgb(4, 5, 6)

  test "dim is mild and decorations are exposed":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: rgbColor(200, 200, 200), flags: {rfDim, rfUnderline, rfStrike}),
      rgb(245, 246, 248),
      rgb(5, 6, 7),
      Ansi,
      liftNearGray = false,
    )

    ## Default dim factor 0.82: 200*0.82 = 164
    check resolved.foreground == rgb(164, 164, 164)
    check resolved.decorations == {rfUnderline, rfStrike}

  test "bold maps indexed 0-7 to bright half":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(1), flags: {rfBold}),
      rgb(245, 246, 248),
      rgb(0, 0, 0),
      Ansi,
    )
    check resolved.foreground == rgb(255, 0, 0)
    check rfBold in resolved.decorations

  test "bold brightens default without bold-as-bright index":
    let defaultBold = resolveRenderAttrs(
      RenderAttrs(fg: defaultColor(), flags: {rfBold}),
      rgb(200, 200, 200),
      rgb(0, 0, 0),
      Ansi,
      liftNearGray = false,
    )
    ## brighten(200, 0.28) → 200 + 55*0.28 = 215.4 → 215
    check defaultBold.foreground == rgb(215, 215, 215)

  test "near-gray body ink is lifted on dark backgrounds":
    ## Agent markdown body often ships as muddy mid-gray truecolor.
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: rgbColor(120, 120, 120)),
      rgb(245, 246, 248),
      rgb(5, 6, 7),
      Ansi,
    )
    check relativeLuma(resolved.foreground) >= 0.80
    check resolved.foreground.r >= 200

  test "saturated heading colors are not washed out by lift":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: rgbColor(80, 140, 255)),
      rgb(245, 246, 248),
      rgb(5, 6, 7),
      Ansi,
    )
    check resolved.foreground == rgb(80, 140, 255)

  test "dim wins intensity after bold-as-bright remap":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(7), flags: {rfBold, rfDim}),
      rgb(245, 246, 248),
      rgb(0, 0, 0),
      Ansi,
      liftNearGray = false,
    )
    ## bold maps 7→15 (255), then dim 0.82 → 209
    check resolved.foreground == rgb(209, 209, 209)

  test "boldAsBright can be disabled":
    let resolved = resolveRenderAttrs(
      RenderAttrs(fg: indexedColor(1), flags: {rfBold}),
      rgb(245, 246, 248),
      rgb(0, 0, 0),
      Ansi,
      boldAsBright = false,
      liftNearGray = false,
    )
    ## brighten red(200,0,0) by 0.28 → (215, 71, 71)
    check resolved.foreground == rgb(215, 71, 71)
