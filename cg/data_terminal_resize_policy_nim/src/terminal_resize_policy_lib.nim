## Terminal grid resize policy for multi-pane hosts.
##
## Pure logic for:
##   * skipping no-op size applications (same cols/rows)
##   * holding the last good PTY size when a pane shrinks below a TUI floor
##   * rate-limiting how often SIGWINCH-style size changes may apply
##
## Drawing and PTY I/O stay with the host.

type
  GridSize* = object
    cols*, rows*: int

  ResizePlan* = object
    cols*, rows*: int
    apply*: bool       ## true when the PTY/buffer size should change
    undersized*: bool  ## desired pixel grid is below the TUI floor
    heldLastGood*: bool ## applying/holding prior size because pane is too small

  ResizeRateLimit* = object
    lastApplyAt*: float
    minIntervalSec*: float
    pending*: bool
    pendingSize*: GridSize

const
  DefaultMinIntervalSec* = 0.05
  DefaultMinCols* = 40
  DefaultMinRows* = 8

func gridSize*(cols, rows: int): GridSize =
  GridSize(cols: max(1, cols), rows: max(1, rows))

func `==`*(a, b: GridSize): bool =
  a.cols == b.cols and a.rows == b.rows

func newResizeRateLimit*(minIntervalSec = DefaultMinIntervalSec): ResizeRateLimit =
  ResizeRateLimit(
    lastApplyAt: -1.0e9,
    minIntervalSec: max(0.0, minIntervalSec),
    pending: false,
    pendingSize: gridSize(1, 1),
  )

func planTerminalResize*(
    desiredCols, desiredRows: int;
    currentCols, currentRows: int;
    minCols = DefaultMinCols;
    minRows = DefaultMinRows;
): ResizePlan =
  ## Decide the PTY/grid size for one pane.
  ##
  ## When the pixel-derived size is below the floor and the current size is
  ## still healthy, hold the current size so agent TUIs are not SIGWINCH'd into
  ## a 5x3 death spiral mid-drag. When there is no healthy current size, clamp
  ## up to the floor so the child at least starts with a usable grid.
  let desired = gridSize(desiredCols, desiredRows)
  let current = gridSize(currentCols, currentRows)
  let minC = max(1, minCols)
  let minR = max(1, minRows)
  let desiredOk = desired.cols >= minC and desired.rows >= minR
  let currentOk = current.cols >= minC and current.rows >= minR

  if desiredOk:
    result.cols = desired.cols
    result.rows = desired.rows
    result.undersized = false
    result.heldLastGood = false
  elif currentOk:
    result.cols = current.cols
    result.rows = current.rows
    result.undersized = true
    result.heldLastGood = true
  else:
    result.cols = max(desired.cols, minC)
    result.rows = max(desired.rows, minR)
    result.undersized = true
    result.heldLastGood = false

  result.apply = result.cols != current.cols or result.rows != current.rows

proc noteResizeActivity*(limit: var ResizeRateLimit) =
  ## Mark that layout/window geometry changed and a resize pass is needed.
  limit.pending = true

proc noteDesiredSize*(limit: var ResizeRateLimit; cols, rows: int) =
  limit.pending = true
  limit.pendingSize = gridSize(cols, rows)

func canApplyNow*(limit: ResizeRateLimit; now: float): bool =
  ## True when the rate limiter allows a PTY size application.
  now - limit.lastApplyAt >= limit.minIntervalSec

proc markApplied*(limit: var ResizeRateLimit; now: float) =
  limit.lastApplyAt = now
  limit.pending = false

func shouldRunResizePass*(limit: ResizeRateLimit): bool =
  limit.pending

proc takePending*(limit: var ResizeRateLimit): bool =
  ## Consume the pending flag; returns whether a pass was pending.
  result = limit.pending
  limit.pending = false

func planWithRateLimit*(
    limit: ResizeRateLimit;
    now: float;
    desiredCols, desiredRows, currentCols, currentRows: int;
    minCols = DefaultMinCols;
    minRows = DefaultMinRows;
): ResizePlan =
  ## Like planTerminalResize, but suppresses `apply` when rate-limited.
  result = planTerminalResize(
    desiredCols, desiredRows, currentCols, currentRows, minCols, minRows)
  if result.apply and not limit.canApplyNow(now):
    result.apply = false
