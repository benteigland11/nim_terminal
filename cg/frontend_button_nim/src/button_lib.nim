## Push-button primitive: rectangle layout, hit testing, and a visual state
## machine.
##
## Pure logic — no rendering. The host measures a label, asks for the button
## rect, resolves the current visual state from pointer input, and draws it
## however it likes. Sizing is expressed in monospace cell units so the same
## helper works for any fixed-width chrome font.

type
  ButtonState* = enum
    bsDisabled   ## Not interactive.
    bsNormal     ## Idle.
    bsHover      ## Pointer over the button, not pressed.
    bsPressed    ## Pointer over the button and held down.

  ButtonRect* = object
    x*, y*, w*, h*: int

func buttonRect*(x, y, w, h: int): ButtonRect =
  ButtonRect(x: x, y: y, w: w, h: h)

func buttonPixelWidth*(cellWidth, labelLen, padX: int; minWidth = 0): int =
  ## Width needed for a `labelLen`-character label with `padX` on each side.
  max(minWidth, labelLen * max(0, cellWidth) + padX * 2)

func buttonPixelHeight*(cellHeight, padY: int): int =
  cellHeight + padY * 2

func pointInButton*(rect: ButtonRect; x, y: int): bool =
  rect.w > 0 and rect.h > 0 and
    x >= rect.x and x < rect.x + rect.w and
    y >= rect.y and y < rect.y + rect.h

func buttonState*(enabled, pointerInside, pointerDown: bool): ButtonState =
  ## Resolve visual state from interaction inputs. Disabled always wins.
  if not enabled:
    bsDisabled
  elif pointerInside and pointerDown:
    bsPressed
  elif pointerInside:
    bsHover
  else:
    bsNormal

func buttonStateAt*(
    rect: ButtonRect;
    pointerX, pointerY: int;
    pointerDown: bool;
    enabled = true): ButtonState =
  ## Convenience wrapper that hit-tests the pointer against `rect` first.
  buttonState(enabled, pointInButton(rect, pointerX, pointerY), pointerDown)

func centeredLabelOrigin*(
    rect: ButtonRect;
    cellWidth, cellHeight, labelLen: int): tuple[x, y: int] =
  ## Top-left origin that centers a `labelLen`-character label inside `rect`.
  let textW = labelLen * max(0, cellWidth)
  result.x = rect.x + max(0, (rect.w - textW) div 2)
  result.y = rect.y + max(0, (rect.h - cellHeight) div 2)

func isInteractive*(state: ButtonState): bool =
  state != bsDisabled
