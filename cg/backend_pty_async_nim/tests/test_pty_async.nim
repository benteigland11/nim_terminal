import std/unittest
import ../src/pty_async_lib

type
  MockBackend = ref object
    sent: seq[byte]
    acceptCount: int # How many bytes we'll accept next call

proc ptyRead(b: MockBackend, h: int, buf: var openArray[byte]): int = 0
proc ptyWrite(b: MockBackend, h: int, data: openArray[byte]): int =
  let n = min(data.len, b.acceptCount)
  for i in 0 ..< n: b.sent.add data[i]
  n

suite "pty async":

  test "queue and partial flush":
    let b = MockBackend(sent: @[], acceptCount: 0)
    let p = newAsyncPty(b, 1, queueCap = 100)
    
    discard p.send(cast[seq[byte]]("Hello"))
    check p.queueLen == 5
    
    # Backend accepts 0 bytes
    discard p.flush()
    check p.queueLen == 5
    
    # Backend accepts 2 bytes
    b.acceptCount = 2
    discard p.flush()
    check p.queueLen == 3
    check cast[string](b.sent) == "He"
    
    # Backend accepts rest
    b.acceptCount = 10
    discard p.flush()
    check p.queueLen == 0
    check cast[string](b.sent) == "Hello"
