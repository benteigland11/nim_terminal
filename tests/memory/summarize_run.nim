## Read an overnight run directory and emit SUMMARY.md + results.json
## in the public-artifact format the community will see.
##
## Input: path to tests/memory/reports/overnight-<TS>/
## Reads: tier1_idle.log, tier2_soak.log, tier3_valgrind_<scenario>.log,
##        build_release.log (for binary SHA), build_debug.log
## Writes: <dir>/SUMMARY.md, <dir>/results.json

import std/[os, osproc, strutils, parseutils, json, times, sequtils]
import ./valgrind/parse_leaks

const ScenarioOrder = [
  "alt_buffer_toggle", "scroll_churn", "sgr_storm",
  "urandom_flood", "utf8_mix",
]

const SoakSlopeThreshold = 100.0   # KB/min — must match run_overnight.sh

type
  Tier1Row = object
    samples: int
    minKb, maxKb, deltaKb: int
    slope: float
    verdict: string

  Tier2Row = object
    name: string
    samples: int
    minKb, maxKb, deltaKb: int
    slope: float
    verdict: string
    found: bool

  Tier3Row = object
    name: string
    definite, indirect, possible, reachable, suppressed: int
    errors: int
    verdict: string
    found: bool

  Tier4Row = object
    liveBytes, peakBytes, liveResources, anomalies: int
    verdict: string
    found: bool

  RunSummary = object
    runDir: string
    timestamp: string
    commitSha: string
    nimVersion: string
    kernel: string
    releaseSha: string
    debugSha: string
    soakDurationMs: int
    vgDurationS: int
    tier1: Tier1Row
    tier2: seq[Tier2Row]
    tier3: seq[Tier3Row]
    tier4: Tier4Row
    overallPass: bool

# ---------- helpers ----------

proc readLinesIfExists(path: string): seq[string] =
  if not fileExists(path): return @[]
  for ln in lines(path): result.add ln

proc shellCapture(cmd: string): string =
  let (output, code) = execCmdEx(cmd)
  if code == 0: return output.strip()
  ""

proc parseTier1(logPath: string): Tier1Row =
  ## Looks for: "[tier1] samples=N min=NKB max=NKB Δ=NKB slope=N.NNKB/min"
  result.verdict = "FAIL"
  for ln in readLinesIfExists(logPath):
    if not ln.startsWith("[tier1]"): continue
    var samples, mn, mx, delta: int
    var slope: float
    # Use simple split — strscans's UTF-8 Δ handling is finicky.
    for token in ln.split({' ', '\t'}):
      if token.startsWith("samples="):
        discard parseInt(token[len("samples=") .. ^1], samples)
      elif token.startsWith("min=") and token.endsWith("KB"):
        discard parseInt(token[len("min=") ..< token.len - 2], mn)
      elif token.startsWith("max=") and token.endsWith("KB"):
        discard parseInt(token[len("max=") ..< token.len - 2], mx)
      elif token.endsWith("KB") and token.contains("="):
        # delta token starts with non-ascii Δ; match by suffix
        let eqIdx = token.find('=')
        if eqIdx >= 0:
          let v = token[eqIdx + 1 ..< token.len - 2]
          var n: int
          if parseInt(v, n) > 0 and (mx - mn) == n:
            delta = n
      elif token.startsWith("slope="):
        let v = token[len("slope=") .. ^1]
        # strip "KB/min" if present
        let numEnd = v.find("KB")
        let numStr = if numEnd > 0: v[0 ..< numEnd] else: v
        discard parseFloat(numStr, slope)
    result.samples = samples
    result.minKb = mn
    result.maxKb = mx
    result.deltaKb = mx - mn
    result.slope = slope
    if samples >= 5 and result.deltaKb < 1024 and slope < 5_000.0:
      result.verdict = "PASS"
    return

