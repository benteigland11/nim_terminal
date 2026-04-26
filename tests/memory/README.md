# Memory tests

Four tiers, each catching a different leak class. Cheaper tiers run on
every PR; slower tiers run nightly or on demand. The current state is
captured in [`reports/MEMORY.md`](reports/MEMORY.md).

| Tier | What it catches | Cost | Cadence | Status |
|------|-----------------|------|---------|--------|
| 1 — idle baseline | Render-loop leaks | ~15s | every PR | **shipped** |
| 2 — workload soak | Allocation growth under load | 5 min × 5 scenarios nightly | nightly | **harness shipped, soak runs nightly** |
| 3 — Valgrind | CPU-side definite/indirect leaks | ~12s smoke / ~30min full | weekly + on-demand | **shipped** (smoke; full sweep nightly) |
| 4 — GPU tracking | Texture / VBO orphans | in-process | every PR (when wired) | deferred (blocked on `gpu_renderer.nim`) |

## Running locally

### Tier 1 — idle baseline

```bash
nim c -r tests/memory/test_idle_baseline.nim
```

Spawns the terminal under `xvfb-run`, sits for 10s, asserts RSS
delta < 1 MB. Currently observes ~127 MB resident with Δ=0KB on this
machine. Use this as the smoke test before/after any change.

### Tier 2 — soak (dev mode = short, CI mode = long)

```bash
# Dev smoke — 30s per scenario, useful to prove the harness drives a
# workload but NOT long enough to produce meaningful slope numbers.
nim c -r tests/memory/test_soak.nim scroll_churn

# Nightly CI soak — 5 minutes per scenario, slope threshold 100 KB/min.
SOAK_DURATION_MS=300000 SOAK_SLOPE_KB_MIN=100 \
    nim c -r tests/memory/test_soak.nim

# All 5 scenarios at default duration:
nim c -r tests/memory/test_soak.nim
```

Available scenarios (each is a `.cfg` + sibling `.sh` pair under
`scenarios/`):

| Scenario | Stresses |
|---|---|
| `urandom_flood`     | VT parser + screen buffer churn under high-throughput byte stream |
| `scroll_churn`      | Scrollback growth + damage tracking |
| `sgr_storm`         | SGR attribute storage |
| `alt_buffer_toggle` | Alt-screen save/restore (vim/htop pattern) |
| `utf8_mix`          | UTF-8 decoder + glyph atlas across CJK / emoji / combining marks |

Environment overrides (all optional):
- `SOAK_DURATION_MS` — per-scenario soak length, default 30000 (dev) — set to 300000 for nightly
- `SOAK_INTERVAL_MS` — RSS sampling interval, default 1000
- `SOAK_WARMUP_MS`   — warmup window before sampling, default 3000
- `SOAK_SLOPE_KB_MIN` — slope threshold, default 100.0 KB/min

### Validating the suite itself

The suite has its own self-tests so a broken harness doesn't masquerade
as a clean app:

```bash
nim c -r tests/memory/test_sampler_unit.nim   # slope math, ASCII chart
nim c -r tests/memory/test_child_pid.nim      # PID resolves to nim_terminal, not Xvfb
nim c -r tests/memory/test_scenarios.nim      # cfg parses, scripts run, regression guards
```

### Tier 3 — Valgrind

```bash
# Parser unit tests (fast):
nim c -r tests/memory/valgrind/test_parse_leaks.nim

# Build the debug binary (required, see note below):
nim c --mm:orc -d:useMalloc -d:debug --debugger:native \
      -o:tests/memory/valgrind/nim_terminal_debug src/nim_terminal.nim

# Smoke run under valgrind (~12s end-to-end):
nim c -r tests/memory/valgrind/test_valgrind_smoke.nim

# Different scenario / longer duration:
VG_SCENARIO=urandom_flood VG_DURATION=20 \
    ./tests/memory/valgrind/test_valgrind_smoke
```

The debug build flags are non-negotiable. Without `-d:useMalloc`, Nim's
slab allocator hides every leak from Valgrind. ORC is required for clean
leak attribution (refc produces too many false positives).

Suppressions are pinned by library (`obj:*/lib<thing>.so*`) so we never
silence leaks originating in our own code. See
[`valgrind/README.md`](valgrind/README.md) for the suppression policy.

## Reports

`reports/MEMORY.md` is the rolling public summary — current baselines,
soak slopes, last Valgrind run. CI rewrites it on each successful run.
That file is the artifact the Nim community will look at.

## Known limitations

- **Linux-only** — sampler reads `/proc/<pid>/status`. macOS would need
  `task_info()` and Windows would need `GetProcessMemoryInfo`. The
  harness deliberately defers cross-OS support until the suite has
  proven its value on Linux.
- **Software OpenGL only** — `LIBGL_ALWAYS_SOFTWARE=1` is set so the
  GPU driver doesn't pollute results with its own allocation patterns.
  GPU-side memory is not visible to this suite (Tier 4 will close
  that gap).
- **xvfb-run dependency** — tests require `xorg-x11-server-Xvfb`
  installed locally and on CI runners.
- **PTY-driven only** — the soak scenarios drive the terminal through
  shell output. Input-side stress (paste-bombs, key-repeat storms) is
  not yet covered.
