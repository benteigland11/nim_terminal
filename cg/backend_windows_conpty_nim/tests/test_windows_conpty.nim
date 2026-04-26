import std/unittest
import ../src/windows_conpty_lib

suite "windows conpty backend":
  test "translates common Windows errors":
    check translateErrorCode(267) == "The directory name is invalid (ERROR_DIRECTORY)"
    check translateErrorCode(109) == "The pipe has been ended (ERROR_BROKEN_PIPE)"

  test "constructs backend handle holder":
    let backend = newWindowsBackend()
    check backend != nil

  test "non-Windows open fails clearly":
    when hostOS != "windows":
      let backend = newWindowsBackend()
      expect OSError:
        discard backend.ptyOpen()
