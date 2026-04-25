## Example usage of Terminal Theme.

import terminal_theme_lib

# Create default theme
let theme = defaultTheme()

# Get a basic ANSI color
let red = theme.getColor(1)
doAssert red.r == 205

# Override a color
theme.ansi[0] = rgb(10, 10, 10) # Dark gray instead of black
let darkBlack = theme.getColor(0)
doAssert darkBlack.r == 10

# Get an extended xterm color (not affected by theme overrides)
let cyan = theme.getColor(51)
doAssert cyan.r == 0
doAssert cyan.g == 255
doAssert cyan.b == 255

echo "All terminal-theme examples passed."
