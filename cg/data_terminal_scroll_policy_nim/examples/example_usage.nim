## Example usage of Terminal Scroll Policy.

import terminal_scroll_policy_lib

let decision = decideWheelAction(ScrollPolicyInput(
  usingAltScreen: true,
  childWantsWheel: true,
  childWheelEncoding: cweMouseWheel,
  viewportHasHistory: true,
  viewportHasMeaningfulHistory: true,
  viewportAtLiveEnd: true,
  scrollingTowardHistory: true,
  altScrollbackMode: assPassive,
  altWheelPolicy: awpApp,
  normalWheelPolicy: nwpTerminal,
))

doAssert decision == saRouteMouseWheel
