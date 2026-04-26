import std/strutils
import posix_pty_lib

var env = defaultPosixPtyLaunchEnv()
env.termProgram = "example-terminal"

doAssert env.term == "xterm-256color"
doAssert childProbePayload("/tmp/example", env.term, env.colorTerm, "/dev/pts/1").startsWith("cwd=/tmp/example")
