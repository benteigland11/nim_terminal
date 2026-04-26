## Reusable POSIX terminal child-process launch environment helpers.
##
## Platform PTY syscalls stay in the consumer because they require C FFI.
## This widget owns the pure launch contract around cwd, TERM/COLORTERM,
## TERM_PROGRAM, and optional child diagnostics.

import std/os

type
  PosixPtyLaunchEnv* = object
    term*: string
    colorTerm*: string
    termProgram*: string
    childProbePath*: string

func defaultPosixPtyLaunchEnv*(): PosixPtyLaunchEnv =
  PosixPtyLaunchEnv(term: "xterm-256color", colorTerm: "truecolor")

func inheritedOrDefaultColorTerm*(inherited, fallback: string): string =
  if inherited.len > 0:
    inherited
  else:
    fallback

func childProbePayload*(cwd, term, colorTerm, tty: string): string =
  "cwd=" & cwd & "\n" &
  "term=" & term & "\n" &
  "colorterm=" & colorTerm & "\n" &
  "tty=" & tty & "\n"

proc applyPosixPtyLaunchEnv*(env: PosixPtyLaunchEnv, cwd, tty: string) =
  if cwd.len > 0:
    try:
      setCurrentDir(cwd)
    except OSError:
      discard
    putEnv("PWD", getCurrentDir())
  if env.term.len > 0:
    putEnv("TERM", env.term)
  if env.colorTerm.len > 0:
    putEnv("COLORTERM", env.colorTerm)
  if env.termProgram.len > 0:
    putEnv("TERM_PROGRAM", env.termProgram)
  if env.childProbePath.len > 0:
    try:
      writeFile(env.childProbePath,
        childProbePayload(getCurrentDir(), env.term, env.colorTerm, tty))
    except OSError:
      discard
