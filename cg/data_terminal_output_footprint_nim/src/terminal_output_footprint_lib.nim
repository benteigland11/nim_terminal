## Tracks the lowest row touched by inline terminal UI output.
##
## Some terminal programs draw a multi-line interface in the primary screen,
## restore the cursor to the original command row, and then let the shell print
## the next prompt. This helper keeps that prompt from overwriting the drawn UI
## by computing a resume row below the touched footprint.

type
  ResumeAction* = object
    shouldMove*: bool
    targetRow*: int
    scrollCount*: int

  OutputFootprint* = object
    bottomRow: int
    armed: bool
    sawFullDisplayErase: bool

func newOutputFootprint*(): OutputFootprint =
  OutputFootprint(bottomRow: -1, armed: false, sawFullDisplayErase: false)

func bottomRow*(f: OutputFootprint): int = f.bottomRow

func isArmed*(f: OutputFootprint): bool = f.armed

func noResumeAction*(): ResumeAction =
  ResumeAction(shouldMove: false, targetRow: -1, scrollCount: 0)

proc reset*(f: var OutputFootprint) =
  f.bottomRow = -1
  f.armed = false
  f.sawFullDisplayErase = false

proc markFullDisplayErase*(f: var OutputFootprint, activeAlternate = false) =
  if activeAlternate: return
  f.sawFullDisplayErase = true

proc recordRow*(f: var OutputFootprint, row: int, activeAlternate = false) =
  if activeAlternate or row < 0: return
  f.bottomRow = max(f.bottomRow, row)

proc recordRows*(
    f: var OutputFootprint,
    firstRow, lastRow: int,
    activeAlternate = false
) =
  if activeAlternate: return
  f.recordRow(max(firstRow, lastRow))

proc armAfterCursorRestore*(
    f: var OutputFootprint,
    cursorRow: int,
    activeAlternate = false
) =
  if activeAlternate:
    f.armed = false
  else:
    f.armed = f.sawFullDisplayErase and f.bottomRow >= 0 and cursorRow < f.bottomRow

proc consumeResume*(
    f: var OutputFootprint,
    cursorRow, screenRows: int,
    activeAlternate = false,
    force = false
): ResumeAction =
  if activeAlternate or screenRows <= 0 or f.bottomRow < 0:
    return noResumeAction()
  if not f.armed and not force:
    return noResumeAction()

  let target = f.bottomRow + 1
  if target <= cursorRow:
    f.reset()
    return noResumeAction()

  result.shouldMove = true
  if target < screenRows:
    result.targetRow = target
    result.scrollCount = 0
  else:
    result.scrollCount = target - screenRows + 1
    result.targetRow = screenRows - 1
  f.reset()
