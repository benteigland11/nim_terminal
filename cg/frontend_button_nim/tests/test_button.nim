import std/unittest
import button_lib

suite "button":
  test "pixel sizing honors padding and minimum":
    check buttonPixelWidth(8, 6, 10) == 6 * 8 + 20
    check buttonPixelWidth(8, 1, 4, minWidth = 100) == 100
    check buttonPixelHeight(16, 4) == 24

  test "hit testing":
    let r = buttonRect(10, 10, 40, 20)
    check pointInButton(r, 10, 10)
    check pointInButton(r, 49, 29)
    check not pointInButton(r, 50, 30)
    check not pointInButton(r, 5, 5)

  test "state machine precedence":
    check buttonState(enabled = false, pointerInside = true, pointerDown = true) == bsDisabled
    check buttonState(true, true, true) == bsPressed
    check buttonState(true, true, false) == bsHover
    check buttonState(true, false, false) == bsNormal

  test "state at pointer position":
    let r = buttonRect(0, 0, 20, 20)
    check buttonStateAt(r, 5, 5, pointerDown = true) == bsPressed
    check buttonStateAt(r, 100, 100, pointerDown = true) == bsNormal
    check buttonStateAt(r, 5, 5, pointerDown = false, enabled = false) == bsDisabled

  test "label centering":
    let r = buttonRect(0, 0, 100, 20)
    let (tx, ty) = centeredLabelOrigin(r, 8, 16, 4)
    check tx == (100 - 32) div 2
    check ty == (20 - 16) div 2

  test "interactive helper":
    check isInteractive(bsHover)
    check not isInteractive(bsDisabled)
