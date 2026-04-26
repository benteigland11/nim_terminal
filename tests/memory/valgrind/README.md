# Tier 3 — Valgrind

Drives `nim_terminal` under valgrind's `memcheck` for a single scenario and
asserts no bytes are **definitely lost** or **indirectly lost** in our code.
Third-party noise (Mesa, GLFW, fontconfig, X11, ld) is filtered by
`suppressions.supp`.

## Layout

| File | Role |
|---|---|
| `suppressions.supp` | Pinned-by-library suppressions for known third-party noise. Add to it deliberately, with a date and reason. |
| `run_valgrind.sh` | Wraps a scenario run: stages cfg + script in a temp dir, launches `xvfb-run timeout valgrind nim_terminal_debug`, writes log to `../reports/valgrind-<scenario>-<ts>.log`, prints the log path on success. |
| `parse_leaks.nim` | Parses a valgrind log into a structured `LeakSummary` (bytes + blocks per kind, error counts, pid). |
| `test_parse_leaks.nim` | Unit tests for the parser. Runs in milliseconds. No valgrind needed. |
| `test_valgrind_smoke.nim` | End-to-end: builds debug binary, runs `run_valgrind.sh`, parses the log, asserts zero definite/indirect leaks. Skips cleanly if prerequisites are missing. |

## Build the debug binary

`memcheck` only produces useful Nim output when the build keeps allocations
visible to it: `--mm:orc -d:useMalloc -d:debug --debugger:native`. With
`gc:arc/orc` defaults (jemalloc-style pooling), valgrind reports raw arena
allocations, not the Nim object that owns them.

```bash
nim c --mm:orc -d:useMalloc -d:debug --debugger:native \
      -o:tests/memory/valgrind/nim_terminal_debug \
      src/nim_terminal.nim
```

## Run

```bash
# Parser unit tests (cheap, always run):
nim c -r tests/memory/valgrind/test_parse_leaks.nim

# Smoke (10-30s wall time, runs valgrind):
nim c -r tests/memory/valgrind/test_valgrind_smoke.nim

# Specific scenario, longer duration:
VG_SCENARIO=urandom_flood VG_DURATION=20 \
  ./tests/memory/valgrind/test_valgrind_smoke
```

## Reading the log

The runner prints a path like `../reports/valgrind-alt_buffer_toggle-20260426-013100.log`.
Inspect with:

```bash
nim c -r tests/memory/valgrind/parse_leaks.nim <path-to-log>
```

Or just `less` the raw file — valgrind's stack traces show file:line for
Nim symbols thanks to `--debugger:native`.

## Suppressions policy

- **Suppress by library, never by call site in our code.** Every entry in
  `suppressions.supp` is pinned to `obj:*/lib<thing>.so*`. If a leak originates
  in our `.nim` file and you suppress it, you've hidden a real bug.
- **Date the entry and explain why.** A future contributor needs to be able
  to re-evaluate it.
- **Prefer `match-leak-kinds: definite,possible` over blanket suppressions.**
  `still reachable` from third-party libraries is usually fine to leave un-suppressed
  since the test ignores it anyway.

## Known limits

- **One pid per run.** `nim_terminal` may spawn helper processes (the shell
  child); valgrind is only watching the parent. Helper-process leaks would
  need `--trace-children=yes`, which slows the run further and produces
  multiple LEAK SUMMARY blocks the parser doesn't yet handle.
- **No multi-scenario aggregation.** Each scenario is a separate run. If
  two scenarios pass individually but a leak only appears in interleaved
  sequences, this tier won't catch it. Tier 2 (soak) is what catches that.
- **Suppressions are platform-flavored.** They target Mesa/GLFW/X11 paths
  on Linux. macOS/Windows runs would need their own `.supp`.
