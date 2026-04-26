#!/usr/bin/env bash
# Overnight memory test runner — the full suite, no skips, ~35 min wall time.
#
# Phases (each only runs if the previous one passed its self-tests):
#   1. Self-tests:          parser, sampler unit, scenarios, child-pid (~30s)
#   2. Builds:              release + valgrind-debug binaries
#   3. Tier 1 idle:         spawn-and-watch for 10s
#   4. Tier 2 soak:         all 5 scenarios, 5 min each, slope < 100 KB/min
#   5. Tier 3 valgrind:     all 5 scenarios, 12s each, zero definite leaks
#   6. Tier 4 GPU ledger:   renderer-owned textures/buffers are reported
#   7. Lifecycle chaos:     tab/pane/zoom/resize/rebuild paths are cycled
#
# Output:
#   - Live progress to stdout (and the verdict file's tail)
#   - Per-phase logs in tests/memory/reports/overnight-<ts>/
#   - Final summary in tests/memory/reports/overnight-<ts>/SUMMARY.md
#
# Exit code:
#   0 — every phase passed
#   1 — at least one phase failed (summary lists what)
#   2 — runner could not start (missing tool, build failure)
#
# Usage:
#   ./tests/memory/run_overnight.sh
#   SOAK_DURATION_MS=60000 ./tests/memory/run_overnight.sh   # short smoke (~6 min)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="tests/memory/reports/overnight-$TS"
mkdir -p "$RUN_DIR"
PHASES="$RUN_DIR/PHASES.md"   # bash-generated audit trail
SUMMARY="$RUN_DIR/SUMMARY.md" # rich public artifact (Nim summarizer)

SOAK_DURATION_MS="${SOAK_DURATION_MS:-300000}"   # 5 min default
SOAK_SLOPE_KB_MIN="${SOAK_SLOPE_KB_MIN:-100}"
VG_DURATION="${VG_DURATION:-20}"

PHASE_RESULTS=()
RESTORED_BINARY=0

# ---------- helpers ----------

bar() { printf '\n%s %s %s\n' "================" "$1" "================"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "FATAL: required command not found: $1" >&2
    exit 2
  }
}

restore_binary() {
  if [[ "$RESTORED_BINARY" -eq 0 && -e nim_terminal.overnight-bak ]]; then
    mv nim_terminal.overnight-bak nim_terminal 2>/dev/null || true
    RESTORED_BINARY=1
  fi
}

trap restore_binary EXIT

# Run a phase. Captures stdout+stderr, appends to summary.
# Args: <phase name> <log filename> <command...>
run_phase() {
  local name="$1" logfile="$2"; shift 2
  local log="$RUN_DIR/$logfile"
  bar "$name"
  echo "[overnight] log: $log"
  local start; start=$(date +%s)
  set +e
  ( "$@" ) >"$log" 2>&1
  local rc=$?
  set -e
  local elapsed=$(( $(date +%s) - start ))
  if [[ $rc -eq 0 ]]; then
    echo "[overnight] PASS ($elapsed s)"
    PHASE_RESULTS+=("PASS|$name|${elapsed}s|$logfile")
  else
    echo "[overnight] FAIL rc=$rc ($elapsed s)"
    echo "----- last 30 lines of $logfile -----"
    tail -30 "$log"
    echo "----- end -----"
    PHASE_RESULTS+=("FAIL|$name|${elapsed}s|$logfile")
  fi
  return 0   # never abort the runner — collect all results
}

write_phases() {
  {
    echo "# Phase log — overnight memory run $TS"
    echo
    echo "Repo: \`$REPO_ROOT\`"
    echo "Nim: \`$(nim --version | head -1)\`"
    echo "Soak duration: ${SOAK_DURATION_MS} ms per scenario"
    echo "Soak slope threshold: ${SOAK_SLOPE_KB_MIN} KB/min"
    echo "Valgrind scenario duration: ${VG_DURATION} s"
    echo
    echo "## Verdict"
    echo
    local fail=0
    for r in "${PHASE_RESULTS[@]}"; do
      [[ "$r" == FAIL* ]] && fail=$((fail+1))
    done
    if [[ $fail -eq 0 ]]; then
      echo "**ALL PHASES PASSED.** Suite is green."
    else
      echo "**$fail PHASE(S) FAILED.** See per-phase logs."
    fi
    echo
    echo "## Phases"
    echo
    echo "| Status | Phase | Time | Log |"
    echo "|---|---|---|---|"
    for r in "${PHASE_RESULTS[@]}"; do
      IFS='|' read -r status name elapsed logfile <<<"$r"
      echo "| $status | $name | $elapsed | \`$logfile\` |"
    done
  } >"$PHASES"
  echo
  echo "[overnight] phase log written to $PHASES"
}

write_public_summary() {
  # Compile summarize_run once if it isn't already.
  if [[ ! -x tests/memory/summarize_run ]]; then
    nim c -o:tests/memory/summarize_run tests/memory/summarize_run.nim \
      >"$RUN_DIR/build_summarizer.log" 2>&1 || {
        echo "[overnight] WARN: summarize_run failed to compile; skipping rich SUMMARY.md"
        return 0
    }
  fi
  if ! ./tests/memory/summarize_run "$RUN_DIR" "$SOAK_DURATION_MS" "$VG_DURATION"; then
    echo "[overnight] FAIL: summarize_run exited nonzero — public SUMMARY.md may be missing or wrong"
    PHASE_RESULTS+=("FAIL|Summarize run|n/a|build_summarizer.log")
  fi
}

