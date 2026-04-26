## Fixed-capacity FIFO byte buffer.
##
## A thread-safe-ready (caller synchronized) ring buffer for bytes.
## Useful for managing communication backpressure, accumulation,
## and rate-limiting.
##
## This widget is pure logic: it manages a segment of memory and
## provides read/write/peek operations.

import std/options

type
  FifoBuffer* = ref object
    data: seq[byte]
    head: int # Next byte to read
    tail: int # Next slot to write
    count: int
    capacity: int

func newFifoBuffer*(capacity: int): FifoBuffer =
  ## Create a new buffer with the given capacity.
  doAssert capacity > 0
  FifoBuffer(
    data: newSeq[byte](capacity),
    head: 0,
    tail: 0,
    count: 0,
    capacity: capacity
  )

func len*(b: FifoBuffer): int = b.count
func capacity*(b: FifoBuffer): int = b.capacity
func isFull*(b: FifoBuffer): bool = b.count == b.capacity
func isEmpty*(b: FifoBuffer): bool = b.count == 0
func available*(b: FifoBuffer): int = b.capacity - b.count

# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

proc writeByte*(b: FifoBuffer, val: byte): bool =
  ## Write a single byte. Returns false if the buffer is full.
  if b.isFull: return false
  b.data[b.tail] = val
  b.tail = (b.tail + 1) mod b.capacity
  inc b.count
  true

proc write*(b: FifoBuffer, data: openArray[byte]): int =
  ## Write as many bytes as possible from `data`. Returns number of
  ## bytes actually written.
  let toWrite = min(data.len, b.available)
  for i in 0 ..< toWrite:
    discard b.writeByte(data[i])
  toWrite

proc writeString*(b: FifoBuffer, s: string): int =
  ## Write as many bytes as possible from `s`.
  if s.len == 0: return 0
  b.write(s.toOpenArrayByte(0, s.high))

# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

proc readByte*(b: FifoBuffer): Option[byte] =
  ## Read a single byte. Returns none() if empty.
  if b.isEmpty: return none(byte)
  let val = b.data[b.head]
  b.head = (b.head + 1) mod b.capacity
  dec b.count
  some(val)

proc read*(b: FifoBuffer, outBuf: var openArray[byte]): int =
  ## Read as many bytes as possible into `outBuf`. Returns number
  ## of bytes read.
  let toRead = min(outBuf.len, b.count)
  for i in 0 ..< toRead:
    outBuf[i] = b.readByte().get()
  toRead

# ---------------------------------------------------------------------------
# Peeking
# ---------------------------------------------------------------------------

proc peekByte*(b: FifoBuffer, offset: int = 0): Option[byte] =
  ## Look at a byte without consuming it.
  if offset < 0 or offset >= b.count: return none(byte)
  let idx = (b.head + offset) mod b.capacity
  some(b.data[idx])

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

proc clear*(b: FifoBuffer) =
  b.head = 0
  b.tail = 0
  b.count = 0
