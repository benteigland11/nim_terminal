import std/unittest
import terminal_scroll_policy_lib

suite "terminal scroll policy":
  test "normal buffer scrolls terminal unless child requested wheel":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: false,
      childWantsWheel: false,
      viewportHasHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
    )) == saScrollViewport

    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: false,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
    )) == saRouteMouseWheel

  test "alternate screen off routes wheel to child when requested":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assOff,
      altWheelPolicy: awpTerminal,
    )) == saRouteMouseWheel

  test "app policy prefers child-owned TUI scrolling":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
    )) == saRouteMouseWheel

  test "terminal policy uses retained history when available":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assAlways,
      altWheelPolicy: awpTerminal,
    )) == saScrollViewport

    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      childWheelEncoding: cweMouseWheel,
      viewportHasHistory: false,
      viewportHasMeaningfulHistory: false,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assAlways,
      altWheelPolicy: awpTerminal,
    )) == saRouteMouseWheel

    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      childWheelEncoding: cweCursorKeys,
      viewportHasHistory: false,
      viewportHasMeaningfulHistory: false,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assAlways,
      altWheelPolicy: awpTerminal,
    )) == saIgnore

  test "smart policy returns to app at live edge":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpSmart,
    )) == saRouteMouseWheel

    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: false,
      scrollingTowardHistory: false,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpSmart,
    )) == saScrollViewport

  test "parsers accept documented aliases":
    check parseAltScreenScrollbackMode("off", assPassive) == assOff
    check parseAltScreenScrollbackMode("always", assOff) == assAlways
    check parseAltWheelPolicy("child", awpTerminal) == awpApp
    check parseAltWheelPolicy("viewport", awpApp) == awpTerminal
    check parseNormalWheelPolicy("fallback", nwpTerminal) == nwpTuiFallback
    check parseNormalWheelPolicy("auto", nwpTerminal) == nwpSmart

  test "normal-screen tui fallback routes thin history to cursor keys":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: false,
      childWantsWheel: false,
      childWheelEncoding: cweNone,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: false,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      normalScreenTuiLikely: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
      normalWheelPolicy: nwpTuiFallback,
    )) == saRouteCursorKeys

  test "normal-screen terminal policy does not synthesize cursor keys":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: false,
      childWantsWheel: false,
      childWheelEncoding: cweNone,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: false,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      normalScreenTuiLikely: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
      normalWheelPolicy: nwpTerminal,
    )) == saScrollViewport

  test "normal-screen tui fallback preserves meaningful terminal history":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: false,
      childWantsWheel: false,
      childWheelEncoding: cweNone,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      normalScreenTuiLikely: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
      normalWheelPolicy: nwpTuiFallback,
    )) == saScrollViewport

  test "normal-screen smart routes live-edge tui wheel to cursor keys":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: false,
      childWantsWheel: false,
      childWheelEncoding: cweNone,
      viewportHasHistory: true,
      viewportHasMeaningfulHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: false,
      normalScreenTuiLikely: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
      normalWheelPolicy: nwpSmart,
    )) == saRouteCursorKeys

  test "explicit child encoding is preserved":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: false,
      childWantsWheel: true,
      childWheelEncoding: cweCursorKeys,
      viewportHasHistory: false,
      viewportHasMeaningfulHistory: false,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
      normalWheelPolicy: nwpTerminal,
    )) == saRouteCursorKeys