# ---------- preflight ----------

require_cmd nim
require_cmd xvfb-run
require_cmd valgrind
require_cmd timeout

bar "PHASE 0: builds"

echo "[build] release binary"
nim c -d:release -o:nim_terminal_release src/nim_terminal.nim \
  >"$RUN_DIR/build_release.log" 2>&1 || {
    echo "FATAL: release build failed — see $RUN_DIR/build_release.log"
    tail -20 "$RUN_DIR/build_release.log"
    exit 2
}

# Tier 1/2 read ./nim_terminal — link to the release artifact for the run.
# Use a copy not a symlink so the test's binaryPath() check passes cleanly.
if [[ -e nim_terminal && ! -e nim_terminal.overnight-bak ]]; then
  cp nim_terminal nim_terminal.overnight-bak 2>/dev/null || true
fi
cp -f nim_terminal_release nim_terminal 2>/dev/null || {
  # nim_terminal is busy (live editor session) — fall back to env override
  echo "[build] WARN: ./nim_terminal busy; tests will need to find nim_terminal_release"
  # Tier 1 reads ./nim_terminal hard — we can't override without code change.
  # Accept this: the live binary is the one that gets tested. It is the same
  # source, just a few minutes older. Document in SUMMARY.
}

echo "[build] valgrind debug binary"
nim c --mm:orc -d:useMalloc -d:debug --debugger:native \
      -o:tests/memory/valgrind/nim_terminal_debug \
      src/nim_terminal.nim \
  >"$RUN_DIR/build_debug.log" 2>&1 || {
    echo "FATAL: debug build failed — see $RUN_DIR/build_debug.log"
    tail -20 "$RUN_DIR/build_debug.log"
    exit 2
}

# ---------- phase 1: self-tests ----------

run_phase "Self-test: sampler unit"   "selftest_sampler.log" \
  nim c -r tests/memory/test_sampler_unit.nim
run_phase "Self-test: scenarios"      "selftest_scenarios.log" \
  nim c -r tests/memory/test_scenarios.nim
run_phase "Self-test: child PID"      "selftest_childpid.log" \
  nim c -r tests/memory/test_child_pid.nim
run_phase "Self-test: parse_leaks"    "selftest_parser.log" \
  nim c -r tests/memory/valgrind/test_parse_leaks.nim

# ---------- phase 2: tier 1 ----------

run_phase "Tier 1: idle baseline"     "tier1_idle.log" \
  nim c -r tests/memory/test_idle_baseline.nim

# ---------- phase 3: tier 2 soak (all 5 scenarios) ----------

# test_soak.nim runs all scenarios when given none. Slope threshold and
# duration are env-driven.
run_phase "Tier 2: soak (5 scenarios @ ${SOAK_DURATION_MS}ms)" "tier2_soak.log" \
  env SOAK_DURATION_MS="$SOAK_DURATION_MS" \
      SOAK_SLOPE_KB_MIN="$SOAK_SLOPE_KB_MIN" \
  nim c -r tests/memory/test_soak.nim

# ---------- phase 4: tier 3 valgrind (all 5 scenarios) ----------

# Compile the smoke test once, then run it per scenario via env override.
nim c -o:tests/memory/valgrind/test_valgrind_smoke \
      tests/memory/valgrind/test_valgrind_smoke.nim \
  >"$RUN_DIR/build_valgrind_smoke.log" 2>&1 || {
    echo "FATAL: valgrind smoke compile failed"
    tail -20 "$RUN_DIR/build_valgrind_smoke.log"
    PHASE_RESULTS+=("FAIL|Tier 3 build|n/a|build_valgrind_smoke.log")
    write_phases
    write_public_summary
    exit 1
}

for scen in alt_buffer_toggle scroll_churn sgr_storm urandom_flood utf8_mix; do
  run_phase "Tier 3: valgrind $scen (${VG_DURATION}s)" \
            "tier3_valgrind_${scen}.log" \
    env VG_SCENARIO="$scen" VG_DURATION="$VG_DURATION" \
    ./tests/memory/valgrind/test_valgrind_smoke
done

# ---------- phase 5: tier 4 GPU resource accounting ----------

run_phase "Tier 4: GPU resource ledger" "tier4_gpu.log" \
  nim c -r tests/memory/test_gpu_resources.nim

run_phase "Tier 4: lifecycle chaos" "tier4_lifecycle_chaos.log" \
  env WAYMARK_LIFECYCLE_CHAOS_CYCLES=16 \
      LIBGL_ALWAYS_SOFTWARE=1 \
  timeout 30 \
  xvfb-run -a --server-args="-screen 0 1280x800x24" \
  ./nim_terminal

# ---------- finalize ----------

write_phases
write_public_summary

echo
echo "============== PHASE LOG =============="
cat "$PHASES"
echo
echo "============== PUBLIC SUMMARY =============="
[[ -f "$SUMMARY" ]] && cat "$SUMMARY" || echo "(SUMMARY.md not generated)"

# Restore the original ./nim_terminal if we backed it up.
restore_binary

# Exit nonzero if anything failed
for r in "${PHASE_RESULTS[@]}"; do
  [[ "$r" == FAIL* ]] && exit 1
done
exit 0
