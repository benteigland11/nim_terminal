import std/unittest
import ../src/posix_pty_lib

suite "POSIX PTY launch environment":
  test "default launch environment is terminal-friendly":
    let env = defaultPosixPtyLaunchEnv()
    check env.term == "xterm-256color"
    check env.colorTerm == "truecolor"
    check env.termProgram == ""
    check env.childProbePath == ""

  test "color terminal inherits when present":
    check inheritedOrDefaultColorTerm("24bit", "truecolor") == "24bit"
    check inheritedOrDefaultColorTerm("", "truecolor") == "truecolor"

  test "child probe payload is stable":
    check childProbePayload("/tmp/example", "xterm-256color", "truecolor", "/dev/pts/1") ==
      "cwd=/tmp/example\nterm=xterm-256color\ncolorterm=truecolor\ntty=/dev/pts/1\n"

  test "inherited fd policy preserves stdio only":
    check not shouldCloseInheritedFd(0)
    check not shouldCloseInheritedFd(1)
    check not shouldCloseInheritedFd(2)
    check shouldCloseInheritedFd(3)
    check not shouldCloseInheritedFd(7, [0, 1, 2, 7])
