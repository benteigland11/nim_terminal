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

  NormalWheelPolicy* = enum
    nwpTerminal    ## Normal-screen wheel input scrolls terminal history.
    nwpTuiFallback ## Route wheel to TUI-like children when history is thin.
    nwpSmart       ## Prefer real history, otherwise route to TUI-like children.

  ChildWheelEncoding* = enum
    cweNone
    cweMouseWheel
    cweCursorKeys

  ScrollAction* = enum
    saIgnore
    saRouteToChild ## Legacy child route; callers should prefer explicit routes.
    saRouteMouseWheel
    saRouteCursorKeys
    saRoutePageKeys
    saScrollViewport

  ScrollPolicyInput* = object
    usingAltScreen*: bool
    childWantsWheel*: bool
    childWheelEncoding*: ChildWheelEncoding
    viewportHasHistory*: bool
    viewportHasMeaningfulHistory*: bool
    viewportAtLiveEnd*: bool
    scrollingTowardHistory*: bool
    normalScreenTuiLikely*: bool
    forceTerminalScroll*: bool
    forceChildScroll*: bool
    altScrollbackMode*: AltScreenScrollbackMode
    altWheelPolicy*: AltWheelPolicy
    normalWheelPolicy*: NormalWheelPolicy

func altScrollbackEnabled*(mode: AltScreenScrollbackMode): bool =
  mode != assOff

func routeForChildEncoding(kind: ChildWheelEncoding): ScrollAction =
  case kind
  of cweMouseWheel: saRouteMouseWheel
  of cweCursorKeys: saRouteCursorKeys
  of cweNone: saRouteToChild

func effectiveChildEncoding(input: ScrollPolicyInput): ChildWheelEncoding =
  if input.childWheelEncoding != cweNone:
    return input.childWheelEncoding
  if input.childWantsWheel:
    return cweMouseWheel
  cweNone

func canScrollTerminal(input: ScrollPolicyInput, meaningful = false): bool =
  let hasHistory =
    if meaningful: input.viewportHasMeaningfulHistory
    else: input.viewportHasHistory
  hasHistory and (input.scrollingTowardHistory or not input.viewportAtLiveEnd)

func decideWheelAction*(input: ScrollPolicyInput): ScrollAction =
  ## Choose where wheel input belongs for the current terminal state.
  if input.forceTerminalScroll:
    return saScrollViewport
  if input.forceChildScroll:
    let childEncoding = input.effectiveChildEncoding()
    if childEncoding != cweNone:
      return routeForChildEncoding(childEncoding)
    return saRouteCursorKeys

  let childEncoding = input.effectiveChildEncoding()

  if not input.usingAltScreen:
    if childEncoding != cweNone:
      return routeForChildEncoding(childEncoding)
    if input.normalScreenTuiLikely:
      let hasMeaningfulHistory = input.viewportHasMeaningfulHistory
      case input.normalWheelPolicy
      of nwpTerminal:
        discard
      of nwpTuiFallback:
        if not hasMeaningfulHistory:
          return saRouteCursorKeys
      of nwpSmart:
        if input.canScrollTerminal(meaningful = true):
          return saScrollViewport
        return saRouteCursorKeys
    return saScrollViewport

  if input.altScrollbackMode == assOff:
    if childEncoding != cweNone:
      return routeForChildEncoding(childEncoding)
    return saIgnore

  let canScroll = input.canScrollTerminal()

  case input.altWheelPolicy
  of awpApp:
    if childEncoding != cweNone:
      routeForChildEncoding(childEncoding)
    elif canScroll:
      saScrollViewport
    else:
      saIgnore
  of awpTerminal:
    if canScroll:
      saScrollViewport
    elif childEncoding == cweMouseWheel:
      routeForChildEncoding(childEncoding)
    else:
      saIgnore
  of awpSmart:
    if canScroll and not input.viewportAtLiveEnd:
      saScrollViewport
    elif childEncoding != cweNone:
      routeForChildEncoding(childEncoding)
    elif canScroll:
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

func parseNormalWheelPolicy*(value: string, fallback: NormalWheelPolicy): NormalWheelPolicy =
  case value
  of "terminal", "viewport":
    nwpTerminal
  of "tui", "app", "child", "fallback":
    nwpTuiFallback
  of "smart", "auto":
    nwpSmart
  else:
    fallback
