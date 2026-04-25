import std/[unittest, strutils]
import ../src/vt_reports_lib

suite "vt reports generator":

  test "reportCursorPosition formats 0-indexed to 1-indexed":
    check reportCursorPosition(0, 0) == "\e[1;1R"
    check reportCursorPosition(23, 79) == "\e[24;80R"

  test "reportPrimaryDeviceAttributes includes expected parts":
    let s = reportPrimaryDeviceAttributes({tfAnsiColor, tfMouse1006})
    check s.contains("?62")
    check s.contains("1")
    check s.contains("8")
    check s.endsWith("c")

  test "reportSecondaryDeviceAttributes":
    check reportSecondaryDeviceAttributes(123) == "\e[>0;123;0c"

  test "reportWindowSize":
    check reportWindowSize(24, 80) == "\e[8;24;80t"

  test "reportWindowTitle":
    check reportWindowTitle("Hello") == "\e[lHello\e\\"
