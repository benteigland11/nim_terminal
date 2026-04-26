## Unit tests for the valgrind log parser. These run in milliseconds and
## prove the parser handles the leak summary format without needing a real
## valgrind run.

import std/[unittest, os, random, strutils]
import ./parse_leaks
randomize()

const sampleClean = """
==12345== Memcheck, a memory error detector
==12345== HEAP SUMMARY:
==12345==     in use at exit: 0 bytes in 0 blocks
==12345==   total heap usage: 100 allocs, 100 frees, 1,024 bytes allocated
==12345==
==12345== All heap blocks were freed -- no leaks are possible
==12345==
==12345== ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)
"""

const sampleLeaky = """
==99999== LEAK SUMMARY:
==99999==    definitely lost: 1,024 bytes in 4 blocks
==99999==    indirectly lost: 256 bytes in 2 blocks
==99999==      possibly lost: 0 bytes in 0 blocks
==99999==    still reachable: 12,345 bytes in 17 blocks
==99999==         suppressed: 8,192 bytes in 64 blocks
==99999==
==99999== ERROR SUMMARY: 6 errors from 6 contexts (suppressed: 12 from 4)
"""

proc writeTmp(content: string): string =
  result = getTempDir() / ("vg_test_" & $getCurrentProcessId() & "_" &
                           $rand(1_000_000) & ".log")
  writeFile(result, content)

suite "parse_leaks":
  test "clean log has zero definite leaks":
    let p = writeTmp(sampleClean)
    defer: removeFile(p)
    let s = parseValgrindLog(p)
    check s.errorCount == 0
    check s.definiteLostBytes == 0
    check s.suppressedCount == 0

  test "leaky log captures every kind":
    let p = writeTmp(sampleLeaky)
    defer: removeFile(p)
    let s = parseValgrindLog(p)
    check s.parsed
    check s.pid == 99999
    check s.definiteLostBytes == 1024
    check s.indirectLostBytes == 256
    check s.possibleLostBytes == 0
    check s.reachableBytes == 12345
    check s.bytes[lkSuppressed] == 8192
    check s.blocks[lkDefinite] == 4
    check s.blocks[lkIndirect] == 2
    check s.blocks[lkSuppressed] == 64
    check s.errorCount == 6
    check s.suppressedCount == 12

  test "render produces a non-empty multi-line summary":
    let s = parseValgrindLog(writeTmp(sampleLeaky))
    let r = render(s)
    check r.contains("definitely lost: 1024 bytes")
    check r.contains("errors: 6")
    check r.splitLines.len >= 6

  test "missing file raises IOError":
    expect IOError:
      discard parseValgrindLog("/tmp/definitely-not-a-real-path-xyz.log")
