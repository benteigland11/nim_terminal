## POSIX implementation of the `PtyBackend` concept from
## `backend-pty-host-nim`.
##
## The raw PTY syscalls remain project-local because Nim std/posix does not
## expose all allocation primitives yet. Reusable child launch environment
## behavior lives in `cg/backend_posix_pty_nim`.

import std/[os, posix]
import ../../cg/backend_pty_host_nim/src/pty_host_lib
import ../../cg/backend_posix_pty_nim/src/posix_pty_lib

proc posix_openpt(oflag: cint): cint {.importc, header: "<stdlib.h>".}
proc grantpt(fildes: cint): cint {.importc, header: "<stdlib.h>".}
proc unlockpt(fildes: cint): cint {.importc, header: "<stdlib.h>".}
proc ptsname(fildes: cint): cstring {.importc, header: "<stdlib.h>".}
proc ioctl(fd: cint, request: culong, arg: pointer): cint {.
  importc, header: "<sys/ioctl.h>", varargs.}

const
  TiocSwinsz = when hostOS == "linux": culong(0x5414)
               else: culong(0x80087467)
  TiocSctty = when hostOS == "linux": culong(0x540E)
              else: culong(0x20007461)

type
  Winsize = object
    wsRow, wsCol, wsXpixel, wsYpixel: cushort

  PosixBackend* = ref object
    launchEnv: PosixPtyLaunchEnv

proc newPosixBackend*(): PosixBackend =
  var launchEnv = defaultPosixPtyLaunchEnv()
  launchEnv.colorTerm = inheritedOrDefaultColorTerm(getEnv("COLORTERM", ""), launchEnv.colorTerm)
  launchEnv.termProgram = "Waymark"
  launchEnv.childProbePath = getEnv("WAYMARK_CHILD_PROBE_PATH", "")
  PosixBackend(launchEnv: launchEnv)

proc raisePtyErrno(op: string) =
  raise newException(PtyError, op & " failed: " & $strerror(errno))

proc ptyOpen*(b: PosixBackend): tuple[handle: int, slaveId: string] =
  let master = posix_openpt(O_RDWR or O_NOCTTY or O_NONBLOCK)
  if master == -1:
    raisePtyErrno("posix_openpt")
  if grantpt(master) == -1:
    raisePtyErrno("grantpt")
  if unlockpt(master) == -1:
    raisePtyErrno("unlockpt")
  let name = $ptsname(master)
  if name.len == 0:
    raisePtyErrno("ptsname")
  (int(master), name)

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
  if pid == -1:
    raisePtyErrno("fork")
  if pid == 0:
    if setsid() == -1:
      exitnow(127)
    let slave = posix.open(cstring(slaveId), O_RDWR)
    if slave == -1:
      exitnow(127)
    discard ioctl(slave, TiocSctty, nil)
    if dup2(slave, 0.cint) == -1 or dup2(slave, 1.cint) == -1 or
       dup2(slave, 2.cint) == -1:
      exitnow(127)
    if slave > 2:
      discard close(slave)
    applyPosixPtyLaunchEnv(b.launchEnv, cwd, slaveId)
    var argv = @[program]
    for arg in args:
      argv.add arg
    let cargv = allocCStringArray(argv)
    discard execvp(cstring(program), cargv)
    deallocCStringArray(cargv)
    exitnow(127)
  int(pid)

proc ptyRead*(b: PosixBackend, handle: int, buf: var openArray[byte]): int =
  if buf.len == 0:
    return 0
  let readCount = posix.read(cint(handle), addr buf[0], buf.len)
  if readCount >= 0:
    return readCount
  if errno == EAGAIN or errno == EWOULDBLOCK:
    return -1
  if errno == EIO:
    return 0
  raisePtyErrno("read")

proc ptyWrite*(b: PosixBackend, handle: int, data: openArray[byte]): int =
  if data.len == 0:
    return 0
  let writeCount = posix.write(cint(handle), unsafeAddr data[0], data.len)
  if writeCount >= 0:
    return writeCount
  if errno == EAGAIN or errno == EWOULDBLOCK:
    return -1
  raisePtyErrno("write")

proc ptySignal*(b: PosixBackend, pid, signum: int) =
  discard posix.kill(Pid(pid), cint(signum))

proc ptyWait*(b: PosixBackend, pid: int): int =
  var status: cint = 0
  let rc = waitpid(Pid(pid), status, 0)
  if rc == -1:
    return -1
  if WIFEXITED(status):
    return encodeExitNormal(int(WEXITSTATUS(status)))
  if WIFSIGNALED(status):
    return encodeExitSignaled(int(WTERMSIG(status)))
  -1

proc ptyClose*(b: PosixBackend, handle: int) =
  discard close(cint(handle))