proc parseTier2(logPath: string): seq[Tier2Row] =
  ## Looks for: "[soak/<name>] PASS|FAIL slope=N.NN..." per scenario.
  for scen in ScenarioOrder:
    var row = Tier2Row(name: scen, verdict: "FAIL", found: false)
    result.add row
  for ln in readLinesIfExists(logPath):
    if not ln.startsWith("[soak/"): continue
    let closeIdx = ln.find("]")
    if closeIdx < 0: continue
    let name = ln[len("[soak/") ..< closeIdx]
    var idx = -1
    for i, r in result:
      if r.name == name:
        idx = i; break
    if idx < 0: continue
    var samples, mn, mx: int
    var slope: float
    var verdict = "FAIL"
    let parts = ln[closeIdx + 1 .. ^1].split({' ', '\t'})
    for token in parts:
      let t = token.strip()
      if t.len == 0: continue
      if t == "PASS" or t == "FAIL":
        verdict = t
      elif t.startsWith("slope="):
        let v = t[len("slope=") .. ^1]
        let numEnd = v.find("KB")
        let numStr = if numEnd > 0: v[0 ..< numEnd] else: v
        discard parseFloat(numStr, slope)
      elif t.startsWith("min=") and t.endsWith("KB"):
        discard parseInt(t[len("min=") ..< t.len - 2], mn)
      elif t.startsWith("max=") and t.endsWith("KB"):
        discard parseInt(t[len("max=") ..< t.len - 2], mx)
      elif t.startsWith("samples="):
        discard parseInt(t[len("samples=") .. ^1], samples)
    result[idx].samples = samples
    result[idx].minKb = mn
    result[idx].maxKb = mx
    result[idx].deltaKb = mx - mn
    result[idx].slope = slope
    result[idx].verdict = verdict
    result[idx].found = true

proc findValgrindLog(runDir, scenario: string): string =
  ## Prefer the raw valgrind log named by this run's phase log. Fall back to
  ## the latest matching raw log only for older partial runs that predate
  ## phase-output capture.
  let phaseLog = runDir / ("tier3_valgrind_" & scenario & ".log")
  if fileExists(phaseLog):
    for ln in readLinesIfExists(phaseLog):
      let stripped = ln.strip()
      if stripped.endsWith(".log") and fileExists(stripped):
        return stripped

  let reportsDir = parentDir(runDir)
  var newest = ""
  var newestMtime: Time
  for kind, path in walkDir(reportsDir):
    if kind != pcFile: continue
    let base = extractFilename(path)
    if not base.startsWith("valgrind-" & scenario & "-"): continue
    if not base.endsWith(".log"): continue
    let mt = getLastModificationTime(path)
    if newest.len == 0 or mt > newestMtime:
      newest = path; newestMtime = mt
  newest

proc parseTier3(runDir: string): seq[Tier3Row] =
  for scen in ScenarioOrder:
    var row = Tier3Row(name: scen, verdict: "FAIL", found: false)
    let vgLog = findValgrindLog(runDir, scen)
    if vgLog.len > 0 and fileExists(vgLog):
      try:
        let s = parseValgrindLog(vgLog)
        if s.parsed:
          row.definite = s.definiteLostBytes
          row.indirect = s.indirectLostBytes
          row.possible = s.possibleLostBytes
          row.reachable = s.reachableBytes
          row.suppressed = s.bytes[lkSuppressed]
          row.errors = s.errorCount
          row.found = true
          if row.definite == 0 and row.indirect == 0 and
              row.possible == 0 and row.errors == 0:
            row.verdict = "PASS"
      except CatchableError:
        discard
    result.add row

proc parseTier4(logPath: string): Tier4Row =
  result.verdict = "FAIL"
  for ln in readLinesIfExists(logPath):
    if not ln.startsWith("[gpu]"): continue
    result.found = true
    for token in ln.split({' ', '\t'}):
      if token.startsWith("live_bytes="):
        discard parseInt(token[len("live_bytes=") .. ^1], result.liveBytes)
      elif token.startsWith("peak_bytes="):
        discard parseInt(token[len("peak_bytes=") .. ^1], result.peakBytes)
      elif token.startsWith("live_resources="):
        discard parseInt(token[len("live_resources=") .. ^1], result.liveResources)
      elif token.startsWith("anomalies="):
        discard parseInt(token[len("anomalies=") .. ^1], result.anomalies)
    if result.liveBytes > 0 and result.peakBytes >= result.liveBytes and
        result.liveResources > 0 and result.anomalies == 0:
      result.verdict = "PASS"
    return

