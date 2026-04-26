## Tier 1 — idle baseline.
##
## Spawn nim_terminal under xvfb, render some frames, sit for 10s,
## sample RSS at 1Hz, assert the curve is flat.
##
## A failure here points at a leak in the render loop, the input
## poll, or any other tick-driven path. Cheapest possible regression
## guard — runs in well under a minute.

import std/[os, strutils, unittest]
import ./rss_sampler

const
  WarmupMs    = 2000   # let the window come up and the first frames render
  SampleMs    = 10_000 # 10s observation window
  IntervalMs  = 1000
  ToleranceKb = 1024   # max - min must stay under 1 MB

proc binaryPath(): string =
  let root = projectRoot()
  let candidate = root / "nim_terminal"
  if fileExists(candidate): return candidate
  # CI may build into a different name — fall back to a debug binary.
  let dbg = root / "nim_terminal_dbg"
  if fileExists(dbg): return dbg
  raise newException(IOError,
    "nim_terminal binary not found at " & candidate &
    "; build with `nim c -d:release src/nim_terminal.nim` first")

suite "memory:tier1:idle":

  test "RSS stays flat over 10s of idle":
    let bin = binaryPath()
    var h = spawnTerminal(bin)
    defer: h.shutdown()

    sleep(WarmupMs)
    let series = h.sample(SampleMs, IntervalMs)

    require series.len >= 5  # we expect ~10 samples; require at least 5

    let delta = series.maxRss - series.minRss
    let slope = series.slopeKbPerMin

    echo "[tier1] samples=", series.len,
         " min=", series.minRss, "KB",
         " max=", series.maxRss, "KB",
         " Δ=", delta, "KB",
         " slope=", formatFloat(slope, ffDecimal, 2), "KB/min"
    echo series.renderAsciiChart(width = 60, height = 8)

    check delta < ToleranceKb
    # Slope tolerance is generous — any growth >5MB/min over 10s is alarming.
    check slope < 5_000.0
