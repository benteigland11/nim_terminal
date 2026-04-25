import std/unittest
import ../src/os_launcher_lib

suite "os launcher":
  test "API exists":
    # We don't actually launch in tests to avoid popping browsers in CI
    check declared(launchUri)
