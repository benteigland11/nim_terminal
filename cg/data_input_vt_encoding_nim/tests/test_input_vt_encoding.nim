import std/[unittest, strutils]
import ../src/input_vt_encoding_lib

suite "input vt encoding":

  test "SGR mouse press encoding":
    var mode = newInputMode()
    mode.mouseMode = mmSgr
    let ev = mouse(mePress, mbLeft, 10, 20)
    let bytes = encodeMouseEvent(ev, mode)
    # CSI < 0 ; 21 ; 11 M
    check cast[string](bytes) == "\e[<0;21;11M"

  test "SGR mouse release encoding":
    var mode = newInputMode()
    mode.mouseMode = mmSgr
    let ev = mouse(meRelease, mbLeft, 10, 20)
    let bytes = encodeMouseEvent(ev, mode)
    # CSI < 0 ; 21 ; 11 m
    check cast[string](bytes) == "\e[<0;21;11m"

  test "bracketed paste":
    var mode = newInputMode()
    mode.bracketedPaste = true
    let bytes = encodePaste("hello", mode)
    check cast[string](bytes) == "\e[200~hello\e[201~"

  test "keyboard encoding preserved (arrow up)":
    var mode = newInputMode()
    mode.cursorApp = false
    let bytes = encodeKeyEvent(key(kArrowUp), mode)
    check cast[string](bytes) == "\e[A"

  test "keyboard encoding application mode (arrow up)":
    var mode = newInputMode()
    mode.cursorApp = true
    let bytes = encodeKeyEvent(key(kArrowUp), mode)
    check cast[string](bytes) == "\eOA"
