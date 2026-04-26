## GLFW window sizing helpers.
##
## Reconciles framebuffer, window, and callback-reported sizes into a drawable
## size suitable for OpenGL viewports and app layout.

type
  Size2D* = object
    width*: int
    height*: int

  WindowSizeReport* = object
    framebuffer*: Size2D
    window*: Size2D
    fallback*: Size2D
    chosen*: Size2D

func size2d*(width, height: int): Size2D =
  Size2D(width: width, height: height)

func isPositive*(size: Size2D): bool =
  size.width > 0 and size.height > 0

func chooseDrawableSize*(framebuffer, window, fallback: Size2D): WindowSizeReport =
  ## Select a drawable size from available GLFW measurements.
  ##
  ## Normal high-DPI platforms report framebuffer >= window size. Some
  ## translated environments report a stale framebuffer while window size
  ## changes, so the larger positive dimension is chosen independently.
  let width = max(max(framebuffer.width, window.width), fallback.width)
  let height = max(max(framebuffer.height, window.height), fallback.height)
  WindowSizeReport(
    framebuffer: framebuffer,
    window: window,
    fallback: fallback,
    chosen: size2d(width, height),
  )

func changedFrom*(report: WindowSizeReport, current: Size2D): bool =
  report.chosen.width != current.width or report.chosen.height != current.height

func formatSizeDiagnostics*(report: WindowSizeReport): string =
  "fallback=" & $report.fallback.width & "x" & $report.fallback.height & "\n" &
  "window=" & $report.window.width & "x" & $report.window.height & "\n" &
  "framebuffer=" & $report.framebuffer.width & "x" & $report.framebuffer.height & "\n" &
  "chosen=" & $report.chosen.width & "x" & $report.chosen.height & "\n"
