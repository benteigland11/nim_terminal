import std/unittest
import pty_host_lib

# An in-memory backend used for testing. It satisfies the PtyBackend
# concept without any FFI or real syscalls, so these tests run on every
# platform the Nim compiler supports.

type
  FakeBackend = ref object
    openCalls: int
    lastProgram: string
    lastArgs: seq[string]
    lastCwd: string
    writeLog: seq[byte]
    readQueue: seq[seq[byte]]
    resizes: seq[tuple[rows, cols: int]]
    signals: seq[int]
    exitStatus: int
    closedCount: int
    nextHandle: int
    nextPid: int

proc newFake(): FakeBackend =
  FakeBackend(nextHandle: 100, nextPid: 4000)

proc ptyOpen(b: FakeBackend): tuple[handle: int, slaveId: string] =
  inc b.openCalls
  let h = b.nextHandle
  inc b.nextHandle
  (h, "/dev/fake/" & $h)

proc ptySetSize(b: FakeBackend, handle: int, rows, cols: int) =
  b.resizes.add((rows, cols))

proc ptyForkExec(b: FakeBackend, slaveId, program: string,
                 args: openArray[string], cwd: string): int =
  b.lastProgram = program
  b.lastArgs = @[]
  for a in args: b.lastArgs.add a
  b.lastCwd = cwd
  let p = b.nextPid
  inc b.nextPid
  p

proc ptyRead(b: FakeBackend, handle: int, buf: var openArray[byte]): int =
  if b.readQueue.len == 0: return 0
  let chunk = b.readQueue[0]
  b.readQueue.delete(0)
  let n = min(chunk.len, buf.len)
  for i in 0 ..< n: buf[i] = chunk[i]
  n

proc ptyWrite(b: FakeBackend, handle: int, data: openArray[byte]): int =
  for c in data: b.writeLog.add c
  data.len

proc ptySignal(b: FakeBackend, pid, signum: int) =
  b.signals.add signum

proc ptyWait(b: FakeBackend, pid: int): int = b.exitStatus

proc ptyClose(b: FakeBackend, handle: int) =
  inc b.closedCount

func bytesOf(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

suite "spawn":
  test "spawn calls openPty, sets winsize, forks with program + args":
    let b = newFake()
    let p = spawn(b, "/bin/item", ["alpha", "beta"], cwd = "/tmp", rows = 30, cols = 100)
    check b.openCalls == 1
    check b.resizes == @[(30, 100)]
    check b.lastProgram == "/bin/item"
    check b.lastArgs == @["alpha", "beta"]
    check b.lastCwd == "/tmp"
    check p.rows == 30 and p.cols == 100
    check p.alive

  test "default rows/cols land at 24x80":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    check p.rows == 24 and p.cols == 80
    check b.resizes == @[(24, 80)]

suite "read":
  test "readString returns queued bytes then EOF":
    let b = newFake()
    b.readQueue.add bytesOf("hello ")
    b.readQueue.add bytesOf("world")
    let p = spawn(b, "/bin/item")
    var collected = ""
    while true:
      let chunk = p.readString(16)
      if chunk.len == 0: break
      collected.add chunk
    check collected == "hello world"

  test "read into buf returns 0 on empty queue":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    var buf = newSeq[byte](8)
    check p.read(buf) == 0
    check p.eof

  test "readResult classifies data, EOF, and closed":
    let b = newFake()
    b.readQueue.add bytesOf("ok")
    let p = spawn(b, "/bin/item")
    var buf = newSeq[byte](8)
    let first = p.readResult(buf)
    check first.kind == prData
    check first.count == 2
    let second = p.readResult(buf)
    check second.kind == prEof
    check p.eof
    p.close()
    let third = p.readResult(buf)
    check third.kind == prClosed

  test "read after close returns 0 without consulting backend":
    let b = newFake()
    b.readQueue.add bytesOf("unread")
    let p = spawn(b, "/bin/item")
    p.close()
    check p.readString() == ""
    # Queue is untouched because close() short-circuits.
    check b.readQueue.len == 1

suite "write":
  test "writeString sends bytes to backend":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    let n = p.writeString("ping\n")
    check n == 5
    var s = ""
    for c in b.writeLog: s.add char(c)
    check s == "ping\n"

  test "write after close returns 0":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    p.close()
    check p.writeString("dropped") == 0
    check b.writeLog.len == 0

suite "resize":
  test "resize updates dimensions and calls backend":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    p.resize(120, 40)
    check p.cols == 120 and p.rows == 40
    check b.resizes.len == 2  # initial + resize
    check b.resizes[^1] == (40, 120)

  test "resize with non-positive dimensions raises":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    expect PtyError:
      p.resize(0, 10)
    expect PtyError:
      p.resize(10, -1)

suite "kill":
  test "kill forwards signum to backend":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    p.kill(15)
    p.kill(9)
    check b.signals == @[15, 9]

  test "kill is a no-op after close":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    p.close()
    p.kill(15)
    check b.signals.len == 0

suite "waitExit":
  test "waitExit returns backend's reported status":
    let b = newFake()
    b.exitStatus = 7
    let p = spawn(b, "/bin/item")
    check p.waitExit() == 7

suite "close":
  test "close is idempotent and closes handle exactly once":
    let b = newFake()
    let p = spawn(b, "/bin/item")
    check p.alive
    p.close()
    check not p.alive
    p.close()
    p.close()
    check b.closedCount == 1

suite "exit-status helpers":
  test "encodeExitNormal masks to low byte":
    check encodeExitNormal(0) == 0
    check encodeExitNormal(7) == 7
    check encodeExitNormal(256) == 0
    check encodeExitNormal(0x1ff) == 0xff

  test "encodeExitSignaled adds 128":
    check encodeExitSignaled(15) == 143
    check encodeExitSignaled(9) == 137

  test "exitedBySignal classifies correctly":
    check not exitedBySignal(0)
    check not exitedBySignal(127)
    check exitedBySignal(128)
    check exitedBySignal(143)
    check not exitedBySignal(256)
