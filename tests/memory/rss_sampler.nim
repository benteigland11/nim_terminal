## Shared helpers for memory tests.
##
## Spawns `nim_terminal` under `xvfb-run` so tests run headless,
## samples RSS from `/proc/<pid>/status`, and exposes small statistics
## helpers used by the idle baseline and soak harnesses.

import std/[os, osproc, strutils, strtabs, times, math, options, sequtils]

type
  Sample* = object
    tMs*: int64       ## milliseconds since spawn
    rssKb*: int       ## resident set size in KB

  SampleSeries* = seq[Sample]

  RunHandle* = object
    process*: Process
    pid*: int
    spawnedAt*: float

# ---------------------------------------------------------------------------
# Process spawning
# ---------------------------------------------------------------------------

proc projectRoot*(): string =
  ## Walk upward from this file until we find `nim_terminal.nimble`.
  result = currentSourcePath().parentDir
  while result.len > 1 and not fileExists(result / "nim_terminal.nimble"):
    result = result.parentDir

proc readComm(pid: int): string =
  let path = "/proc/" & $pid & "/comm"
  if not fileExists(path): return ""
  try: result = readFile(path).strip()
  except CatchableError: result = ""

iterator childrenOf(parentPid: int): int =
  for kind, path in walkDir("/proc"):
    if kind != pcDir: continue
    let name = path.extractFilename
    if not name.allCharsInSet({'0'..'9'}): continue
    let statPath = path / "stat"
    if not fileExists(statPath): continue
    try:
      let stat = readFile(statPath)
      let rparen = stat.rfind(')')
      if rparen < 0: continue
      let after = stat[rparen + 2 .. ^1].split(' ')
      if after.len < 2: continue
      if parseInt(after[1]) == parentPid:
        yield parseInt(name)
    except CatchableError:
      continue

proc findNamedDescendant(parentPid: int; commPrefix: string; maxDepth: int = 3): Option[int] =
  ## Find a descendant process whose /proc/<pid>/comm starts with commPrefix.
  ## /proc/comm is truncated to 15 bytes — so callers should pass the
  ## leading characters of the binary basename.
  if maxDepth <= 0: return none(int)
  for child in childrenOf(parentPid):
    let comm = readComm(child)
    if comm.len > 0 and (commPrefix.startsWith(comm) or comm.startsWith(commPrefix)):
      return some(child)
    let deeper = findNamedDescendant(child, commPrefix, maxDepth - 1)
    if deeper.isSome: return deeper
  none(int)

proc spawnTerminal*(binary: string; cfg: string = ""; extraEnv: seq[(string, string)] = @[]): RunHandle =
  ## Spawn the given terminal binary under xvfb-run. Optionally point at a
  ## custom cfg via NIM_TERMINAL_CFG (the app reads its config file from
  ## that env var if set, otherwise falls back to nim_terminal.cfg).
  ##
  ## The returned RunHandle's pid is the *child* nim_terminal process,
  ## not the xvfb-run wrapper, so RSS samples reflect the app's footprint.
  let root = projectRoot()
  var env = newStringTable()
  for (k, v) in extraEnv: env[k] = v
  if cfg.len > 0: env["NIM_TERMINAL_CFG"] = cfg
  # Force software OpenGL — deterministic, no GPU driver leaks pollute results.
  env["LIBGL_ALWAYS_SOFTWARE"] = "1"
  let cmd = "xvfb-run"
  let args = @["-a", "--server-args=-screen 0 1280x800x24", binary]
  let p = startProcess(
    command = cmd,
    workingDir = root,
    args = args,
    env = env,
    options = {poUsePath, poStdErrToStdOut}
  )
  # xvfb-run spawns Xvfb plus our binary as siblings. Search the descendant
  # tree for a process whose /proc/comm matches the binary basename.
  let basename = binary.extractFilename
  var childPid = -1
  let deadline = epochTime() + 5.0
  while epochTime() < deadline:
    sleep(100)
    let found = findNamedDescendant(p.processID, basename)
    if found.isSome:
      childPid = found.get
      break
  if childPid < 0:
    childPid = p.processID  # degraded mode: sample the wrapper
  RunHandle(process: p, pid: childPid, spawnedAt: epochTime())

