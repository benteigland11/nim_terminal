## Tier 4 — GPU resource ledger smoke.
##
## Spawns Waymark under Xvfb with the renderer snapshot hook enabled and
## checks that texture/buffer resources are visible and anomaly-free while the
## process is running. This proves the app can report GPU-owned resources,
## which RSS and Valgrind cannot see directly.

import std/[json, os, osproc, strtabs, strutils, unittest]
import ./rss_sampler

const
  WarmupMs = 3000
  PollMs = 100

proc binaryPath(): string =
  let root = projectRoot()
  let candidate = root / "nim_terminal"
  if fileExists(candidate): return candidate
  raise newException(IOError, "nim_terminal binary not found; build first")

proc waitForSnapshot(path: string; timeoutMs: int): JsonNode =
  var elapsed = 0
  while elapsed < timeoutMs:
    if fileExists(path):
      try:
        let raw = readFile(path).strip()
        if raw.len > 0:
          return parseJson(raw)
      except CatchableError:
        discard
    sleep(PollMs)
    elapsed += PollMs
  raise newException(IOError, "GPU snapshot was not written to " & path)

proc kindStats(snapshot: JsonNode; kind: string): JsonNode =
  for row in snapshot["stats"].items:
    if row["kind"].getStr() == kind:
      return row
  newJNull()

suite "memory:tier4:gpu_resources":

  test "renderer reports live textures and buffers without anomalies":
    let reportPath = getTempDir() / ("waymark_gpu_snapshot_" & $getCurrentProcessId() & ".json")
    try: removeFile(reportPath) except CatchableError: discard

    var env = newStringTable()
    env["WAYMARK_GPU_SNAPSHOT_PATH"] = reportPath
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    let p = startProcess(
      command = "xvfb-run",
      workingDir = projectRoot(),
      args = @["-a", "--server-args=-screen 0 1280x800x24", binaryPath()],
      env = env,
      options = {poUsePath, poStdErrToStdOut},
    )
    defer:
      if p.running:
        p.terminate()
        discard p.waitForExit()
      p.close()
      try: removeFile(reportPath) except CatchableError: discard

    sleep(WarmupMs)
    let snapshot = waitForSnapshot(reportPath, 5000)
    let textures = kindStats(snapshot, "texture")
    let buffers = kindStats(snapshot, "buffer")

    echo "[gpu] live_bytes=", snapshot["total_live_bytes"].getInt(),
         " peak_bytes=", snapshot["total_peak_bytes"].getInt(),
         " live_resources=", snapshot["leak_count"].getInt(),
         " anomalies=", snapshot["anomaly_count"].getInt()

    require textures.kind != JNull
    require buffers.kind != JNull
    check textures["live_count"].getInt() >= 3
    check textures["live_bytes"].getInt() > 0
    check buffers["live_count"].getInt() >= 1
    check buffers["live_bytes"].getInt() > 0
    check snapshot["anomaly_count"].getInt() == 0
