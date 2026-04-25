## POSIX implementation of the `PtyBackend` concept from
## `backend-pty-host-nim`.
##
## This file is project-local glue (not a widget) because it uses
## `{.importc.}` to reach the four PTY-allocation primitives that
## `std/posix` does not yet export (see NOTES.md, ISSUE-001):
##
##     posix_openpt / grantpt / unlockpt / ptsname
##
## Everything else is stdlib: `fork`, `setsid`, `dup2`, `execvp`,
## `read`, `write`, `kill`, `waitpid`, `ioctl`, `fcntl`, signals.
##
## Once the missing primitives land in `std/posix` (or a nimble
## package wrapping them is published), this file can be promoted to
## a widget and the terminal can install it from the widget library.

import std/posix
import std/os
import ../../cg/backend_pty_host_nim/src/pty_host_lib

# POSIX PTY allocation primitives that std/posix does not expose.
proc posix_openpt(oflag: cint): cint {.importc, header: "<stdlib.h>".}
proc grantpt(fildes: cint): cint {.importc, header: "<stdlib.h>".}
proc unlockpt(fildes: cint): cint {.importc, header: "<stdlib.h>".}
proc ptsname(fildes: cint): cstring {.importc, header: "<stdlib.h>".}
proc ioctl(fd: cint, request: culong, arg: pointer): cint {.
  importc, header: "<sys/ioctl.h>", varargs.}

const
  # TIOCSWINSZ differs by platform: 0x5414 on Linux, 0x80087467 on BSD/Darwin.
  TiocSwinsz = when hostOS == "linux": culong(0x5414)
               else: culong(0x80087467)

type
  Winsize = object
    wsRow, wsCol, wsXpixel, wsYpixel: cushort

  PosixBackend* = ref object
    ## Stateless POSIX PTY backend. Construct with `newPosixBackend()`.

proc newPosixBackend*(): PosixBackend = PosixBackend()

proc raisePtyErrno(op: string) =
  raise newException(PtyError, op & " failed: " & $strerror(errno))

proc ptyOpen*(b: PosixBackend): tuple[handle: int, slaveId: string] =
  let m = posix_openpt(O_RDWR or O_NOCTTY or O_NONBLOCK)
  if m == -1: raisePtyErrno("posix_openpt")
  if grantpt(m) == -1: raisePtyErrno("grantpt")
  if unlockpt(m) == -1: raisePtyErrno("unlockpt")
  let name = $ptsname(m)
  if name.len == 0: raisePtyErrno("ptsname")
  (int(m), name)

proc ptySetSize*(b: PosixBackend, handle: int, rows, cols: int) =
  var ws = Winsize(
    wsRow: cushort(rows), wsCol: cushort(cols),
    wsXpixel: 0, wsYpixel: 0,
  )
  if ioctl(cint(handle), TiocSwinsz, addr ws) == -1:
    raisePtyErrno("ioctl(TIOCSWINSZ)")

proc ptyForkExec*(b: PosixBackend, slaveId, program: string,
                  args: openArray[string], cwd: string): int =
  let pid = fork()
  if pid == -1: raisePtyErrno("fork")
  if pid == 0:
    if setsid() == -1: exitnow(127)
    let slave = posix.open(cstring(slaveId), O_RDWR)
    if slave == -1: exitnow(127)
    if dup2(slave, 0.cint) == -1 or dup2(slave, 1.cint) == -1 or
       dup2(slave, 2.cint) == -1:
      exitnow(127)
    if slave > 2: discard close(slave)
    if cwd.len > 0:
      try: setCurrentDir(cwd) except OSError: discard
    var argv = @[program]
    for a in args: argv.add a
    let cargv = allocCStringArray(argv)
    discard execvp(cstring(program), cargv)
    deallocCStringArray(cargv)
    exitnow(127)
  int(pid)

proc ptyRead*(b: PosixBackend, handle: int, buf: var openArray[byte]): int =
  if buf.len == 0: return 0
  let n = posix.read(cint(handle), addr buf[0], buf.len)
  if n >= 0: return n
  if errno == EAGAIN or errno == EWOULDBLOCK: return -1
  if errno == EIO: return 0   # Linux signals PTY hangup via EIO.
  raisePtyErrno("read")

proc ptyWrite*(b: PosixBackend, handle: int, data: openArray[byte]): int =
  if data.len == 0: return 0
  let n = posix.write(cint(handle), unsafeAddr data[0], data.len)
  if n < 0: raisePtyErrno("write")
  n

proc ptySignal*(b: PosixBackend, pid, signum: int) =
  discard posix.kill(Pid(pid), cint(signum))

proc ptyWait*(b: PosixBackend, pid: int): int =
  var status: cint = 0
  let rc = waitpid(Pid(pid), status, 0)
  if rc == -1: return -1
  if WIFEXITED(status): return encodeExitNormal(int(WEXITSTATUS(status)))
  if WIFSIGNALED(status): return encodeExitSignaled(int(WTERMSIG(status)))
  -1

proc ptyClose*(b: PosixBackend, handle: int) =
  discard close(cint(handle))
