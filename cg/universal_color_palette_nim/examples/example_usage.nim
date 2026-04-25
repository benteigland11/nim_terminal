## Example usage of Color Palette.

import color_palette_lib

# Get RGB for an ANSI index
let red = getXterm256Color(1)
doAssert red.r == 0xcd

# Find nearest index for a custom RGB
let nearRed = findClosestXterm256(rgb(250, 10, 10))
doAssert nearRed == 9 # Bright Red

# Check luminance
let white = rgb(255, 255, 255)
doAssert white.isDark == false

echo "All color-palette examples passed."
