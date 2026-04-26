import std/unittest
import ../src/pty_async_lib

type
  MockBackend = ref object
    sent: seq[byte]
    acceptCount: int # How many bytes we'll accept next call
    reads: seq[int]

proc ptyRead(b: MockBackend, h: int, buf: var openArray[byte]): int =
  if b.reads.len == 0: return 0
  result = b.reads[0]
  b.reads.delete(0)
  if result > 0:
    for i in 0 ..< min(result, buf.len):
      buf[i] = byte('a') + byte(i)
proc ptyWrite(b: MockBackend, h: int, data: openArray[byte]): int =
  let n = min(data.len, b.acceptCount)
  for i in 0 ..< n: b.sent.add data[i]
  n

suite "pty async":

  test "queue and partial flush":
    let b = MockBackend(sent: @[], acceptCount: 0)
    let p = newAsyncPty(b, 1, queueCap = 100)
    
    let message = "Hello"
    discard p.send(message.toOpenArrayByte(0, message.high))
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

  test "readResult classifies backend reads":
    let b = MockBackend(reads: @[3, -1, 0])
    let p = newAsyncPty(b, 1)
    var buf = newSeq[byte](8)
    let data = p.readResult(buf)
    check data.kind == arData
    check data.count == 3
    check buf[0] == byte('a')
    check p.readResult(buf).kind == arWouldBlock
    check p.readResult(buf).kind == arEof
