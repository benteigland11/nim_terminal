## Example usage of PTY Async.

import pty_async_lib

# 1. Define a backend (mock loopback for example)
type MockB = ref object
proc ptyRead(b: MockB, h: int, buf: var openArray[byte]): int = 0
proc ptyWrite(b: MockB, h: int, data: openArray[byte]): int = data.len

# 2. Setup orchestrator
let backend = MockB()
let p = newAsyncPty(backend, 1)

# 3. Queue some data
let message = "Hello Shell"
discard p.send(message.toOpenArrayByte(0, message.high))

# 4. Flush in your main loop
let written = p.flush()
doAssert written == 11
doAssert p.queueLen == 0

echo "Pty-async example verified."
