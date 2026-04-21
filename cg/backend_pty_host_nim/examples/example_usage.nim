## Example: implementing `PtyBackend` with a loopback in-memory backend.
##
## This widget defines the *protocol* for a PTY host — the orchestrator
## and the backend concept. Real backends (POSIX `posix_openpt` / `fork`,
## Windows ConPTY) necessarily use FFI and live outside the widget; this
## example instead shows the minimum scaffolding needed to satisfy the
## concept and exercise the API without leaving pure Nim.
##
## The loopback backend routes writes back as reads — useful for unit
## testing consumers of `PtyHost` without spawning real processes.

import pty_host_lib

type
  LoopbackBackend = ref object
    buffer: seq[byte]
    closed: bool
    exitCode: int

proc newLoopbackBackend(exitCode: int = 0): LoopbackBackend =
  LoopbackBackend(exitCode: exitCode)

proc ptyOpen(b: LoopbackBackend): tuple[handle: int, slaveId: string] =
  (1, "/dev/loopback")

proc ptySetSize(b: LoopbackBackend, handle: int, rows, cols: int) = discard

proc ptyForkExec(b: LoopbackBackend, slaveId, program: string,
                 args: openArray[string], cwd: string): int = 1

proc ptyRead(b: LoopbackBackend, handle: int, buf: var openArray[byte]): int =
  if b.buffer.len == 0: return 0
  let n = min(b.buffer.len, buf.len)
  for i in 0 ..< n: buf[i] = b.buffer[i]
  for _ in 0 ..< n: b.buffer.delete(0)
  n

proc ptyWrite(b: LoopbackBackend, handle: int, data: openArray[byte]): int =
  for c in data: b.buffer.add c
  data.len

proc ptySignal(b: LoopbackBackend, pid, signum: int) = discard

proc ptyWait(b: LoopbackBackend, pid: int): int = b.exitCode

proc ptyClose(b: LoopbackBackend, handle: int) =
  b.closed = true

# ---------------------------------------------------------------------------
# Demo: send bytes into the host, read them back, check the exit status.
# ---------------------------------------------------------------------------

let backend = newLoopbackBackend(exitCode = 0)
let host = spawn(backend, "/bin/item", ["alpha", "beta"], rows = 24, cols = 80)

let written = host.writeString("hello loopback\n")
doAssert written == "hello loopback\n".len

let echoed = host.readString(64)
doAssert echoed == "hello loopback\n"

host.resize(120, 40)
doAssert host.cols == 120 and host.rows == 40

let status = host.waitExit()
doAssert status == 0

host.close()
doAssert not host.alive
