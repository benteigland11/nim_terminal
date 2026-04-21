## Pseudo-terminal host: platform-neutral orchestration.
##
## This widget provides the *orchestration* of running a child process
## attached to a pseudo-terminal, expressed against a `PtyBackend` concept
## that any platform (POSIX, Windows ConPTY, in-memory fake) can implement.
##
## The widget itself performs no syscalls and no FFI — it defines the
## protocol, the state machine, and a handful of pure helpers. A concrete
## backend is supplied by the caller and wired in at spawn time.
##
## See `examples/example_usage.nim` for a POSIX implementation of the
## backend using `posix_openpt` / `grantpt` / `unlockpt` / `ptsname` /
## `fork` / `setsid` / `dup2` / `execvp`.
##
## Error signalling
## ----------------
## Backends signal read outcomes with the return value of `readBytes`:
##   * `n > 0`  — number of bytes read
##   * `n == 0` — end of file (child closed the slave / pty hangup)
##   * `n < 0`  — nonblocking fd would have blocked (no data available)
##
## Backends may raise `PtyError` for unrecoverable failures.
##
## Exit status encoding
## --------------------
## `waitExit` returns whatever the backend reports. The helpers
## `encodeExitNormal` and `encodeExitSignaled` provide the conventional
## POSIX-style encoding (exit code in low byte, signalled termination as
## `128 + signum`) so multiple backends can agree on a shape without this
## widget owning the libc-specific macros.

type
  PtyError* = object of CatchableError
    ## Raised by backends for unrecoverable PTY failures.

  PtyBackend* = concept b
    ## Contract a pseudo-terminal backend must satisfy.
    ##
    ## `handle` and `pid` are opaque integers interpreted by the backend
    ## (on POSIX they are a file descriptor and a process id; on Windows
    ## ConPTY they would be indices into a backend-owned handle table).
    ##
    ## Implementations must be thread-safe only to the degree the caller
    ## needs — this widget uses each backend from a single thread.
    ptyOpen(b) is tuple[handle: int, slaveId: string]
    ptySetSize(b, int, int, int)
    ptyForkExec(b, string, string, openArray[string], string) is int
    ptyRead(b, int, var openArray[byte]) is int
    ptyWrite(b, int, openArray[byte]) is int
    ptySignal(b, int, int)
    ptyWait(b, int) is int
    ptyClose(b, int)

  PtyHost*[B] = ref object
    ## A running child attached to a pseudo-terminal.
    ##
    ## Generic over the backend type so that no virtual dispatch is needed
    ## and the backend's own state (handle tables, allocators) is carried
    ## along with the host.
    backend*: B
    handle*: int
    pid*: int
    rows*, cols*: int
    closed*: bool

# ---------------------------------------------------------------------------
# Exit status helpers (pure, usable by any backend)
# ---------------------------------------------------------------------------

func encodeExitNormal*(code: int): int =
  ## Encode a normal-exit status code. Masks to the low byte since POSIX
  ## `WEXITSTATUS` is 8-bit.
  code and 0xff

func encodeExitSignaled*(signum: int): int =
  ## Encode a signal-terminated status using the conventional `128 + sig`.
  128 + signum

func exitedBySignal*(status: int): bool =
  ## True if `status` was produced by `encodeExitSignaled`.
  status >= 128 and status < 256

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

proc spawn*[B](
    backend: B,
    program: string,
    args: openArray[string] = [],
    cwd: string = "",
    rows: int = 24,
    cols: int = 80,
): PtyHost[B] =
  ## Allocate a PTY via `backend`, set its size, then fork+exec `program`
  ## attached to the slave end. `args` must NOT include argv[0]; the
  ## backend is expected to prepend `program` itself.
  let (h, slaveId) = backend.ptyOpen()
  backend.ptySetSize(h, rows, cols)
  var argv = newSeqOfCap[string](args.len)
  for a in args: argv.add a
  let pid = backend.ptyForkExec(slaveId, program, argv, cwd)
  PtyHost[B](
    backend: backend,
    handle: h,
    pid: pid,
    rows: rows,
    cols: cols,
    closed: false,
  )

proc close*[B](p: PtyHost[B]) =
  ## Close the master end. Does not wait for the child — call `waitExit`
  ## first if you need the exit status.
  if p.closed: return
  p.backend.ptyClose(p.handle)
  p.closed = true

proc alive*[B](p: PtyHost[B]): bool = not p.closed
  ## Whether the master end is still open.

# ---------------------------------------------------------------------------
# IO
# ---------------------------------------------------------------------------

proc read*[B](p: PtyHost[B], buf: var openArray[byte]): int =
  ## Read up to `buf.len` bytes from the master. Returns the number of
  ## bytes read, 0 on EOF, or a negative value if a nonblocking backend
  ## would have blocked. Returns 0 if the host is already closed.
  if p.closed or buf.len == 0: return 0
  p.backend.ptyRead(p.handle, buf)

proc readString*[B](p: PtyHost[B], maxBytes: int = 4096): string =
  ## Convenience wrapper that returns bytes as a string. Empty string on
  ## EOF or would-block.
  if maxBytes <= 0: return ""
  var buf = newSeq[byte](maxBytes)
  let n = p.read(buf)
  if n <= 0: return ""
  result = newStringOfCap(n)
  for i in 0 ..< n: result.add char(buf[i])

proc write*[B](p: PtyHost[B], data: openArray[byte]): int =
  ## Write bytes to the master. Returns the number of bytes accepted
  ## (may be less than `data.len`). Returns 0 if the host is closed.
  if p.closed or data.len == 0: return 0
  p.backend.ptyWrite(p.handle, data)

proc writeString*[B](p: PtyHost[B], s: string): int =
  ## Convenience wrapper that writes a string.
  if s.len == 0: return 0
  var bs = newSeq[byte](s.len)
  for i, c in s: bs[i] = byte(c)
  p.write(bs)

# ---------------------------------------------------------------------------
# Control
# ---------------------------------------------------------------------------

proc resize*[B](p: PtyHost[B], cols, rows: int) =
  ## Notify the child of a new terminal size. No-op if closed.
  if p.closed: return
  if rows <= 0 or cols <= 0:
    raise newException(PtyError, "resize: rows and cols must be positive")
  p.backend.ptySetSize(p.handle, rows, cols)
  p.rows = rows
  p.cols = cols

proc kill*[B](p: PtyHost[B], signum: int) =
  ## Send `signum` to the child. No-op if closed. The numeric value of
  ## `signum` is backend-defined (e.g. POSIX `SIGTERM == 15`).
  if p.closed or p.pid <= 0: return
  p.backend.ptySignal(p.pid, signum)

proc waitExit*[B](p: PtyHost[B]): int =
  ## Block until the child exits and return its status as encoded by the
  ## backend. Returns -1 if the pid is not known.
  if p.pid <= 0: return -1
  p.backend.ptyWait(p.pid)
