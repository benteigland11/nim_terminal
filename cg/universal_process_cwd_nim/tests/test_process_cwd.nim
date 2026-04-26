import std/unittest
import std/options
import process_cwd_lib

suite "Process CWD":
  test "cwdLabel uses the last path segment":
    check cwdLabel("home/example/project") == "project"
    check cwdLabel("home/example/project/") == "project"
    check cwdLabel("") == ""

  test "invalid pid has no cwd":
    check processCwd(0).isNone
    check processCwd(-1).isNone

  test "missing proc root has no cwd":
    check processCwd(1, "/definitely/missing/proc/root").isNone
