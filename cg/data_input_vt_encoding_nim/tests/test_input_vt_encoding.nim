import std/unittest
import ../src/input_vt_encoding_lib

suite "input vt encoding":

  test "mouse reporting disabled sends nothing":
    check encodeMouseEvent(mouse(mePress, mbLeft, 0, 0), newInputMode()).len == 0

  test "X11 mouse reporting encodes press release wheel and modifiers":
    var mode = newInputMode()
    mode.mouseMode = mmX11

    check cast[string](encodeMouseEvent(mouse(mePress, mbLeft, 2, 4), mode)) == "\e[M %#"
    check cast[string](encodeMouseEvent(mouse(meRelease, mbRelease, 2, 4), mode)) == "\e[M#%#"
    check cast[string](encodeMouseEvent(mouse(mePress, mbWheelUp, 0, 0), mode)) == "\e[M`!!"
    check cast[string](encodeMouseEvent(mouse(mePress, mbWheelDown, 0, 0), mode)) == "\e[Ma!!"
    check cast[string](encodeMouseEvent(mouse(mePress, mbLeft, 0, 0, {modShift, modAlt, modCtrl}), mode)) == "\e[M<!!"

  test "X11 mouse reporting clamps legacy coordinates":
    var mode = newInputMode()
    mode.mouseMode = mmX11

    check encodeMouseEvent(mouse(mePress, mbLeft, -4, -7), mode) == @[Esc, byte('['), byte('M'), 32'u8, 33'u8, 33'u8]
    check encodeMouseEvent(mouse(mePress, mbLeft, 400, 500), mode) == @[Esc, byte('['), byte('M'), 32'u8, 255'u8, 255'u8]

  test "button-event mode reports drag while X11 ignores drag":
    var mode = newInputMode()
    mode.mouseMode = mmX11
    check encodeMouseEvent(mouse(meDrag, mbLeft, 1, 2), mode).len == 0

    mode.mouseMode = mmButtonEvent
    check cast[string](encodeMouseEvent(mouse(meDrag, mbLeft, 1, 2), mode)) == "\e[M@#\""

  test "any-event mode reports plain motion":
    var mode = newInputMode()
    mode.mouseMode = mmAnyEvent

    check cast[string](encodeMouseEvent(mouse(meMove, mbRelease, 1, 2), mode)) == "\e[MC#\""

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

  test "SGR no-button motion reports code 35 with motion terminator":
    # Any-event tracking (DECSET 1003) reports motion with no button held.
    # The button code is 35 (3 = no button, +32 motion bit) and, because it
    # is motion rather than a release, the terminator must be 'M', not 'm'.
    var mode = newInputMode()
    mode.mouseMode = mmSgr
    check cast[string](encodeMouseEvent(mouse(meMove, mbRelease, 10, 20), mode)) == "\e[<35;21;11M"

  test "SGR mouse reporting encodes wheel drag and modifiers":
    var mode = newInputMode()
    mode.mouseMode = mmSgr

    check cast[string](encodeMouseEvent(mouse(mePress, mbWheelUp, 0, 0), mode)) == "\e[<64;1;1M"
    check cast[string](encodeMouseEvent(mouse(mePress, mbWheelDown, 0, 0), mode)) == "\e[<65;1;1M"
    check cast[string](encodeMouseEvent(mouse(meDrag, mbLeft, 1, 2), mode)) == "\e[<32;3;2M"
    check cast[string](encodeMouseEvent(mouse(mePress, mbLeft, 0, 0, {modShift, modAlt, modCtrl}), mode)) == "\e[<28;1;1M"

  test "SGR coordinate encoding can be requested over button-event tracking":
    var mode = newInputMode()
    mode.mouseMode = mmButtonEvent
    mode.sgrMouse = true

    check cast[string](encodeMouseEvent(mouse(meDrag, mbLeft, 1, 2), mode)) == "\e[<32;3;2M"

  test "mouse tracking mode helpers report requested motion classes":
    var mode = newInputMode()
    mode.mouseMode = mmButtonEvent
    check trackingWantsDrag(mode)
    check trackingWantsMotion(mode)

    mode.mouseMode = mmAnyEvent
    check trackingWantsDrag(mode)
    check trackingWantsMotion(mode)

  test "alternate scroll requests wheel routing":
    var mode = newInputMode()
    check not mode.shouldSendWheel()
    mode.alternateScroll = true
    check not mode.shouldSendWheel()
    check mode.shouldSendWheel(usingAlternateScreen = true)
    check mode.shouldSendWheelAsCursorKeys(usingAlternateScreen = true)
    check not mode.shouldSendWheelAsCursorKeys(usingAlternateScreen = false)

  test "alternate screen routes wheel as cursor keys without mouse tracking":
    let mode = newInputMode()
    check mode.shouldSendWheel(usingAlternateScreen = true)
    check mode.shouldSendWheelAsCursorKeys(usingAlternateScreen = true)

  test "mouse tracking requests wheel routing":
    var mode = newInputMode()
    mode.mouseMode = mmX11
    check mode.shouldSendWheel()
    check mode.scrollInputKind(usingAlternateScreen = true) == sikMouseWheel

  test "input mode snapshot reports active scroll encoding":
    var mode = newInputMode()
    mode.cursorApp = true
    mode.bracketedPaste = true
    let snap = mode.snapshot(usingAlternateScreen = true)
    check snap.cursorApp
    check snap.bracketedPaste
    check snap.usingAlternateScreen
    check snap.scrollInputKind == sikCursorKeys

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

  test "keypad enter sends carriage return in normal and application keypad modes":
    var mode = newInputMode()
    check encodeKeyEvent(key(kKeypadEnter), mode) == @[13'u8]

    mode.keypadApp = true
    check encodeKeyEvent(key(kKeypadEnter), mode) == @[13'u8]

  test "alt keypad enter prefixes escape":
    check encodeKeyEvent(key(kKeypadEnter, {modAlt})) == @[27'u8, 13'u8]

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
