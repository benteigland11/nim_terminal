import std/[unittest, strutils]
import ../src/vt_reports_lib

suite "vt reports generator":

  test "reportCursorPosition formats 0-indexed to 1-indexed":
    check reportCursorPosition(0, 0) == "\e[1;1R"
    check reportCursorPosition(23, 79) == "\e[24;80R"

  test "reportTerminalOk formats DSR 5 response":
    check reportTerminalOk() == "\e[0n"

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

  test "reportModeStatus":
    check reportModeStatus(2026, msNotRecognized) == "\e[?2026;0$y"
    check reportModeStatus(2004, msSet) == "\e[?2004;1$y"
    check reportModeStatus(4, msReset, privateMode = false) == "\e[4;2$y"

  test "modeStatusFrom table lookup":
    let modes = [
      modeSupport(2004, msSet),
      modeSupport(4, msReset, privateMode = false),
    ]
    check modeStatusFrom(modes, 2004) == msSet
    check modeStatusFrom(modes, 4, privateMode = false) == msReset
    check modeStatusFrom(modes, 2026) == msNotRecognized

  test "reportStateString formats DECRQSS responses":
    check reportStateString("0m") == "\eP1$r0m\e\\"
    check reportStateString("", valid = false) == "\eP0$r\e\\"
