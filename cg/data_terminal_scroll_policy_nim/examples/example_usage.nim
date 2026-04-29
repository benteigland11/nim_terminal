## Example usage of Terminal Scroll Policy.

import terminal_scroll_policy_lib

let decision = decideWheelAction(ScrollPolicyInput(
  usingAltScreen: true,
  childWantsWheel: true,
  viewportHasHistory: true,
  viewportAtLiveEnd: true,
  scrollingTowardHistory: true,
  altScrollbackMode: assPassive,
  altWheelPolicy: awpApp,
))

doAssert decision == saRouteToChild