# ---------- gather metadata ----------

proc gatherMetadata(runDir: string; soakMs: int; vgS: int): RunSummary =
  result.runDir = runDir
  result.timestamp = extractFilename(runDir).replace("overnight-", "")
  result.soakDurationMs = soakMs
  result.vgDurationS = vgS
  # runDir = <repo>/tests/memory/reports/overnight-<TS> → 4 levels up to repo root.
  let repoRoot = runDir.parentDir.parentDir.parentDir.parentDir
  result.commitSha = shellCapture("git -C " & repoRoot & " rev-parse HEAD")
  result.nimVersion = shellCapture("nim --version | head -1")
  result.kernel = shellCapture("uname -r")
  # Hash the binaries that were ACTUALLY EXECUTED by the tiers, not just the
  # most-recently-built one. Tier 1/2 invoke `./nim_terminal` (which the
  # runner cp'd from nim_terminal_release, but only if it wasn't busy). Tier 3
  # invokes nim_terminal_debug. If `./nim_terminal` is from a different
  # commit because the cp failed, SUMMARY.md must say so honestly.
  let runtimeBin = repoRoot / "nim_terminal"
  let debugBin   = repoRoot / "tests/memory/valgrind/nim_terminal_debug"
  result.releaseSha = shellCapture("sha256sum " & runtimeBin & " 2>/dev/null | awk '{print $1}'")
  result.debugSha = shellCapture("sha256sum " & debugBin & " 2>/dev/null | awk '{print $1}'")
  let freshBin = repoRoot / "nim_terminal_release"
  let freshSha = shellCapture("sha256sum " & freshBin & " 2>/dev/null | awk '{print $1}'")
  if freshSha.len > 0 and freshSha != result.releaseSha:
    # ./nim_terminal didn't get refreshed (live editor session?). The tier
    # numbers reflect the older binary. Surface the divergence so readers
    # can re-run if it matters.
    result.releaseSha = result.releaseSha &
      " [WARN: differs from freshly-built nim_terminal_release " & freshSha & "]"

# ---------- emitters ----------

