import std/[unittest, options]
import ../src/fifo_buffer_lib

suite "fifo buffer":

  test "basic write and read":
    let b = newFifoBuffer(10)
    check b.writeByte(65) == true
    check b.len == 1
    let val = b.readByte()
    check val.isSome
    check val.get() == 65
    check b.len == 0

  test "fill and overflow":
    let b = newFifoBuffer(3)
    check b.writeByte(1)
    check b.writeByte(2)
    check b.writeByte(3)
    check b.writeByte(4) == false
    check b.isFull

  test "wrapping":
    let b = newFifoBuffer(2)
    discard b.writeByte(1)
    discard b.writeByte(2)
    discard b.readByte()
    check b.writeByte(3) == true # should wrap to idx 0
    check b.readByte().get() == 2
    check b.readByte().get() == 3

  test "write/read slices":
    let b = newFifoBuffer(5)
    check b.write([1'u8, 2, 3]) == 3
    var outBuf = newSeq[byte](2)
    check b.read(outBuf) == 2
    check outBuf == [1'u8, 2]
    check b.len == 1

  test "peek":
    let b = newFifoBuffer(5)
    discard b.writeString("ABC")
    check b.peekByte(0).get() == byte('A')
    check b.peekByte(1).get() == byte('B')
    check b.peekByte(2).get() == byte('C')
    check b.peekByte(3).isNone