proc shutdown*(h: var RunHandle; graceMs: int = 500) =
  ## Try a polite SIGTERM, escalate to SIGKILL if still alive.
  if h.process == nil: return
  if h.process.running:
    h.process.terminate()
    let deadline = epochTime() + graceMs / 1000
    while h.process.running and epochTime() < deadline:
      sleep(20)
    if h.process.running:
      h.process.kill()
  discard h.process.waitForExit()
  h.process.close()
  h.process = nil

# ---------------------------------------------------------------------------
# RSS sampling
# ---------------------------------------------------------------------------

proc readRssKb*(pid: int): Option[int] =
  ## Read VmRSS in KB from /proc/<pid>/status. None if the process is gone.
  let path = "/proc/" & $pid & "/status"
  if not fileExists(path):
    return none(int)
  try:
    for line in lines(path):
      if line.startsWith("VmRSS:"):
        # "VmRSS:\t   12345 kB"
        for tok in line.splitWhitespace():
          if tok.allCharsInSet({'0'..'9'}):
            return some(parseInt(tok))
  except IOError:
    return none(int)
  none(int)

proc sample*(h: RunHandle; durationMs: int; intervalMs: int): SampleSeries =
  ## Sample RSS at a fixed interval for `durationMs`. Stops early if the
  ## process exits.
  result = @[]
  let start = epochTime()
  let deadline = start + durationMs / 1000
  while epochTime() < deadline:
    if not h.process.running: break
    let r = readRssKb(h.pid)
    if r.isSome:
      let tMs = int64((epochTime() - h.spawnedAt) * 1000)
      result.add Sample(tMs: tMs, rssKb: r.get)
    sleep(intervalMs)

# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------

proc minRss*(s: SampleSeries): int =
  if s.len == 0: return 0
  result = s[0].rssKb
  for x in s: result = min(result, x.rssKb)

proc maxRss*(s: SampleSeries): int =
  if s.len == 0: return 0
  result = s[0].rssKb
  for x in s: result = max(result, x.rssKb)

proc meanRss*(s: SampleSeries): float =
  if s.len == 0: return 0.0
  var total = 0
  for x in s: total += x.rssKb
  total.float / s.len.float

proc slopeKbPerMin*(s: SampleSeries): float =
  ## Simple least-squares slope of RSS over time, expressed in KB/min.
  ## Positive = growing, negative = shrinking, ~0 = flat.
  if s.len < 2: return 0.0
  var sumT, sumR, sumTT, sumTR: float
  for x in s:
    let t = x.tMs.float / 60_000.0  # minutes since spawn
    let r = x.rssKb.float
    sumT += t; sumR += r; sumTT += t * t; sumTR += t * r
  let n = s.len.float
  let denom = n * sumTT - sumT * sumT
  if denom == 0.0: return 0.0
  (n * sumTR - sumT * sumR) / denom

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

proc renderAsciiChart*(s: SampleSeries; width: int = 60; height: int = 12): string =
  ## Tiny text plot for inclusion in MEMORY.md and CI logs.
  if s.len < 2: return "(no data)\n"
  let lo = s.minRss.float
  let hi = max(s.maxRss.float, lo + 1.0)
  var grid = newSeqWith(height, repeat(' ', width))
  for i, x in s:
    let xPos = (i * (width - 1)) div (s.len - 1)
    let yNorm = (x.rssKb.float - lo) / (hi - lo)
    let yPos = height - 1 - int(round(yNorm * (height - 1).float))
    grid[yPos][xPos] = '*'
  result = ""
  for row in grid:
    result.add row & "\n"
  result.add "min=" & $s.minRss & "KB max=" & $s.maxRss &
             "KB Δ=" & $(s.maxRss - s.minRss) & "KB samples=" & $s.len & "\n"
