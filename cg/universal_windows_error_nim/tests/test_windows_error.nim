import std/[unittest, strutils, options]
import ../src/windows_error_lib

suite "windows error translator":

  test "common error codes":
    check translateErrorCode(5).contains("Access is denied")
    check translateErrorCode(109).contains("BROKEN_PIPE")

  test "hresult mapping":
    # 0x80070057 -> -2147024809
    check translateErrorCode(-2147024809).contains("Invalid parameter")

  test "exception raising":
    try:
      raiseWinError(6, "Opening PTY")
    except WinError as e:
      check e.msg.contains("Opening PTY")
      check e.msg.contains("handle is invalid")
