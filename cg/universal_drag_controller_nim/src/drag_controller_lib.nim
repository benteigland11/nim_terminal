## Grid-based drag interaction state machine.
##
## Tracks mouse button state and movement to manage drag operations
## (like text selection). Provides "Auto-scroll" signaling when the
## mouse is dragged outside the viewport bounds.
##
## This widget is pure logic and does not depend on any specific
## UI framework.

type
  DragState* = enum
    dsIdle
    dsActive
    dsOutsideTop     ## Mouse is above the viewport while dragging
    dsOutsideBottom  ## Mouse is below the viewport while dragging

  DragController* = object
    state*: DragState
    startX*, startY*: int  ## Initial grid coordinates
    currX*, currY*: int    ## Current grid coordinates
    height*: int           ## Viewport height in rows

func newDragController*(viewportHeight: int): DragController =
  DragController(
    state: dsIdle,
    startX: 0, startY: 0,
    currX: 0, currY: 0,
    height: viewportHeight
  )

func update*(c: var DragController, row, col: int, isDown: bool) =
  ## Update the state machine with new mouse coordinates.
  if not isDown:
    c.state = dsIdle
    return

  if c.state == dsIdle:
    # Start a new drag
    c.state = dsActive
    c.startX = col
    c.startY = row
  
  # Update current position
  c.currX = col
  c.currY = row
  
  # Detect auto-scroll signaling
  if row < 0:
    c.state = dsOutsideTop
  elif row >= c.height:
    c.state = dsOutsideBottom
  else:
    c.state = dsActive

func row*(c: DragController): int = c.currY
func col*(c: DragController): int = c.currX
