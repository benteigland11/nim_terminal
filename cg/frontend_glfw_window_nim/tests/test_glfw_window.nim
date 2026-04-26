import std/unittest
import ../src/glfw_window_lib

suite "GLFW window sizing":
  test "uses framebuffer when it is larger than window":
    let report = chooseDrawableSize(size2d(2400, 1600), size2d(1200, 800), size2d(0, 0))
    check report.chosen == size2d(2400, 1600)

  test "uses window size when framebuffer is stale":
    let report = chooseDrawableSize(size2d(1280, 720), size2d(1920, 1080), size2d(0, 0))
    check report.chosen == size2d(1920, 1080)

  test "uses fallback for missing dimensions":
    let report = chooseDrawableSize(size2d(0, 0), size2d(0, 0), size2d(640, 360))
    check report.chosen == size2d(640, 360)

  test "detects changed drawable size":
    let report = chooseDrawableSize(size2d(100, 80), size2d(100, 80), size2d(0, 0))
    check report.changedFrom(size2d(100, 80)) == false
    check report.changedFrom(size2d(80, 80)) == true

  test "formats diagnostics with stable keys":
    let report = chooseDrawableSize(size2d(1280, 720), size2d(1920, 1080), size2d(640, 360))
    check formatSizeDiagnostics(report) ==
      "fallback=640x360\nwindow=1920x1080\nframebuffer=1280x720\nchosen=1920x1080\n"
