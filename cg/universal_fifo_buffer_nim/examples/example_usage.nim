## Example usage of Fifo Buffer.
##
## This file must compile and run cleanly with no user input,
## no network calls, and no external services. Use fake/hardcoded
## data to demonstrate the API.

import fifo_buffer_lib
import std/options

# Create a buffer with capacity for 1024 bytes
let b = newFifoBuffer(1024)

# Write some bytes
discard b.writeByte(byte('H'))
discard b.writeByte(byte('i'))

# Write a string
discard b.writeString(" there!")

# Check current length
doAssert b.len == 9

# Peek at the first byte without consuming
let p = b.peekByte(0)
doAssert p.isSome and p.get() == byte('H')

# Read everything back into a buffer
var outBuf = newSeq[byte](b.len)
let n = b.read(outBuf)
doAssert n == 9
doAssert cast[string](outBuf) == "Hi there!"

# Check it's empty now
doAssert b.isEmpty

echo "All fifo-buffer examples passed."
