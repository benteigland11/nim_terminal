## Resolve terminal cell attributes into renderer-ready values.

import terminal_render_attrs_lib

const Ansi: array[16, RenderColor] = [
  rgb(0, 0, 0), rgb(200, 0, 0), rgb(0, 200, 0), rgb(200, 200, 0),
  rgb(0, 0, 200), rgb(200, 0, 200), rgb(0, 200, 200), rgb(220, 220, 220),
  rgb(120, 120, 120), rgb(255, 0, 0), rgb(0, 255, 0), rgb(255, 255, 0),
  rgb(80, 80, 255), rgb(255, 0, 255), rgb(0, 255, 255), rgb(255, 255, 255),
]

let attrs = RenderAttrs(
  fg: indexedColor(2),
  bg: defaultColor(),
  flags: {rfInverse, rfUnderline},
)
let resolved = resolveRenderAttrs(attrs, rgb(230, 230, 230), rgb(0, 0, 0), Ansi)

doAssert resolved.drawBackground
doAssert rfUnderline in resolved.decorations
