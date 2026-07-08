## Example usage of Button.

import button_lib

# Lay out a button sized to its label.
let label = "Inspect"
let cellWidth = 8
let cellHeight = 16
let btn = buttonRect(20, 100, buttonPixelWidth(cellWidth, label.len, padX = 10),
                     buttonPixelHeight(cellHeight, padY = 4))

# Resolve visual state from a pointer at (25, 105) pressing the button.
let state = buttonStateAt(btn, 25, 105, pointerDown = true)
assert state == bsPressed

# Where to draw the centered label.
let (tx, ty) = centeredLabelOrigin(btn, cellWidth, cellHeight, label.len)
assert tx >= btn.x
assert ty >= btn.y
