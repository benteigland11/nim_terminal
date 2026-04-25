## App-local benchmarks for the terminal pipeline.
##
## These scenarios intentionally live outside widgets because they assemble
## this application's concrete terminal pipeline and current widget set.

import std/[options, strutils]
import benchmark_suite_lib
import ../src/terminal

type MockBackend = ref object
  data: seq[byte]

proc ptyOpen(b: MockBackend): tuple[handle: int, slaveId: string] = (1, "mock")

proc ptyRead(b: MockBackend, h: int, buf: var openArray[byte]): int =
  if b.data.len == 0:
    return 0
  let n = min(buf.len, b.data.len)
  for i in 0 ..< n:
    buf[i] = b.data[i]
  if n > 0:
    for i in 0 ..< b.data.len - n:
      b.data[i] = b.data[i + n]
    b.data.setLen(b.data.len - n)
  n

proc ptyWrite(b: MockBackend, h: int, data: openArray[byte]): int = data.len
proc ptyResize(b: MockBackend, h, r, c: int) = discard
proc ptySignal(b: MockBackend, p, s: int) = discard
proc ptyWait(b: MockBackend, p: int): int = 0
proc ptyClose(b: MockBackend, h: int) = discard
proc ptySetSize(b: MockBackend, h, r, c: int) = discard
proc ptyForkExec(b: MockBackend, s, p: string, a: openArray[string], c: string): int = 123

proc newMockTerminal(rows, cols: int): Terminal =
  result = Terminal(
    backend: nil,
    decoder: newUtf8Decoder(),
    parser: newVtParser(),
    screen: newScreen(cols, rows, 1000),
    inputMode: newInputMode(),
    damage: newDamage(rows),
    selection: newSelection(),
    viewport: newViewport(rows),
    drag: newDragController(rows),
    shortcuts: newShortcutMap(),
    history: newSemanticHistory(),
    activeLink: none(ActiveLink),
  )
  result.async = newAsyncPty[terminal.CurrentBackend](nil, 1)

proc feed(t: Terminal, s: string) =
  t.feedBytes(cast[seq[byte]](s))

func repeatedLine(line: string, count: int): string =
  result = newStringOfCap((line.len + 2) * count)
  for _ in 0 ..< count:
    result.add line
    result.add "\r\n"

let plainPayload = repeatedLine("plain text with numbers 0123456789 and symbols []{}", 80)
let scrollPayload = repeatedLine("scrollback pressure https://example.com/path?q=1", 220)
let linkLine = "docs: https://example.com/reference and https://nim-lang.org/docs/manual.html"

let config = BenchmarkConfig(warmupIterations: 5, iterations: 25, batchSize: 1)

let feedPlain: BenchmarkBody = proc() =
  let t = newMockTerminal(40, 120)
  t.feed plainPayload

let feedScrollback: BenchmarkBody = proc() =
  let t = newMockTerminal(24, 100)
  t.feed scrollPayload

let resizeScreen: BenchmarkBody = proc() =
  let t = newMockTerminal(24, 100)
  t.feed plainPayload
  t.screen.resize(132, 40)
  t.screen.resize(80, 20)

let detectRowLinks: BenchmarkBody = proc() =
  discard detectLinks(linkLine)

let suiteResult = runSuite([
  ("terminal feed plain", feedPlain),
  ("terminal feed scrollback", feedScrollback),
  ("screen resize populated", resizeScreen),
  ("detect row links", detectRowLinks),
], config)

for item in suiteResult.results:
  echo summaryLine(item)

echo ""
echo suiteResult.toCsv().strip()
