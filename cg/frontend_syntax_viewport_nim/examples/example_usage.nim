## Example usage of Syntax Viewport.

import syntax_viewport_lib

let source = "let x = 1\n# comment"
let spans = @[
  (0, 3, tvKeyword),
  (7, 8, tvNumber),
  (10, 18, tvComment),
]
let viewport = buildSourceViewport(source, spans, cols = 20, maxRows = 4, scrollRow = 0)
assert viewport.lines.len > 0
assert viewport.totalLines >= 2
