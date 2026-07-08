## Example usage of Chrome Theme.

import chrome_theme_lib

let theme = defaultDarkChromeTheme()
# Map a semantic token to whatever the render backend expects.
let panel = theme.panel
assert panel.a == 1.0

# Rebrand by overriding just the accent.
let branded = theme.withAccent(themeColor(0.2, 0.6, 1.0))
assert branded.accent.b == 1.0
assert branded.border == theme.border
