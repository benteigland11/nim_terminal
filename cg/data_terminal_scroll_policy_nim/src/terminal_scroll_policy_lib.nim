## Terminal scroll routing policy.
##
## Decides whether wheel-like input should scroll the terminal viewport or be
## forwarded to the child process. This keeps terminal emulator glue from
## hardcoding app-specific behavior for full-screen TUIs.

type
  AltScreenScrollbackMode* = enum
    assOff      ## Do not retain alternate-screen history.
    assPassive  ## Retain history, but prefer child-owned TUI scrolling.
    assAlways   ## Retain history and prefer terminal viewport scrolling.

  AltWheelPolicy* = enum
    awpApp       ## Prefer forwarding wheel input to the child application.
    awpTerminal  ## Prefer scrolling terminal-retained history.
    awpSmart     ## Scroll retained history only after user has scrolled back.

  ScrollAction* = enum
    saIgnore
    saRouteToChild
    saScrollViewport

  ScrollPolicyInput* = object
    usingAltScreen*: bool
    childWantsWheel*: bool
    viewportHasHistory*: bool
    viewportAtLiveEnd*: bool
    scrollingTowardHistory*: bool
    altScrollbackMode*: AltScreenScrollbackMode
    altWheelPolicy*: AltWheelPolicy

func altScrollbackEnabled*(mode: AltScreenScrollbackMode): bool =
  mode != assOff

func decideWheelAction*(input: ScrollPolicyInput): ScrollAction =
  ## Choose where wheel input belongs for the current terminal state.
  if not input.usingAltScreen:
    if input.childWantsWheel:
      return saRouteToChild
    return saScrollViewport

  if input.altScrollbackMode == assOff:
    if input.childWantsWheel:
      return saRouteToChild
    return saIgnore

  let canScrollTerminal =
    input.viewportHasHistory and
    (input.scrollingTowardHistory or not input.viewportAtLiveEnd)

  case input.altWheelPolicy
  of awpApp:
    if input.childWantsWheel:
      saRouteToChild
    elif canScrollTerminal:
      saScrollViewport
    else:
      saIgnore
  of awpTerminal:
    if canScrollTerminal:
      saScrollViewport
    elif input.childWantsWheel:
      saRouteToChild
    else:
      saIgnore
  of awpSmart:
    if canScrollTerminal and not input.viewportAtLiveEnd:
      saScrollViewport
    elif input.childWantsWheel:
      saRouteToChild
    elif canScrollTerminal:
      saScrollViewport
    else:
      saIgnore

func parseAltScreenScrollbackMode*(value: string, fallback: AltScreenScrollbackMode): AltScreenScrollbackMode =
  case value
  of "off", "false", "none":
    assOff
  of "passive", "on", "true":
    assPassive
  of "always", "terminal":
    assAlways
  else:
    fallback

func parseAltWheelPolicy*(value: string, fallback: AltWheelPolicy): AltWheelPolicy =
  case value
  of "app", "child":
    awpApp
  of "terminal", "viewport":
    awpTerminal
  of "smart", "auto":
    awpSmart
  else:
    fallback
