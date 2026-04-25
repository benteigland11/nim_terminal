# nim_terminal

A Nim terminal emulator built from the ground up as reusable
[Cartograph](https://github.com/benteigland11/Cartograph) widgets. Every generalizable piece
— VT parser, screen buffer, UTF-8 decoder, typed VT commands, PTY host
— is a pure-Nim widget that can be lifted out and used in other Nim
projects.

Building in the open. Expect rough edges.

## Why

The long-term goal is a surface that makes it easy to attach terminal
coding agents to a single directory — something closer to a new kind of
IDE than a classic terminal. To get there we're pursuing full xterm-grade
VT compliance as the first milestone. Worst case: we don't finish, and
the Nim ecosystem picks up a handful of useful widgets along the way.

## Widgets

All widgets live under `cg/` and are installable/publishable via Cartograph.
Each is pure Nim, validated, and has tests + a runnable example.

| Widget                          | What it does                                                                           |
|---------------------------------|----------------------------------------------------------------------------------------|
| `data-vt-parser-nim`            | Paul Williams' DEC VT state machine. Bytes in, typed `VtEvent`s out.                   |
| `data-screen-buffer-nim`        | Terminal screen grid: cursor, attrs, scroll regions, alt buffer, scrollback, resize.   |
| `universal-utf8-decoder-nim`    | Streaming UTF-8 decoder with display-width classification (CJK/emoji/combining).       |
| `data-vt-commands-nim`          | Typed translator from raw parser dispatches to semantic `VtCommand` variants.          |
| `backend-pty-host-nim`          | Platform-neutral PTY orchestrator: `PtyBackend` concept + generic `PtyHost[B]`.        |

## Project-level code

Some pieces can't be widgets because they require FFI that isn't yet in
the Nim stdlib (see [Known Issues](#known-issues)). Those live under
`src/` as project-specific glue:

    src/pty/posix_backend.nim   POSIX implementation of PtyBackend using
                                posix_openpt / grantpt / unlockpt / ptsname
                                / ioctl / fork / setsid / dup2 / execvp.

## Known Issues

See [`NOTES.md`](NOTES.md) for tracked project issues — things we've
noticed but aren't solving today. Notably:

- `std/posix` is missing five PTY primitives. We have a workaround
  (project-level FFI in `src/pty/`) but ultimately those entry points
  should land in stdlib or a shared nimble package so widgets can stay
  pure Nim.

## License

MIT. See [LICENSE](LICENSE).
