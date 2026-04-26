# Waymark Memory Validation — 20260426-025226

Commit: `dab33388e7e6bec2f3680811e44a2264eca80c76`
Host: Linux 6.19.9-200.fc43.x86_64
Nim: `Nim Compiler Version 2.2.10 [Linux: amd64]`
Build:
- release sha256: `1126142077168b63602f67cb671ebe673f29e0458d847de61de7cc224652f89c`
- valgrind debug sha256: `0980e0eaf9e00203eb9dd6089f0a9f1a3653df5bd4e692e242dd1e381015c888`
Runtime: Xvfb 1280x800x24, software OpenGL

Artifacts:
- machine-readable receipt: `results.json`
- phase audit trail: `PHASES.md`
- raw logs: this directory

## Verdict

**PASS**

## Tier 1 — Idle Baseline

| Duration | Samples | Min RSS | Max RSS | Delta | Slope | Verdict |
|---|---:|---:|---:|---:|---:|---|
| 10s | 10 | 175848 KB | 175848 KB | 0 KB | 0.00 KB/min | PASS |

## Tier 2 — Scenario Soak

Threshold: < 100 KB/min over 300s per scenario

| Scenario | Samples | Min RSS | Max RSS | Delta | Slope | Verdict |
|---|---:|---:|---:|---:|---:|---|
| alt_buffer_toggle | 300 | 175692 KB | 175692 KB | 0 KB | 0.00 KB/min | PASS |
| scroll_churn | 300 | 175568 KB | 175568 KB | 0 KB | -0.00 KB/min | PASS |
| sgr_storm | 300 | 175676 KB | 175676 KB | 0 KB | -0.00 KB/min | PASS |
| urandom_flood | 300 | 175744 KB | 175744 KB | 0 KB | 0.00 KB/min | PASS |
| utf8_mix | 300 | 175616 KB | 175616 KB | 0 KB | 0.00 KB/min | PASS |

## Tier 3 — Valgrind

Duration: 20s per scenario.
Suppressions: `tests/memory/valgrind/suppressions.supp` (Mesa/GLFW/fontconfig/X11/ld noise filtered).

> **Honesty caveat.** Valgrind's 10–30× slowdown means `nim_terminal_debug` is killed by the time bound before any scenario workload runs at steady state. Per-scenario rows below mostly measure the same init + early-runtime allocations. Steady-state leak detection is Tier 2's job; Tier 3 catches leaks in startup paths and is the line of defense against `definitely lost` regressions anywhere in the codebase.

| Scenario | Definite | Indirect | Possible | Still Reachable | Suppressed | Errors | Verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| alt_buffer_toggle | 0 B | 0 B | 0 B | 94179 B | 893196 B | 0 | PASS |
| scroll_churn | 0 B | 0 B | 0 B | 94179 B | 893196 B | 0 | PASS |
| sgr_storm | 0 B | 0 B | 0 B | 94179 B | 893196 B | 0 | PASS |
| urandom_flood | 0 B | 0 B | 0 B | 94179 B | 893196 B | 0 | PASS |
| utf8_mix | 0 B | 0 B | 0 B | 94179 B | 893196 B | 0 | PASS |

## Tier 4 — GPU Resource Ledger

Scope: renderer-owned OpenGL textures and tile-batcher buffer, reported from Waymark's internal resource ledger while running under Xvfb/software OpenGL.

| Live Bytes | Peak Bytes | Live Resources | Anomalies | Verdict |
|---:|---:|---:|---:|---|
| 33807540 B | 33807540 B | 5 | 0 | PASS |

## Tier 4b — Lifecycle Chaos

Scope: opt-in Waymark harness mode cycles real tab, pane, zoom, resize, atlas rebuild, render, and GPU ledger paths under Xvfb/software OpenGL.

| Cycles | Max Tabs | Max Panes | GPU Live Bytes | GPU Peak Bytes | Live Resources | Anomalies | Verdict |
|---:|---:|---:|---:|---:|---:|---:|---|
| 16 | 2 | 3 | 33807540 B | 33807540 B | 5 | 0 | PASS |

## Known Limits

- Linux-only `/proc` RSS sampler. macOS/Windows not yet supported.
- Xvfb + software OpenGL runtime (`LIBGL_ALWAYS_SOFTWARE=1`) for determinism.
- Tier 4 tracks Waymark-owned GPU resources through internal GL lifecycle instrumentation; it is not a vendor VRAM profiler.
- Tier 2 slope proves bounded resident growth under these workloads, not formal absence of every possible leak.
- Valgrind runs are time-bounded; under heavy scenarios the wrapped program is killed before completing the workload, so Tier 3 mainly exercises init + early-runtime allocations.
