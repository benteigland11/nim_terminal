## Async PTY Orchestrator.
##
## Wraps a standard PTY host with a non-blocking write queue.
## Ensures that slow PTY writes don't stall the main UI/Logic thread.
##
## This widget is pure orchestration: it manages a queue and
## dispatches to a backend.

import std/options

type
  PtyError* = object of CatchableError

  AsyncReadKind* = enum
    arData
    arWouldBlock
    arEof

  AsyncReadResult* = object
    kind*: AsyncReadKind
    count*: int

  PtyBackend* = concept b
    ptyRead(b, int, var openArray[byte]) is int
    ptyWrite(b, int, openArray[byte]) is int

  # Local minimal FIFO implementation to avoid inter-widget dependency
  Fifo = ref object
    data: seq[byte]
    head, tail, count, capacity: int

  AsyncPty*[B] = ref object
    backend*: B
    handle*: int
    queue: Fifo

# ---------------------------------------------------------------------------
# Internal Fifo
# ---------------------------------------------------------------------------

func newFifo(cap: int): Fifo =
  Fifo(data: newSeq[byte](cap), capacity: cap)

proc write(f: Fifo, data: openArray[byte]): int =
  let toWrite = min(data.len, f.capacity - f.count)
  for i in 0 ..< toWrite:
    f.data[f.tail] = data[i]
    f.tail = (f.tail + 1) mod f.capacity
    inc f.count
  toWrite

proc peekByte(f: Fifo, offset: int): Option[byte] =
  if offset < 0 or offset >= f.count: return none(byte)
  some(f.data[(f.head + offset) mod f.capacity])

proc consume(f: Fifo, n: int) =
  let count = min(n, f.count)
  f.head = (f.head + count) mod f.capacity
  f.count -= count

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func newAsyncPty*[B](backend: B, handle: int, queueCap: int = 16384): AsyncPty[B] =
  AsyncPty[B](
    backend: backend,
    handle: handle,
    queue: newFifo(queueCap)
  )

proc read*[B](p: AsyncPty[B], buf: var openArray[byte]): int =
  ## Non-blocking read from the PTY.
  p.backend.ptyRead(p.handle, buf)

proc readResult*[B](p: AsyncPty[B], buf: var openArray[byte]): AsyncReadResult =
  ## Read and classify the backend result so callers do not have to interpret
  ## the signed integer convention themselves.
  if buf.len == 0:
    return AsyncReadResult(kind: arWouldBlock, count: 0)
  let n = p.backend.ptyRead(p.handle, buf)
  if n > 0:
    AsyncReadResult(kind: arData, count: n)
  elif n < 0:
    AsyncReadResult(kind: arWouldBlock, count: 0)
  else:
    AsyncReadResult(kind: arEof, count: 0)

func send*[B](p: AsyncPty[B], data: openArray[byte]): int =
  ## Queue data to be sent to the PTY. Returns number of bytes queued.
  p.queue.write(data)

proc flush*[B](p: AsyncPty[B]): int =
  ## Attempt to write queued data to the PTY. Returns bytes written.
  if p.queue.count == 0: return 0
  
  # Prepare contiguous buffer for write
  var buf = newSeq[byte](p.queue.count)
  for i in 0 ..< p.queue.count:
    buf[i] = p.queue.peekByte(i).get()
    
  let n = p.backend.ptyWrite(p.handle, buf)
  if n > 0:
    p.queue.consume(n)
    return n
  return 0

func queueLen*(p: AsyncPty): int = p.queue.count
