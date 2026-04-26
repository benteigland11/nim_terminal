# Waymark

A native Nim terminal emulator, assembled from 38 reusable
[Cartograph](https://github.com/benteigland11/Cartograph) widgets.

Building in the open. Expect rough edges.

<!-- DEMO GIF / asciinema cast goes here -->

## What this is

A GPU-rendered terminal written end-to-end in Nim. Every generalizable
piece (VT parser, screen buffer, UTF-8 decoder, glyph atlas, tile
batcher, split-pane tree, tab set, color palette, and dozens more) is a
self-contained widget under `cg/` that can be lifted out and dropped into
any other Nim project.

The terminal is the showcase. The widgets are the point.

## What this proves

- **Memory safety.** A nightly suite (Tier 1 idle baseline, Tier 2 5-min
  soak across 5 scenarios, Tier 3 valgrind under each scenario) produces
  a public `SUMMARY.md` with build SHAs, sample counts, slope thresholds,
  and zero-leak verdicts. See
  [`tests/memory/reports/SUMMARY.md`](tests/memory/reports/SUMMARY.md) and
  [`tests/memory/README.md`](tests/memory/README.md).
- **Composability.** 38 widgets, each independently validated, tested,
  and installable into other projects via `cartograph install`.
- **Performance.** GPU-accelerated rendering through a glyph atlas + tile
  batcher. Microbenchmarks under [`benchmarks/`](benchmarks/).

## Try it

    git clone https://github.com/benteigland11/nim_terminal
    cd nim_terminal

Linux:

    ./scripts/build-linux.sh
    ./nim_terminal

Windows:

    scripts\build-windows.bat
    nim_terminal.exe

Manual build:

    nimble install -y --depsOnly
    nim c -d:release -o:nim_terminal src/nim_terminal.nim

Requires Nim 2.2+, a C compiler toolchain, GLFW/staticglfw dependencies,
and a working OpenGL stack. On Windows, Visual Studio Build Tools or a
MinGW toolchain must be available to Nim. No Cartograph install is needed
to build or run, only to lift widgets out into your own project.

The first terminal starts in `[shell] start_directory` from
`nim_terminal.cfg`, which defaults to `~`. New tabs and panes inherit the
active terminal's current directory. Leave `[shell] program` unset to use
the platform default shell.

## Widgets

All widgets live under `cg/`. The seven below form the spine of the
terminal, in the order data flows through them. The full catalog is
grouped by domain underneath.

### Core

| Widget | Role |
|---|---|
| `data-vt-parser-nim` | DEC VT500 state machine. The heart. |
| `data-vt-commands-nim` | Raw dispatches to semantic `VtCommand`s. |
| `data-screen-buffer-nim` | Cells, cursor, attrs, scrollback, alt buffer. |
| `universal-utf8-decoder-nim` | Streaming UTF-8 with display-width classification. |
| `backend-pty-async-nim` | Non-blocking PTY orchestrator. |
| `universal-glyph-atlas-nim` | Pre-rendered font glyphs in a cacheable atlas. |
| `universal-tile-batcher-nim` | Single-pass batched-quad GPU renderer. |

### All widgets, by domain

<details><summary><b>universal</b> (24) — pure utilities, no domain dependency</summary>

| Widget | Purpose |
|---|---|
| `universal-base64-nim` | Base64 encode/decode via stdlib. |
| `universal-benchmark-suite-nim` | Microbenchmark harness with warmup, batched runs, ns summaries. |
| `universal-color-palette-nim` | Terminal color palette, xterm-256 mapping, RGB utilities. |
| `universal-color-parser-nim` | Parser for X11/xterm color specs (`#RGB`, `rgb:RR/GG/BB`, ...). |
| `universal-damage-tracker-nim` | Mark-and-sweep damage tracker over indexed linear ranges. |
| `universal-drag-controller-nim` | Grid-based drag interaction state machine with auto-scroll. |
| `universal-fifo-buffer-nim` | Fixed-capacity ring buffer for byte streams. |
| `universal-glyph-atlas-nim` | Pre-renders font glyphs into a cacheable atlas. |
| `universal-input-types-nim` | Platform-neutral keyboard/mouse event types. |
| `universal-link-detector-nim` | Pure-Nim scanner for HTTP(S) links and file paths in text. |
| `universal-os-launcher-nim` | Cross-platform "open URL/path in native handler". |
| `universal-path-candidates-nim` | Resolve candidate file paths with anchoring + tilde expansion. |
| `universal-perf-monitor-nim` | High-resolution FPS / frame-latency monitor. |
| `universal-process-cwd-nim` | Resolve a process CWD via procfs and derive compact UI labels. |
| `universal-resource-budget-nim` | Generic soft/hard budget evaluator for bounded systems. |
| `universal-resource-ledger-nim` | Live/peak resource lifetime accounting (count + bytes). |
| `universal-selection-region-nim` | Pure (row, col) selection geometry: anchor, focus, mode. |
| `universal-shortcut-map-nim` | Framework-agnostic keyboard/mouse shortcut lookup. |
| `universal-split-pane-tree-nim` | Pure split-pane tree with active-leaf tracking and H/V splits. |
| `universal-tab-set-nim` | Stable-id tab state: add, activate, rename, close, reorder. |
| `universal-tile-batcher-nim` | Single-pass OpenGL batched-quad renderer. |
| `universal-utf8-decoder-nim` | Streaming UTF-8 decoder; handles splits, overlong, surrogates. |
| `universal-viewport-nim` | Coordinate-mapping viewport for buffers with scrollback. |
| `universal-windows-error-nim` | Translates Win32 error codes / HRESULTs to readable strings. |
| `universal-windows-handle-nim` | RAII wrapper for integer Windows HANDLEs. |

</details>

<details><summary><b>data</b> (11) — terminal-specific state and protocol</summary>

| Widget | Purpose |
|---|---|
| `data-vt-parser-nim` | Paul Williams' DEC VT500 state machine. Bytes in, typed events out. |
| `data-vt-commands-nim` | Translates raw CSI/ESC/OSC/C0 dispatches into semantic `VtCommand`s. |
| `data-vt-reports-nim` | Generator for terminal response strings (DSR, DA, window state). |
| `data-vt-diagnostics-nim` | Bounded ring buffer of recent unknown VT events / mode changes. |
| `data-screen-buffer-nim` | Cells, cursor, attrs, scroll regions, alt buffer, scrollback, resize. |
| `data-input-vt-encoding-nim` | Encodes input events into terminal escape sequences. |
| `data-semantic-history-nim` | OSC 133 shell-integration state machine for command history. |
| `data-terminal-render-attrs-nim` | Resolves SGR + colors into final per-cell render attributes. |
| `data-terminal-theme-nim` | Color scheme / theme representation and management. |
| `data-terminal-output-footprint-nim` | State machine for inline UIs that draw below the cursor. |
| `data-pixel-resource-size-nim` | Byte-size estimation for 2D textures and pixel-backed resources. |

</details>

<details><summary><b>backend</b> (3) — process and PTY orchestration</summary>

| Widget | Purpose |
|---|---|
| `backend-pty-host-nim` | Platform-neutral PTY orchestrator: `PtyBackend` concept + `PtyHost[B]`. |
| `backend-pty-async-nim` | Non-blocking PTY orchestrator with a write queue. |
| `backend-posix-pty-nim` | POSIX PTY child launch environment defaults and diagnostics helpers. |

</details>

<details><summary><b>frontend</b> (1) — windowing and input</summary>

| Widget | Purpose |
|---|---|
| `frontend-glfw-input-nim` | Translates raw GLFW window events into terminal input types. |

</details>

## Architecture

Bytes from the child PTY flow up through the widget stack:

    PTY ──► vt-parser ──► vt-commands ──► screen-buffer ──┐
                                                          │
    GLFW ──► glfw-input ──► input-vt-encoding ──► PTY     │
                                                          ▼
                          glyph-atlas + tile-batcher ◄─ render-attrs
                                       │
                                       ▼
                                  GPU (OpenGL)

`src/` is the project-specific glue that wires widgets together; it
isn't reusable on its own.

## Project-level code

`src/pty/` only selects and configures platform backends. Windows ConPTY
lives in `cg/`; POSIX still needs local FFI for PTY allocation, while its
child launch environment contract lives in `cg/backend_posix_pty_nim`.

## Known issues

See [`NOTES.md`](NOTES.md) for tracked project issues. Notably:

- `std/posix` is missing five PTY primitives, so the POSIX backend keeps a
  small local FFI shim. Those entry points should ultimately land in stdlib
  or a shared nimble package.

## License

MIT. See [LICENSE](LICENSE).
