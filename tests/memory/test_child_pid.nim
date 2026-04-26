## Proves spawnTerminal returns the actual nim_terminal child PID, not
## the xvfb-run wrapper or Xvfb sibling. Regression guard for the bug
## where we sampled the wrapper (3.5MB) and reported a falsely-flat
## curve.

import std/[unittest, os, strutils, options]
import ./rss_sampler

proc binaryPath(): string =
  let root = projectRoot()
  let candidate = root / "nim_terminal"
  doAssert fileExists(candidate),
    "nim_terminal binary not found — build with `nim c -d:release src/nim_terminal.nim`"
  candidate

proc readCommPub(pid: int): string =
  let path = "/proc/" & $pid & "/comm"
  if not fileExists(path): return ""
  try: result = readFile(path).strip() except CatchableError: result = ""

suite "rss_sampler:child_pid":

  test "spawnTerminal resolves to the nim_terminal child, not wrapper or Xvfb":
    var h = spawnTerminal(binaryPath())
    defer: h.shutdown()

    sleep(2000)  # let process come up

    let comm = readCommPub(h.pid)
    let rss = readRssKb(h.pid)

    echo "[child_pid] resolved pid=", h.pid, " comm='", comm,
         "' rss=", (if rss.isSome: $rss.get & "KB" else: "<gone>")

    check comm == "nim_terminal"
    check rss.isSome
    # Wrapper is ~3.5MB, Xvfb ~48MB, real terminal ~127MB.
    # Anything above 50MB unambiguously identifies the right process.
    check rss.get > 50_000
