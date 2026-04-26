## Tier 2 — workload soak.
##
## Drives a synthetic shell workload through the terminal for a fixed
## duration and asserts that resident-set growth stays under a slope
## threshold. Each scenario lives in `scenarios/<name>.cfg` and selects
## a shell.program that hammers a specific code path.
##
## Pass a scenario name as the first argument:
##
##     nim c -r tests/memory/test_soak.nim -- urandom_flood
##
## With no argument, runs every scenario in scenarios/.
##
## Environment variables:
##   SOAK_DURATION_MS  override per-scenario soak duration (default 30s)
##   SOAK_INTERVAL_MS  override RSS sampling interval (default 1000ms)
##   SOAK_WARMUP_MS    override warmup window before sampling (default 3000ms)
##   SOAK_SLOPE_KB_MIN override slope threshold (default 100 KB/min)

import std/[os, strutils, times]
import ./rss_sampler

const
  DefaultDurationMs = 30_000
  DefaultIntervalMs = 1000
  DefaultWarmupMs   = 3000
  DefaultSlopeKbMin = 100.0

type
  ScenarioResult = object
    name: string
    durationMs: int
    samples: SampleSeries
    slope: float
    minRss: int
    maxRss: int
    passed: bool

proc envIntOr(name: string; default: int): int =
  let v = getEnv(name)
  if v.len == 0: return default
  try: result = parseInt(v) except ValueError: result = default

proc envFloatOr(name: string; default: float): float =
  let v = getEnv(name)
  if v.len == 0: return default
  try: result = parseFloat(v) except ValueError: result = default

proc binaryPath(): string =
  let root = projectRoot()
  let candidate = root / "nim_terminal"
  if fileExists(candidate): return candidate
  raise newException(IOError, "nim_terminal binary not found; build first")

proc scenariosDir(): string =
  projectRoot() / "tests" / "memory" / "scenarios"

proc availableScenarios(): seq[string] =
  result = @[]
  if not dirExists(scenariosDir()): return
  for kind, path in walkDir(scenariosDir()):
    if kind == pcFile and path.endsWith(".cfg"):
      result.add path.extractFilename.changeFileExt("")

proc copyScenarioCfg(name: string): string =
  ## Copy the scenario cfg + its sibling .sh script into a temp dir,
  ## symlink resources/, and return the temp dir for use as workingDir.
  ##
  ## The cfg references its script as `./<name>.sh` (relative to cwd),
  ## so the script must be copied alongside and made executable.
  let scenarioPath = scenariosDir() / (name & ".cfg")
  let scriptPath = scenariosDir() / (name & ".sh")
  if not fileExists(scenarioPath):
    raise newException(IOError, "unknown scenario cfg: " & name)
  if not fileExists(scriptPath):
    raise newException(IOError, "missing scenario script: " & name & ".sh")
  let tmp = getTempDir() / ("nim_terminal_soak_" & name & "_" & $epochTime().int)
  createDir(tmp)
  let resSrc = projectRoot() / "resources"
  if dirExists(resSrc):
    createSymlink(resSrc, tmp / "resources")
  copyFile(scenarioPath, tmp / "nim_terminal.cfg")
  copyFile(scriptPath, tmp / (name & ".sh"))
  setFilePermissions(tmp / (name & ".sh"),
    {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})
  tmp

proc runScenario(name: string;
                 durationMs, intervalMs, warmupMs: int): ScenarioResult =
  let bin = binaryPath()
  let workDir = copyScenarioCfg(name)
  defer:
    try: removeDir(workDir) except CatchableError: discard

  # Spawn with a custom workingDir by overriding inside spawnTerminal — we
  # accomplish the same effect here by chdir'ing the parent process for
  # the duration of the spawn (xvfb-run inherits cwd).
  let prevCwd = getCurrentDir()
  setCurrentDir(workDir)
  var h: RunHandle
  try:
    h = spawnTerminal(bin)
  finally:
    setCurrentDir(prevCwd)
  defer: h.shutdown()

  sleep(warmupMs)
  let series = h.sample(durationMs, intervalMs)

  let slope = series.slopeKbPerMin
  ScenarioResult(
    name: name,
    durationMs: durationMs,
    samples: series,
    slope: slope,
    minRss: series.minRss,
    maxRss: series.maxRss,
    passed: series.len >= 5,  # passed/failed determined by caller threshold
  )

proc renderResult(r: ScenarioResult; threshold: float): string =
  let verdict = if r.slope < threshold: "PASS" else: "FAIL"
  result = "[soak/" & r.name & "] " & verdict &
           " slope=" & formatFloat(r.slope, ffDecimal, 2) & "KB/min" &
           " min=" & $r.minRss & "KB" &
           " max=" & $r.maxRss & "KB" &
           " Δ=" & $(r.maxRss - r.minRss) & "KB" &
           " samples=" & $r.samples.len & "\n"
  result.add r.samples.renderAsciiChart(width = 60, height = 8)

proc main() =
  let durationMs = envIntOr("SOAK_DURATION_MS", DefaultDurationMs)
  let intervalMs = envIntOr("SOAK_INTERVAL_MS", DefaultIntervalMs)
  let warmupMs   = envIntOr("SOAK_WARMUP_MS",   DefaultWarmupMs)
  let threshold  = envFloatOr("SOAK_SLOPE_KB_MIN", DefaultSlopeKbMin)

  var requested = commandLineParams()
  if requested.len == 0:
    requested = availableScenarios()
  if requested.len == 0:
    quit("no scenarios found in " & scenariosDir(), 2)

  var allPassed = true
  for name in requested:
    echo "=== running scenario: ", name, " (", durationMs, "ms) ==="
    let r = runScenario(name, durationMs, intervalMs, warmupMs)
    echo renderResult(r, threshold)
    if r.samples.len < 5:
      echo "  (insufficient samples — process exited early?)"
      allPassed = false
    elif r.slope >= threshold:
      allPassed = false

  if not allPassed:
    quit("one or more soak scenarios exceeded slope threshold of " &
         formatFloat(threshold, ffDecimal, 1) & " KB/min", 1)

when isMainModule:
  main()
