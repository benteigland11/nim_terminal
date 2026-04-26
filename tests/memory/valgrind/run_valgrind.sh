#!/usr/bin/env bash
# Run nim_terminal_debug under valgrind for a single scenario.
#
# Usage:
#   run_valgrind.sh <scenario_name> [duration_seconds]
#
# Scenario names match files under ../scenarios/ (e.g. urandom_flood, scroll_churn).
# Duration defaults to 8s; valgrind is ~10-30x slower than native, so keep it short.
#
# Output: writes valgrind log to ../reports/valgrind-<scenario>-<timestamp>.log
# Exit code: 0 if valgrind ran to completion (leak verdict is parser's job).

set -euo pipefail

SCENARIO="${1:-}"
DURATION_S="${2:-8}"

if [[ -z "$SCENARIO" ]]; then
  echo "usage: $0 <scenario_name> [duration_seconds]" >&2
  exit 2
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SCENARIO_DIR="$HERE/../scenarios"
REPORT_DIR="$HERE/../reports"
SUPPRESSIONS="$HERE/suppressions.supp"
DEBUG_BIN="$HERE/nim_terminal_debug"

CFG="$SCENARIO_DIR/$SCENARIO.cfg"
SCRIPT="$SCENARIO_DIR/$SCENARIO.sh"

if [[ ! -x "$DEBUG_BIN" ]]; then
  echo "debug binary missing: $DEBUG_BIN" >&2
  echo "build with: nim c --mm:orc -d:useMalloc -d:debug --debugger:native -o:$DEBUG_BIN $REPO_ROOT/src/nim_terminal.nim" >&2
  exit 3
fi
if [[ ! -f "$CFG" || ! -f "$SCRIPT" ]]; then
  echo "scenario not found: $SCENARIO (looked for $CFG and $SCRIPT)" >&2
  exit 4
fi

mkdir -p "$REPORT_DIR"

# Stage cfg + script into a temp dir, symlink resources/ for fonts.
WORKDIR="$(mktemp -d -t nimterm-vg-XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

cp "$CFG" "$WORKDIR/nim_terminal.cfg"
cp "$SCRIPT" "$WORKDIR/$SCENARIO.sh"
chmod +x "$WORKDIR/$SCENARIO.sh"
ln -s "$REPO_ROOT/resources" "$WORKDIR/resources"

TS="$(date +%Y%m%d-%H%M%S)"
LOG="$REPORT_DIR/valgrind-$SCENARIO-$TS.log"

echo "[run_valgrind] scenario=$SCENARIO duration=${DURATION_S}s log=$LOG"

# We bound the process with `timeout` because nim_terminal does not exit on
# its own. SIGTERM gives the runtime a chance to run shutdown hooks; the
# kill-after grace window lets *valgrind* flush its leak summary even when
# the wrapped program is unresponsive — under heavy scenarios valgrind needs
# 10-20s to walk the heap and write the report. 3s is not enough; 30s is.
set +e
xvfb-run -a --server-args="-screen 0 1280x800x24" \
  timeout --signal=TERM --kill-after=30 "${DURATION_S}s" \
  valgrind \
    --tool=memcheck \
    --leak-check=full \
    --show-leak-kinds=definite,possible \
    --errors-for-leak-kinds=definite \
    --error-exitcode=0 \
    --track-origins=yes \
    --suppressions="$SUPPRESSIONS" \
    --log-file="$LOG" \
    "$DEBUG_BIN" --config "$WORKDIR/nim_terminal.cfg" \
    >/dev/null 2>&1
RC=$?
set -e

# timeout exits 124 on timer-fired-then-clean, 137 on KILL. Both are normal
# here — valgrind's leak summary is what we care about.
case "$RC" in
  0|124|137|143) ;;
  *)
    echo "[run_valgrind] WARN: unexpected exit $RC (log: $LOG)" >&2
    ;;
esac

if [[ ! -s "$LOG" ]]; then
  echo "[run_valgrind] ERROR: empty valgrind log — did valgrind start?" >&2
  exit 5
fi

echo "$LOG"
