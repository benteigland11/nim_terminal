## Unit tests for the rss_sampler statistics helpers and child-PID
## resolution. Pure synthetic data — does not spawn the terminal.

import std/[unittest, math, strutils]
import ./rss_sampler

suite "rss_sampler:stats":

  test "slopeKbPerMin reports zero for a flat series":
    let s = @[
      Sample(tMs: 0,     rssKb: 1000),
      Sample(tMs: 60_000, rssKb: 1000),
      Sample(tMs: 120_000, rssKb: 1000),
    ]
    check abs(s.slopeKbPerMin) < 0.001

  test "slopeKbPerMin recovers a known +1000 KB/min trend":
    let s = @[
      Sample(tMs: 0,         rssKb: 1000),
      Sample(tMs: 60_000,    rssKb: 2000),
      Sample(tMs: 120_000,   rssKb: 3000),
      Sample(tMs: 180_000,   rssKb: 4000),
    ]
    check abs(s.slopeKbPerMin - 1000.0) < 0.5

  test "slopeKbPerMin recovers a known -500 KB/min trend":
    let s = @[
      Sample(tMs: 0,        rssKb: 5000),
      Sample(tMs: 60_000,   rssKb: 4500),
      Sample(tMs: 120_000,  rssKb: 4000),
    ]
    check abs(s.slopeKbPerMin - -500.0) < 0.5

  test "min/max/mean stats over a small series":
    let s = @[
      Sample(tMs: 0, rssKb: 100),
      Sample(tMs: 1, rssKb: 200),
      Sample(tMs: 2, rssKb: 300),
    ]
    check s.minRss == 100
    check s.maxRss == 300
    check abs(s.meanRss - 200.0) < 0.001

suite "rss_sampler:chart":

  test "renderAsciiChart returns a non-empty string for a real series":
    let s = @[
      Sample(tMs: 0,  rssKb: 100),
      Sample(tMs: 1,  rssKb: 150),
      Sample(tMs: 2,  rssKb: 200),
      Sample(tMs: 3,  rssKb: 175),
      Sample(tMs: 4,  rssKb: 225),
    ]
    let chart = s.renderAsciiChart(width = 20, height = 5)
    check chart.len > 0
    check chart.contains("min=100")
    check chart.contains("max=225")
    check chart.contains("samples=5")
    # eyeball test — print so a human reading the test output can see it
    echo "--- chart sample ---"
    echo chart
    echo "--- end chart ---"

  test "renderAsciiChart handles single-sample series gracefully":
    let s = @[Sample(tMs: 0, rssKb: 100)]
    let chart = s.renderAsciiChart()
    check chart == "(no data)\n"
