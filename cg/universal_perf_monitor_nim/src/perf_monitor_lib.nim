## High-resolution performance monitor.
##
## Tracks frames per second (FPS) and average processing latency.
## Useful for optimizing game loops and real-time UI applications.

import std/times

type
  PerfMonitor* = ref object
    startTime: float
    lastReportTime: float
    frames: int
    totalLatency: float
    lastFrameStart: float

proc newPerfMonitor*(): PerfMonitor =
  let now = cpuTime()
  PerfMonitor(
    startTime: now,
    lastReportTime: now,
    frames: 0,
    totalLatency: 0.0,
    lastFrameStart: 0.0
  )

proc beginFrame*(m: PerfMonitor) =
  ## Mark the start of a frame to track latency.
  m.lastFrameStart = cpuTime()

proc endFrame*(m: PerfMonitor) =
  ## Mark the end of a frame and accumulate latency.
  if m.lastFrameStart > 0:
    m.totalLatency += (cpuTime() - m.lastFrameStart)
    m.lastFrameStart = 0
  inc m.frames

proc shouldReport*(m: PerfMonitor, interval: float = 2.0): bool =
  ## True if the specified interval (in seconds) has passed.
  cpuTime() - m.lastReportTime >= interval

proc takeReport*(m: PerfMonitor): tuple[fps: float, avgLatencyMs: float] =
  ## Calculate stats and reset counters for the next interval.
  let now = cpuTime()
  let dt = now - m.lastReportTime
  if dt > 0 and m.frames > 0:
    result.fps = float(m.frames) / dt
    result.avgLatencyMs = (m.totalLatency / float(m.frames)) * 1000.0
  
  m.lastReportTime = now
  m.frames = 0
  m.totalLatency = 0.0
