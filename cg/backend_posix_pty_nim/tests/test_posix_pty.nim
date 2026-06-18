import std/[envvars, unittest]
import ../src/posix_pty_lib

suite "POSIX PTY launch environment":
  test "default launch environment is terminal-friendly":
    let env = defaultPosixPtyLaunchEnv()
    check env.term == "xterm-256color"
    check env.colorTerm == "truecolor"
    check env.termProgram == ""
    check env.clearNoColor
    check env.childProbePath == ""

  test "color terminal inherits when present":
    check inheritedOrDefaultColorTerm("24bit", "truecolor") == "24bit"
    check inheritedOrDefaultColorTerm("", "truecolor") == "truecolor"

  test "child probe payload is stable":
    check childProbePayload("/tmp/example", "xterm-256color", "truecolor", "/dev/pts/1", "") ==
      "cwd=/tmp/example\nterm=xterm-256color\ncolorterm=truecolor\nno_color=\ntty=/dev/pts/1\n"

  test "launch environment clears inherited no-color suppression":
    let hadNoColor = existsEnv("NO_COLOR")
    let previousNoColor = getEnv("NO_COLOR", "")
    try:
      putEnv("NO_COLOR", "1")
      applyPosixPtyLaunchEnv(defaultPosixPtyLaunchEnv(), "", "")
      check not existsEnv("NO_COLOR")
    finally:
      if hadNoColor:
        putEnv("NO_COLOR", previousNoColor)
      else:
        delEnv("NO_COLOR")

  test "launch environment can preserve no-color suppression":
    let hadNoColor = existsEnv("NO_COLOR")
    let previousNoColor = getEnv("NO_COLOR", "")
    try:
      putEnv("NO_COLOR", "1")
      var env = defaultPosixPtyLaunchEnv()
      env.clearNoColor = false
      applyPosixPtyLaunchEnv(env, "", "")
      check getEnv("NO_COLOR", "") == "1"
    finally:
      if hadNoColor:
        putEnv("NO_COLOR", previousNoColor)
      else:
        delEnv("NO_COLOR")

  test "inherited fd policy preserves stdio only":
    check not shouldCloseInheritedFd(0)
    check not shouldCloseInheritedFd(1)
    check not shouldCloseInheritedFd(2)
    check shouldCloseInheritedFd(3)
    check not shouldCloseInheritedFd(7, [0, 1, 2, 7])
