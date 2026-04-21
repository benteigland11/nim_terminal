# Project Notes & Known Issues

Things we've observed while building `nim_terminal` but aren't solving
today. Each entry records the issue, current workaround, and what a real
fix looks like.

---

## ISSUE-001 — `std/posix` is missing PTY primitives

**Status:** open, workaround in place
**Opened:** 2026-04-20 (Day 2)

### What's missing

Nim's `std/posix` module wraps most of libc's POSIX interface (`fork`,
`dup2`, `execvp`, `read`, `write`, `kill`, `waitpid`, `fcntl`, `ioctl`,
signal constants, etc.) — but it does **not** export the four functions
needed to allocate a pseudo-terminal pair:

    posix_openpt(oflag: cint): cint
    grantpt(fildes: cint): cint
    unlockpt(fildes: cint): cint
    ptsname(fildes: cint): cstring

Nor does it export the `TIOCSWINSZ` ioctl constant (0x5414 on Linux,
0x80087467 on BSD/Darwin), which is needed to tell the child its window
size.

### Why it matters

Cartograph's widget contract forbids `{.importc.}` in widget code —
the correct design principle is that widgets compose from stdlib and
nimble packages, with FFI "one layer down." This means a pure-Nim PTY
widget is **one stdlib patch away from existing**. Until those four
functions are available without `importc`, any widget that wants to
allocate a PTY must either (a) contain FFI (rejected), (b) accept a
backend via dependency injection and punt the FFI to the caller (what
`backend-pty-host-nim` does), or (c) depend on a nimble package that
wraps them.

### Current workaround

The PTY widget is a *protocol + orchestrator* — it defines the
`PtyBackend` concept and the `PtyHost[B]` generic, but performs no
syscalls. A POSIX driver lives as project code in
`src/pty/posix_backend.nim`, outside `cg/`, so it's not subject to the
widget contract. The terminal still works; the widget still validates;
but the POSIX driver can't be shared as a widget in its current form.

### Paths to a real fix

1. **Upstream patch to `std/posix`.** Add the four functions and the
   `TIOCSWINSZ` constants (with the platform-specific values guarded).
   File against `nim-lang/Nim` on GitHub. Small PR (~30 lines). Would
   land in a future Nim release. *This is the right long-term home.*

2. **Publish a standalone nimble package** (e.g. `posix_pty_primitives`)
   containing just those four wrappers. Satisfies Cartograph (FFI is in
   a declared dep, not in widget source) and is available immediately.
   Becomes a shim once (1) lands.

3. **Promote the POSIX backend to a widget** once either (1) or (2) is
   available. At that point the terminal can install it from the widget
   library instead of carrying the code in `src/pty/`.

### When to revisit

After the terminal's core loop is wired end-to-end and the widget set
feels stable. No rush — the workaround is clean and the widget boundary
is already drawn correctly.
