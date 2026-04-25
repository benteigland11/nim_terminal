# Nim Terminal Performance Tracker

This tracks the high-leverage Nim improvements for the native terminal:
measurement first, then reusable widget improvements, then app glue that
uses those widgets.

Status markers:

- `[ ]` not started
- `[~]` in progress
- `[x]` done

## Principles

- Benchmark before optimizing hot paths.
- Promote reusable mechanics into `cg/` when they would improve across
  projects, not only because this app hardcodes them.
- Keep platform/window/GL context wiring in `src/` app glue.
- Validate widget changes with `cartograph validate` before checkin.
- Verify performance-sensitive rendering changes empirically on target
  hardware before checkin.

## Phase 1 - Measurement

- `[x]` Create `universal-benchmark-suite-nim`.
  - Generic framing: deterministic microbenchmark runner with warmups,
    iterations, summary stats, and machine-readable output.
  - Why widget: every Nim widget with hot paths benefits from the same
    repeatable benchmark harness.
  - First consumers: terminal pipeline, screen buffer, link detection,
    renderer batching.

- `[x]` Add app-local terminal benchmark entry points.
  - Glue only: benchmark scenarios that assemble this terminal's specific
    parser, screen, PTY-free feed path, and renderer fixtures.
  - Initial scenarios:
    - parser bytes to screen mutations
    - scrollback-heavy writes
    - resize and scroll-region operations
    - row link detection
    - tile batch construction

## Phase 2 - Hot-Path Caches

- `[ ]` Create `universal-row-derived-cache-nim`.
  - Generic framing: cache derived metadata for indexed text rows with
    explicit invalidation by row id/version.
  - Why widget: starts small, improves with iteration across links, search
    hits, diagnostics, syntax spans, and annotations.

- `[ ]` Use row-derived cache for terminal link detection.
  - Glue only: derive row text from the screen buffer and cache
    `DetectedLink` spans per absolute row.
  - Target behavior: mouse movement should only hit cached spans unless
    the row changed.

## Phase 3 - Damage Precision

- `[ ]` Improve `universal-damage-tracker-nim` with dirty ranges/spans.
  - Generic framing: track partial damage over indexed collections, not
    only whole indices.
  - Why widget: useful for renderers, UI surfaces, terminal grids, and
    scanline-style repaint systems.

- `[ ]` Wire dirty spans into terminal rendering.
  - Glue only: map screen mutations, cursor old/new positions, selection
    overlays, and link hover overlays into repaint spans.
  - Target behavior: avoid full-row/full-screen redraws when a smaller
    span is enough.

## Phase 4 - Screen Storage

- `[ ]` Audit `data-screen-buffer-nim` memory layout.
  - Check cell size, attribute size, scrollback copying, resize copying,
    and wide-character representation.

- `[ ]` Improve screen storage if benchmarks justify it.
  - Candidate directions:
    - flatter row storage
    - packed attributes
    - shared/default attribute representation
    - cheaper scrollback movement
  - Keep this inside the existing screen buffer widget unless the
    reusable unit becomes clearly independent.

## Phase 5 - Render-Side Utilities

- `[ ]` Improve `universal-color-palette-nim` with render-friendly lookup.
  - Generic framing: convert indexed/truecolor terminal colors into a
    caller-selected packed/render format with precomputed xterm tables.

- `[ ]` Improve `universal-tile-batcher-nim` if profiling shows upload or
  batching overhead.
  - Candidate directions:
    - persistent buffer support
    - explicit flush thresholds
    - reusable quad instance layout

- `[ ]` Keep OpenGL context, window lifecycle, and font loading in app glue.

## Phase 6 - Compile-Time Leverage

- `[ ]` Investigate table-driven VT dispatch.
  - Generic framing: build lookup tables from declarative transition or
    dispatch specs at compile time.
  - Create a widget only if profiling or maintainability proves the
    generic helper is worth reusing.

- `[ ]` Investigate static feature/backend specialization.
  - Candidate shape: compile-time flags or generic parameters for optional
    terminal capabilities such as semantic history, OSC clipboard,
    hyperlinks, mouse reporting, or color depth.
  - Keep executable policy in app glue.

## Current Slice

1. `[x]` Scaffold `universal-benchmark-suite-nim`.
2. `[x]` Add focused tests and an example benchmark.
3. `[x]` Validate the benchmark widget.
4. `[x]` Add app-local terminal benchmark scenarios.
5. `[x]` Record baseline numbers before optimization work.

## Baselines

### 2026-04-25 - Initial terminal microbenchmarks

Command:

```sh
nim c -r -d:release --mm:orc --nimcache:./.nimcache \
  --path:src \
  --path:cg/universal_benchmark_suite_nim/src \
  benchmarks/terminal_benchmarks.nim
```

Results:

| Scenario | Mean | Median | Min | Max |
|---|---:|---:|---:|---:|
| terminal feed plain | 605.91 us | 603.35 us | 585.99 us | 645.53 us |
| terminal feed scrollback | 1.37 ms | 1.37 ms | 1.34 ms | 1.39 ms |
| screen resize populated | 510.80 us | 509.99 us | 497.29 us | 543.09 us |
| detect row links | 564.60 ns | 561.00 ns | 541.00 ns | 581.00 ns |
