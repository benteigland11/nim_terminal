## Tier 3 smoke: actually drive nim_terminal under valgrind for a single
## short scenario and assert no DEFINITELY LOST bytes attributable to our
## code (third-party noise is filtered by suppressions.supp).
##
## This test is gated. It is slow (10-30x native) and requires:
##   - valgrind on PATH
##   - xvfb-run on PATH
##   - the debug binary at tests/memory/valgrind/nim_terminal_debug
##
## Skip path: if any prerequisite is missing, the test reports skip
## and exits 0 — CI runs it on demand, not by default.
##
## Override knobs (env vars):
##   VG_SCENARIO   scenario name (default: alt_buffer_toggle, the cheapest)
##   VG_DURATION   seconds to drive the scenario (default: 8)

import std/[unittest, os, osproc, strutils, options]
import ./parse_leaks

const defaultScenario = "alt_buffer_toggle"
const defaultDuration = "8"

proc which(bin: string): Option[string] =
  for dir in getEnv("PATH").split(':'):
    if dir.len == 0: continue
    let p = dir / bin
    if fileExists(p): return some(p)
  none(string)

proc skipReason(): string =
  let here = currentSourcePath().parentDir
  if not fileExists(here / "nim_terminal_debug"):
    return "debug binary missing — build with: " &
      "nim c --mm:orc -d:useMalloc -d:debug --debugger:native " &
      "-o:tests/memory/valgrind/nim_terminal_debug src/nim_terminal.nim"
  if which("valgrind").isNone: return "valgrind not on PATH"
  if which("xvfb-run").isNone: return "xvfb-run not on PATH"
  ""

suite "valgrind smoke":
  test "no definite leaks under short scenario":
    let why = skipReason()
    if why.len > 0:
      echo "[SKIP] ", why
      skip()
    else:
      let here = currentSourcePath().parentDir
      let scenario = getEnv("VG_SCENARIO", defaultScenario)
      let duration = getEnv("VG_DURATION", defaultDuration)
      let cmd = here / "run_valgrind.sh"

      # Runner prints the log path on success as its last stdout line.
      let (output, exitCode) = execCmdEx(cmd & " " & scenario & " " & duration)
      check exitCode == 0
      if exitCode == 0:
        var logPath = ""
        for line in output.splitLines:
          if line.endsWith(".log"):
            logPath = line.strip()
        check logPath.len > 0
        if logPath.len > 0 and fileExists(logPath):
          let summary = parseValgrindLog(logPath)
          echo render(summary)
          check summary.parsed
          # Contract: zero bytes definitely lost from our code. Suppressions
          # absorb known third-party noise; new leaks here are ours.
          check summary.definiteLostBytes == 0
          check summary.indirectLostBytes == 0
      else:
        echo output