proc renderMarkdown(s: RunSummary): string =
  let pass = s.tier1.verdict == "PASS" and
             s.tier2.allIt(it.verdict == "PASS" and it.found) and
             s.tier3.allIt(it.verdict == "PASS" and it.found) and
             s.tier4.verdict == "PASS" and s.tier4.found
  let verdict = if pass: "PASS" else: "FAIL"
  result = "# Waymark Memory Validation — " & s.timestamp & "\n\n"
  result.add "Commit: `" & s.commitSha & "`\n"
  result.add "Host: Linux " & s.kernel & "\n"
  result.add "Nim: `" & s.nimVersion & "`\n"
  result.add "Build:\n"
  result.add "- release sha256: `" & s.releaseSha & "`\n"
  result.add "- valgrind debug sha256: `" & s.debugSha & "`\n"
  result.add "Runtime: Xvfb 1280x800x24, software OpenGL\n\n"
  result.add "Artifacts:\n"
  result.add "- machine-readable receipt: `results.json`\n"
  result.add "- phase audit trail: `PHASES.md`\n"
  result.add "- raw logs: this directory\n\n"
  result.add "## Verdict\n\n**" & verdict & "**\n\n"

  result.add "## Tier 1 — Idle Baseline\n\n"
  result.add "| Duration | Samples | Min RSS | Max RSS | Delta | Slope | Verdict |\n"
  result.add "|---|---:|---:|---:|---:|---:|---|\n"
  result.add "| 10s | " & $s.tier1.samples &
             " | " & $s.tier1.minKb & " KB" &
             " | " & $s.tier1.maxKb & " KB" &
             " | " & $s.tier1.deltaKb & " KB" &
             " | " & formatFloat(s.tier1.slope, ffDecimal, 2) & " KB/min" &
             " | " & s.tier1.verdict & " |\n\n"

  result.add "## Tier 2 — Scenario Soak\n\n"
  result.add "Threshold: < " & $int(SoakSlopeThreshold) &
             " KB/min over " & $(s.soakDurationMs div 1000) & "s per scenario\n\n"
  result.add "| Scenario | Samples | Min RSS | Max RSS | Delta | Slope | Verdict |\n"
  result.add "|---|---:|---:|---:|---:|---:|---|\n"
  for r in s.tier2:
    if not r.found:
      result.add "| " & r.name & " | — | — | — | — | — | NOT RUN |\n"
    else:
      result.add "| " & r.name &
                 " | " & $r.samples &
                 " | " & $r.minKb & " KB" &
                 " | " & $r.maxKb & " KB" &
                 " | " & $r.deltaKb & " KB" &
                 " | " & formatFloat(r.slope, ffDecimal, 2) & " KB/min" &
                 " | " & r.verdict & " |\n"
  result.add "\n"

  result.add "## Tier 3 — Valgrind\n\n"
  result.add "Duration: " & $s.vgDurationS & "s per scenario.\n"
  result.add "Suppressions: `tests/memory/valgrind/suppressions.supp` " &
             "(Mesa/GLFW/fontconfig/X11/ld noise filtered).\n\n"
  result.add "> **Honesty caveat.** Valgrind's 10–30× slowdown means " &
             "`nim_terminal_debug` is killed by the time bound before any " &
             "scenario workload runs at steady state. Per-scenario rows " &
             "below mostly measure the same init + early-runtime " &
             "allocations. Steady-state leak detection is Tier 2's job; " &
             "Tier 3 catches leaks in startup paths and is the line of " &
             "defense against `definitely lost` regressions anywhere in " &
             "the codebase.\n\n"
  result.add "| Scenario | Definite | Indirect | Possible | Still Reachable | Suppressed | Errors | Verdict |\n"
  result.add "|---|---:|---:|---:|---:|---:|---:|---|\n"
  for r in s.tier3:
    if not r.found:
      result.add "| " & r.name & " | — | — | — | — | — | — | NOT RUN |\n"
    else:
      result.add "| " & r.name &
                 " | " & $r.definite & " B" &
                 " | " & $r.indirect & " B" &
                 " | " & $r.possible & " B" &
                 " | " & $r.reachable & " B" &
                 " | " & $r.suppressed & " B" &
                 " | " & $r.errors &
                 " | " & r.verdict & " |\n"
  result.add "\n"

  result.add "## Tier 4 — GPU Resource Ledger\n\n"
  result.add "Scope: renderer-owned OpenGL textures and tile-batcher buffer, " &
             "reported from Waymark's internal resource ledger while running " &
             "under Xvfb/software OpenGL.\n\n"
  result.add "| Live Bytes | Peak Bytes | Live Resources | Anomalies | Verdict |\n"
  result.add "|---:|---:|---:|---:|---|\n"
  if not s.tier4.found:
    result.add "| — | — | — | — | NOT RUN |\n\n"
  else:
    result.add "| " & $s.tier4.liveBytes &
               " B | " & $s.tier4.peakBytes &
               " B | " & $s.tier4.liveResources &
               " | " & $s.tier4.anomalies &
               " | " & s.tier4.verdict & " |\n\n"

  result.add "## Known Limits\n\n"
  result.add "- Linux-only `/proc` RSS sampler. macOS/Windows not yet supported.\n"
  result.add "- Xvfb + software OpenGL runtime (`LIBGL_ALWAYS_SOFTWARE=1`) for determinism.\n"
  result.add "- Tier 4 tracks Waymark-owned GPU resources through internal GL " &
             "lifecycle instrumentation; it is not a vendor VRAM profiler.\n"
  result.add "- Tier 2 slope proves bounded resident growth under these workloads, " &
             "not formal absence of every possible leak.\n"
  result.add "- Valgrind runs are time-bounded; under heavy scenarios the wrapped " &
             "program is killed before completing the workload, so Tier 3 mainly " &
             "exercises init + early-runtime allocations.\n"

