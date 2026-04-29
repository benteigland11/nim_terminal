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
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
    )) == saRouteToChild

  test "alternate screen off routes wheel to child when requested":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assOff,
      altWheelPolicy: awpTerminal,
    )) == saRouteToChild

  test "app policy prefers child-owned TUI scrolling":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpApp,
    )) == saRouteToChild

  test "terminal policy uses retained history when available":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assAlways,
      altWheelPolicy: awpTerminal,
    )) == saScrollViewport

  test "smart policy returns to app at live edge":
    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
      viewportAtLiveEnd: true,
      scrollingTowardHistory: true,
      altScrollbackMode: assPassive,
      altWheelPolicy: awpSmart,
    )) == saRouteToChild

    check decideWheelAction(ScrollPolicyInput(
      usingAltScreen: true,
      childWantsWheel: true,
      viewportHasHistory: true,
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
