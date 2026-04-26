#!/usr/bin/env bash
# Pre-push memory check — fast tier only (~30s wall time).
#
# Runs:
#   - parser unit tests (sub-second)
#   - sampler unit tests (sub-second)
#   - scenarios validation (~5s)
#   - child PID regression (~5s)
#   - Tier 1 idle baseline (~15s)
#
# Skips Tier 2 (5+ min) and Tier 3 (3+ min) — those run via run_overnight.sh.
#
# Install as a git pre-push hook:
#   ln -sf ../../tests/memory/pre_push.sh .git/hooks/pre-push
#
# Bypass once (with reason):
#   git push --no-verify   # use sparingly; prefer running run_overnight.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

bar() { printf '\n[pre-push] === %s ===\n' "$1"; }

# Fail closed. A pre-push hook that silently no-ops because xvfb is missing
# is worse than no hook at all — the user assumes pushes are guarded when
# they aren't. If you really need to push from a machine without xvfb, use
# `git push --no-verify` and own the bypass.
if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "[pre-push] FAIL: xvfb-run not installed — memory checks cannot run." >&2
  echo "[pre-push] Install with: sudo dnf install xorg-x11-server-Xvfb" >&2
  echo "[pre-push] Or bypass once: git push --no-verify" >&2
  exit 1
fi
if ! command -v nim >/dev/null 2>&1; then
  echo "[pre-push] FAIL: nim compiler not on PATH." >&2
  exit 1
fi

# Build release binary if missing or stale
if [[ ! -x nim_terminal_release || src/nim_terminal.nim -nt nim_terminal_release ]]; then
  bar "build release binary"
  nim c -d:release -o:nim_terminal_release src/nim_terminal.nim || {
    echo "[pre-push] FAIL: release build broken — push blocked"
    exit 1
  }
fi

# Tier 1 expects ./nim_terminal — link to the release artifact, but only if
# the live ./nim_terminal isn't busy (running editor session).
if [[ ! -e nim_terminal ]] || cp nim_terminal_release nim_terminal 2>/dev/null; then
  : # ./nim_terminal is now the freshly built binary (or didn't exist)
else
  echo "[pre-push] WARN: ./nim_terminal busy (live session?); using existing binary"
fi

FAILED=0
fast_check() {
  local name="$1"; shift
  bar "$name"
  if ! "$@"; then
    echo "[pre-push] FAIL: $name"
    FAILED=$((FAILED+1))
  fi
}

fast_check "sampler unit"   nim c -r tests/memory/test_sampler_unit.nim
fast_check "parser unit"    nim c -r tests/memory/valgrind/test_parse_leaks.nim
fast_check "scenarios"      nim c -r tests/memory/test_scenarios.nim
fast_check "child PID"      nim c -r tests/memory/test_child_pid.nim
fast_check "Tier 1 idle"    nim c -r tests/memory/test_idle_baseline.nim

echo
if [[ $FAILED -eq 0 ]]; then
  echo "[pre-push] ALL FAST CHECKS PASS — push allowed"
  exit 0
else
  echo "[pre-push] $FAILED check(s) FAILED — push blocked"
  echo "[pre-push] (run tests/memory/run_overnight.sh for the full suite)"
  exit 1
fi