proc toJson(s: RunSummary): JsonNode =
  result = newJObject()
  result["commit"] = %s.commitSha
  result["timestamp"] = %s.timestamp
  result["toolchain"] = %*{
    "nim": s.nimVersion,
    "kernel": s.kernel,
    "release_sha256": s.releaseSha,
    "debug_sha256": s.debugSha,
  }
  let pass = s.tier1.verdict == "PASS" and
             s.tier2.allIt(it.verdict == "PASS" and it.found) and
             s.tier3.allIt(it.verdict == "PASS" and it.found) and
             s.tier4.verdict == "PASS" and s.tier4.found
  result["verdict"] = %(if pass: "pass" else: "fail")
  result["tier1"] = %*{
    "idle": {
      "samples": s.tier1.samples,
      "min_kb": s.tier1.minKb,
      "max_kb": s.tier1.maxKb,
      "delta_kb": s.tier1.deltaKb,
      "slope_kb_min": s.tier1.slope,
      "verdict": s.tier1.verdict,
    }
  }
  var t2arr = newJArray()
  for r in s.tier2:
    t2arr.add %*{
      "name": r.name, "found": r.found,
      "samples": r.samples, "min_kb": r.minKb,
      "max_kb": r.maxKb, "delta_kb": r.deltaKb,
      "slope_kb_min": r.slope, "verdict": r.verdict,
    }
  result["tier2"] = %*{
    "threshold_kb_min": SoakSlopeThreshold,
    "duration_ms": s.soakDurationMs,
    "scenarios": t2arr,
  }
  var t3arr = newJArray()
  for r in s.tier3:
    t3arr.add %*{
      "name": r.name, "found": r.found,
      "definite_bytes": r.definite,
      "indirect_bytes": r.indirect,
      "possible_bytes": r.possible,
      "still_reachable_bytes": r.reachable,
      "suppressed_bytes": r.suppressed,
      "errors": r.errors,
      "verdict": r.verdict,
    }
  result["tier3"] = %*{
    "duration_s": s.vgDurationS,
    "scenarios": t3arr,
  }
  result["tier4"] = %*{
    "gpu_resource_ledger": {
      "found": s.tier4.found,
      "live_bytes": s.tier4.liveBytes,
      "peak_bytes": s.tier4.peakBytes,
      "live_resources": s.tier4.liveResources,
      "anomalies": s.tier4.anomalies,
      "verdict": s.tier4.verdict,
    }
  }

# ---------- main ----------

proc main() =
  if paramCount() < 1:
    quit("usage: summarize_run <run_dir> [soak_ms] [vg_s]", 2)
  let runDir = paramStr(1).absolutePath
  let soakMs = if paramCount() >= 2: parseInt(paramStr(2)) else: 300_000
  let vgS    = if paramCount() >= 3: parseInt(paramStr(3)) else: 20

  if not dirExists(runDir):
    quit("run dir not found: " & runDir, 2)

  var s = gatherMetadata(runDir, soakMs, vgS)
  s.tier1 = parseTier1(runDir / "tier1_idle.log")
  s.tier2 = parseTier2(runDir / "tier2_soak.log")
  s.tier3 = parseTier3(runDir)
  s.tier4 = parseTier4(runDir / "tier4_gpu.log")

  let md = renderMarkdown(s)
  writeFile(runDir / "SUMMARY.md", md)
  writeFile(runDir / "results.json", $toJson(s).pretty)

  echo "[summarize] wrote ", runDir / "SUMMARY.md"
  echo "[summarize] wrote ", runDir / "results.json"

when isMainModule:
  main()
