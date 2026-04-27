import std/unittest
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

  test "X11 mode ignores motion while button-event mode sends drag":
    var mode = newInputMode()
    mode.mouseMode = mmX11
    check encodeMouseEvent(mouse(meDrag, mbLeft, 1, 2), mode).len == 0

    mode.mouseMode = mmButtonEvent
    let drag = encodeMouseEvent(mouse(meDrag, mbLeft, 1, 2), mode)
    check drag.len > 0
    check trackingWantsDrag(mode)

  test "any-event mode sends plain motion":
    var mode = newInputMode()
    mode.mouseMode = mmAnyEvent
    let move = encodeMouseEvent(mouse(meMove, mbLeft, 1, 2), mode)
    check move.len > 0
    check trackingWantsMotion(mode)

  test "alternate scroll requests wheel routing":
    var mode = newInputMode()
    check not mode.shouldSendWheel()
    mode.alternateScroll = true
    check mode.shouldSendWheel()
    check mode.shouldSendWheelAsCursorKeys(usingAlternateScreen = true)
    check not mode.shouldSendWheelAsCursorKeys(usingAlternateScreen = false)

  test "mouse tracking requests wheel routing":
    var mode = newInputMode()
    mode.mouseMode = mmX11
    check mode.shouldSendWheel()

  test "SGR coordinate encoding composes with button-event tracking":
    var mode = newInputMode()
    mode.mouseMode = mmButtonEvent
    mode.sgrMouse = true
    let drag = encodeMouseEvent(mouse(meDrag, mbLeft, 1, 2), mode)
    check cast[string](drag) == "\e[<32;3;2M"

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

  test "control character encoding":
    let ctrlC = encodeKeyEvent(keyChar(uint32('c'), {modCtrl}))
    let ctrlUnderscore = encodeKeyEvent(keyChar(uint32('_'), {modCtrl}))
    let ctrlBackslash = encodeKeyEvent(keyChar(uint32('\\'), {modCtrl}))
    let ctrlLeftBracket = encodeKeyEvent(keyChar(uint32('['), {modCtrl}))
    let ctrlQuestion = encodeKeyEvent(keyChar(uint32('?'), {modCtrl}))

    check ctrlC == @[3'u8]
    check ctrlUnderscore == @[31'u8]
    check ctrlBackslash == @[28'u8]
    check ctrlLeftBracket == @[27'u8]
    check ctrlQuestion == @[127'u8]
