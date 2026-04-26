import std/strutils
import glfw_window_lib

let report = chooseDrawableSize(
  framebuffer = size2d(1280, 720),
  window = size2d(1920, 1080),
  fallback = size2d(640, 360),
)

doAssert report.chosen == size2d(1920, 1080)
doAssert formatSizeDiagnostics(report).startsWith("fallback=640x360")
