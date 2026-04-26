## Parse a valgrind --leak-check=full log into a structured verdict.
##
## Valgrind emits a fixed-format LEAK SUMMARY block once per pid. We pull
## the four kinds we care about and the ERROR SUMMARY count. The numbers
## are byte counts; counting bytes is more useful than counting blocks
## because a single leaked block can be tiny or huge.

import std/[strutils, os, parseutils, options]

type
  LeakKind* = enum
    lkDefinite, lkIndirect, lkPossible, lkReachable, lkSuppressed

  LeakSummary* = object
    bytes*: array[LeakKind, int]
    blocks*: array[LeakKind, int]
    errorCount*: int      ## from "ERROR SUMMARY: N errors"
    suppressedCount*: int ## from "ERROR SUMMARY: ... (suppressed: K from L)"
    pid*: int
    parsed*: bool         ## true if we actually found a LEAK SUMMARY

const kindLabel*: array[LeakKind, string] = [
  "definitely lost",
  "indirectly lost",
  "possibly lost",
  "still reachable",
  "suppressed",
]

func newLeakSummary*(): LeakSummary = discard

proc extractInt(s: string): int =
  ## Pull the first integer out of a string, ignoring commas.
  var stripped = ""
  for ch in s:
    if ch.isDigit: stripped.add(ch)
    elif ch == ',' or ch == ' ': discard
    elif stripped.len > 0: break
  if stripped.len == 0: return 0
  discard parseInt(stripped, result)

proc parseLeakLine(line: string, sum: var LeakSummary) =
  ## Match lines like:  "==12345==    definitely lost: 1,024 bytes in 3 blocks"
  for k in LeakKind:
    let label = kindLabel[k]
    let idx = line.find(label & ":")
    if idx < 0: continue
    let tail = line[idx + label.len + 1 .. ^1]
    let bytesIdx = tail.find("bytes")
    let blocksIdx = tail.find("blocks")
    if bytesIdx > 0:
      sum.bytes[k] = extractInt(tail[0 ..< bytesIdx])
    if blocksIdx > bytesIdx and bytesIdx > 0:
      sum.blocks[k] = extractInt(tail[bytesIdx + len("bytes") ..< blocksIdx])
    return

proc parseErrorSummary(line: string, sum: var LeakSummary) =
  let idx = line.find("ERROR SUMMARY:")
  if idx < 0: return
  let tail = line[idx + len("ERROR SUMMARY:") .. ^1]
  sum.errorCount = extractInt(tail)
  let supIdx = tail.find("suppressed:")
  if supIdx >= 0:
    sum.suppressedCount = extractInt(tail[supIdx + len("suppressed:") .. ^1])

proc parsePid(line: string): Option[int] =
  ## Pull the pid out of a "==PID==" prefix, if present.
  if not line.startsWith("=="): return none(int)
  let endIdx = line.find("==", 2)
  if endIdx < 0: return none(int)
  let inside = line[2 ..< endIdx]
  var pid: int
  if parseInt(inside, pid) > 0:
    return some(pid)
  none(int)

proc parseValgrindLog*(path: string): LeakSummary =
  result = newLeakSummary()
  if not fileExists(path):
    raise newException(IOError, "valgrind log not found: " & path)
  var sawLeak = false
  for raw in lines(path):
    let line = raw
    if not result.parsed:
      let pid = parsePid(line)
      if pid.isSome: result.pid = pid.get
    if line.contains("LEAK SUMMARY:"):
      sawLeak = true
      continue
    if sawLeak:
      parseLeakLine(line, result)
    if line.contains("ERROR SUMMARY:"):
      parseErrorSummary(line, result)
  result.parsed = sawLeak

func definiteLostBytes*(s: LeakSummary): int = s.bytes[lkDefinite]
func indirectLostBytes*(s: LeakSummary): int = s.bytes[lkIndirect]
func possibleLostBytes*(s: LeakSummary): int = s.bytes[lkPossible]
func reachableBytes*(s: LeakSummary): int = s.bytes[lkReachable]

func render*(s: LeakSummary): string =
  result = "valgrind leak summary (pid " & $s.pid & ")\n"
  for k in LeakKind:
    result.add "  " & kindLabel[k] & ": " & $s.bytes[k] & " bytes in " &
               $s.blocks[k] & " blocks\n"
  result.add "  errors: " & $s.errorCount & " (suppressed " &
             $s.suppressedCount & ")\n"

when isMainModule:
  if paramCount() < 1:
    quit("usage: parse_leaks <valgrind.log>", 2)
  let s = parseValgrindLog(paramStr(1))
  echo render(s)
  if not s.parsed:
    quit("no LEAK SUMMARY found in log", 3)
  if s.definiteLostBytes > 0:
    quit("definite leak: " & $s.definiteLostBytes & " bytes", 1)
