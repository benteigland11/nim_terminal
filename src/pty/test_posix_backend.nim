## Integration smoke test for the POSIX PTY backend.
##
## Spawns real child processes (/bin/echo, /bin/cat, /bin/sh) under a
## pseudo-terminal via posix_backend + backend-pty-host-nim. Exercises
## the full code path: PTY allocation, fork/exec, read, write, resize,
## signal delivery, and exit-status encoding (both normal and signalled
## termination).
##
## Run: nim c -r --path:../../cg/backend_pty_host_nim/src test_posix_backend.nim

import std/[unittest, strutils, posix]
import ../../cg/backend_pty_host_nim/src/pty_host_lib
import posix_backend

suite "POSIX PTY backend":

  test "echo emits its argument to the master":
    let backend = newPosixBackend()
    let p = spawn(backend, "/bin/echo", ["hello", "pty"])
    var collected = ""
    while true:
      let chunk = p.readString(256)
      if chunk.len == 0: break
      collected.add chunk
      if collected.len > 4096: break
    let status = p.waitExit()
    p.close()
    check status == 0
    check "hello pty" in collected

  test "sh -c exit 7 surfaces as status 7":
    let backend = newPosixBackend()
    let p = spawn(backend, "/bin/sh", ["-c", "exit 7"])
    while p.readString(256).len > 0: discard
    let status = p.waitExit()
    p.close()
    check status == 7

  test "cat echoes input after EOF":
    let backend = newPosixBackend()
    let p = spawn(backend, "/bin/cat", [])
    let n = p.writeString("ping\n")
    check n == 5
    discard p.writeString("\x04")  # Ctrl-D, EOF to cat.
    var collected = ""
    while true:
      let chunk = p.readString(256)
      if chunk.len == 0: break
      collected.add chunk
      if collected.len > 4096: break
    discard p.waitExit()
    p.close()
    check "ping" in collected

  test "SIGTERM on long-running child encodes as 128 + SIGTERM":
    let backend = newPosixBackend()
    let p = spawn(backend, "/bin/sh", ["-c", "sleep 30"])
    p.kill(int(SIGTERM))
    let status = p.waitExit()
    p.close()
    check status == 128 + int(SIGTERM)
    check exitedBySignal(status)

  test "resize updates host state without raising":
    let backend = newPosixBackend()
    let p = spawn(backend, "/bin/sh", ["-c", "sleep 0.1"])
    p.resize(120, 40)
    check p.cols == 120 and p.rows == 40
    discard p.waitExit()
    p.close()
