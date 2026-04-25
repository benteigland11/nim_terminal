## Example usage of Perf Monitor.

import perf_monitor_lib
import std/os

let m = newPerfMonitor()

# Simulate a 10-frame burst
for i in 0 ..< 10:
  m.beginFrame()
  sleep(1) # small delay
  m.endFrame()

# Take a report
let stats = m.takeReport()
echo "FPS: ", stats.fps
echo "Avg Latency: ", stats.avgLatencyMs, " ms"

echo "Perf-monitor example verified."
