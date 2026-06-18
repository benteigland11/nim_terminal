import std/options
import cursor_row_highlight_lib

let style = defaultCursorRowHighlightStyle()
let rect = cursorRowHighlightRect(1, 4, 20, PixelRect(x: 0, y: 0, w: 640, h: 80), style = style)

doAssert rect.isSome
doAssert rect.get() == PixelRect(x: 0, y: 20, w: 640, h: 20)
doAssert style.color == highlightColor(54, 54, 56)

let composerRows = ["› Draft a response", "", "  gpt-5.5 medium · ~/example"]
let composer = codexComposerHighlightRect(composerRows, 0, 20, PixelRect(x: 0, y: 0, w: 640, h: 80))

doAssert composer.isSome
doAssert composer.get() == PixelRect(x: 0, y: 0, w: 640, h: 40)
