import std/unittest
import ../src/perf_monitor_lib

suite "perf monitor":

  test "basic accumulation":
    let m = newPerfMonitor()
    m.beginFrame()
    m.endFrame()
    let stats = m.takeReport()
    check stats.fps > 0
    check stats.avgLatencyMs >= 0.0
