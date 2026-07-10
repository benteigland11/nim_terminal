import std/unittest
import ../src/terminal_progress_lib

suite "OSC 9;4 progress state":
  test "parse normal determinate progress":
    let p = parseOsc9ProgressBody("4;1;42")
    check p.ok
    check p.state == 1
    check p.percent == 42

  test "parse indeterminate without percent":
    let p = parseOsc9ProgressBody("4;3")
    check p.ok
    check p.state == 3
    check p.percent == 0

  test "parse clear":
    let p = parseOsc9ProgressBody("4;0")
    check p.ok
    check p.state == 0

  test "reject non-progress OSC 9 bodies":
    check not parseOsc9ProgressBody("notify;hello").ok
    check not parseOsc9ProgressBody("").ok
    check not parseOsc9ProgressBody("4").ok

  test "apply clamps percent and tracks visibility":
    var bar = newTerminalProgress()
    check not bar.isVisible
    check bar.applyProgress(1, 150)
    check bar.isVisible
    check bar.percent == 100
    let snap = bar.snapshot()
    check snap.visible
    check snap.fraction == 1.0
    check snap.state == pbsNormal

  test "indeterminate is visible with zero fraction":
    var bar = newTerminalProgress()
    check bar.applyProgress(3, 99)
    check bar.isVisible
    check bar.percent == 0
    check bar.snapshot().fraction == 0.0
    check bar.snapshot().state == pbsIndeterminate

  test "clear hides progress":
    var bar = newTerminalProgress()
    discard bar.applyProgress(1, 25)
    check bar.clearProgress()
    check not bar.isVisible
    check bar.snapshot().visible == false

  test "redundant apply is a no-op":
    var bar = newTerminalProgress()
    check bar.applyProgress(1, 10)
    check not bar.applyProgress(1, 10)
