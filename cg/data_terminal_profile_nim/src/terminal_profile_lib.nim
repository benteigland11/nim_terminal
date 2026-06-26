## Terminal profile presets with layered overrides.
##
## Resolves a mode preset (standard or agent), applies explicit config
## overrides that stay pinned across mode switches, and exposes the
## effective settings bundle for terminal emulator glue.

import std/strutils

type
  ProfileMode* = enum
    pmStandard = "standard"
    pmAgent = "agent"

  ShortcutPreset* = enum
    spStandard = "standard"
    spAgent = "agent"

  ChromeFeature* = enum
    cfHistoryRail = "history_rail"
    cfDiagnosticsHud = "diagnostics_hud"
    cfResourceHud = "resource_hud"

  ProfileField* = enum
    pfMaxPanes
    pfScrollback
    pfDiagnosticsCapacity
    pfAltScreenScrollback
    pfAltWheelPolicy
    pfNormalWheelPolicy
    pfMeaningfulHistoryRows
    pfShortcutPreset
    pfChrome

  TerminalProfileSnapshot* = object
    mode*: ProfileMode
    maxPanes*: int
    scrollback*: int
    diagnosticsCapacity*: int
    altScreenScrollback*: string
    altWheelPolicy*: string
    normalWheelPolicy*: string
    meaningfulHistoryRows*: int
    shortcutPreset*: ShortcutPreset
    chrome*: set[ChromeFeature]

  TerminalProfileState* = ref object
    mode*: ProfileMode
    pinned*: set[ProfileField]
    snapshot*: TerminalProfileSnapshot

  ConfigLookup* = proc(section, key: string): string {.closure.}

const
  StandardMaxPanes* = 4
  AgentMaxPanes* = 8
  ProfileDefaultScrollback* = 10000
  StandardDiagnosticsCapacity* = 128
  AgentDiagnosticsCapacity* = 256
  DefaultMeaningfulHistoryRows* = 3
  StandardAltScreenScrollback* = "passive"
  StandardAltWheelPolicy* = "terminal"
  StandardNormalWheelPolicy* = "terminal"
  AgentAltScreenScrollback* = "passive"
  AgentAltWheelPolicy* = "app"
  AgentNormalWheelPolicy* = "terminal"

func parseProfileMode*(value: string; fallback = pmStandard): ProfileMode =
  case value.strip().toLowerAscii()
  of "agent", "power", "power_user", "power-user":
    pmAgent
  of "standard", "base", "default", "everyday":
    pmStandard
  else:
    fallback

func parseShortcutPreset*(value: string; fallback: ShortcutPreset): ShortcutPreset =
  case value.strip().toLowerAscii()
  of "agent":
    spAgent
  of "standard", "base", "default":
    spStandard
  else:
    fallback

func parseChromeFeatures*(value: string): set[ChromeFeature] =
  result = {}
  for item in value.split(','):
    case item.strip().toLowerAscii()
    of "history", "history_rail", "semantic_history":
      result.incl cfHistoryRail
    of "diagnostics", "diagnostics_hud", "vt_diagnostics":
      result.incl cfDiagnosticsHud
    of "resource", "resource_hud", "resources":
      result.incl cfResourceHud
    else:
      discard

func chromeToConfigValue*(features: set[ChromeFeature]): string =
  var items: seq[string] = @[]
  if cfHistoryRail in features:
    items.add "history_rail"
  if cfDiagnosticsHud in features:
    items.add "diagnostics_hud"
  if cfResourceHud in features:
    items.add "resource_hud"
  items.join(",")

func presetSnapshot*(mode: ProfileMode): TerminalProfileSnapshot =
  case mode
  of pmStandard:
    TerminalProfileSnapshot(
      mode: pmStandard,
      maxPanes: StandardMaxPanes,
      scrollback: ProfileDefaultScrollback,
      diagnosticsCapacity: StandardDiagnosticsCapacity,
      altScreenScrollback: StandardAltScreenScrollback,
      altWheelPolicy: StandardAltWheelPolicy,
      normalWheelPolicy: StandardNormalWheelPolicy,
      meaningfulHistoryRows: DefaultMeaningfulHistoryRows,
      shortcutPreset: spStandard,
      chrome: {},
    )
  of pmAgent:
    TerminalProfileSnapshot(
      mode: pmAgent,
      maxPanes: AgentMaxPanes,
      scrollback: ProfileDefaultScrollback,
      diagnosticsCapacity: AgentDiagnosticsCapacity,
      altScreenScrollback: AgentAltScreenScrollback,
      altWheelPolicy: AgentAltWheelPolicy,
      normalWheelPolicy: AgentNormalWheelPolicy,
      meaningfulHistoryRows: DefaultMeaningfulHistoryRows,
      shortcutPreset: spAgent,
      chrome: {cfHistoryRail, cfDiagnosticsHud},
    )

func newTerminalProfileState*(mode: ProfileMode): TerminalProfileState =
  TerminalProfileState(
    mode: mode,
    pinned: {},
    snapshot: presetSnapshot(mode),
  )

func snapshot*(state: TerminalProfileState): TerminalProfileSnapshot =
  state.snapshot

func hasPinned*(state: TerminalProfileState; field: ProfileField): bool =
  field in state.pinned

proc pinInt*(state: TerminalProfileState; field: ProfileField; value: int; target: var int) =
  state.pinned.incl field
  target = value

proc pinString*(state: TerminalProfileState; field: ProfileField; value: string; target: var string) =
  state.pinned.incl field
  target = value

proc pinShortcutPreset*(state: TerminalProfileState; value: ShortcutPreset) =
  state.pinned.incl pfShortcutPreset
  state.snapshot.shortcutPreset = value

proc pinChrome*(state: TerminalProfileState; value: set[ChromeFeature]) =
  state.pinned.incl pfChrome
  state.snapshot.chrome = value

proc applyPresetFields*(state: TerminalProfileState) =
  let preset = presetSnapshot(state.mode)
  if pfMaxPanes notin state.pinned:
    state.snapshot.maxPanes = preset.maxPanes
  if pfScrollback notin state.pinned:
    state.snapshot.scrollback = preset.scrollback
  if pfDiagnosticsCapacity notin state.pinned:
    state.snapshot.diagnosticsCapacity = preset.diagnosticsCapacity
  if pfAltScreenScrollback notin state.pinned:
    state.snapshot.altScreenScrollback = preset.altScreenScrollback
  if pfAltWheelPolicy notin state.pinned:
    state.snapshot.altWheelPolicy = preset.altWheelPolicy
  if pfNormalWheelPolicy notin state.pinned:
    state.snapshot.normalWheelPolicy = preset.normalWheelPolicy
  if pfMeaningfulHistoryRows notin state.pinned:
    state.snapshot.meaningfulHistoryRows = preset.meaningfulHistoryRows
  if pfShortcutPreset notin state.pinned:
    state.snapshot.shortcutPreset = preset.shortcutPreset
  if pfChrome notin state.pinned:
    state.snapshot.chrome = preset.chrome
  state.snapshot.mode = state.mode

proc switchMode*(state: TerminalProfileState; mode: ProfileMode) =
  state.mode = mode
  applyPresetFields(state)

func parsePositiveInt*(value: string; fallback: int): int =
  let trimmed = value.strip()
  if trimmed.len == 0:
    return fallback
  try:
    max(1, parseInt(trimmed))
  except ValueError:
    fallback

func parseNonNegativeInt*(value: string; fallback: int): int =
  let trimmed = value.strip()
  if trimmed.len == 0:
    return fallback
  try:
    max(0, parseInt(trimmed))
  except ValueError:
    fallback

proc applyConfigOverrides*(state: TerminalProfileState; lookup: ConfigLookup) =
  let maxPanesValue = lookup("terminal", "max_panes")
  if maxPanesValue.len > 0:
    pinInt(state, pfMaxPanes, parsePositiveInt(maxPanesValue, state.snapshot.maxPanes), state.snapshot.maxPanes)

  let scrollbackValue = lookup("terminal", "scrollback")
  if scrollbackValue.len > 0:
    pinInt(state, pfScrollback, parsePositiveInt(scrollbackValue, state.snapshot.scrollback), state.snapshot.scrollback)

  let diagnosticsValue = lookup("diagnostics", "capacity")
  if diagnosticsValue.len > 0:
    pinInt(
      state,
      pfDiagnosticsCapacity,
      parseNonNegativeInt(diagnosticsValue, state.snapshot.diagnosticsCapacity),
      state.snapshot.diagnosticsCapacity,
    )

  let altScrollbackValue = lookup("scroll", "alternate_screen_scrollback")
  if altScrollbackValue.len > 0:
    pinString(state, pfAltScreenScrollback, altScrollbackValue.strip().toLowerAscii(), state.snapshot.altScreenScrollback)

  let altWheelValue = lookup("scroll", "wheel_in_alt_screen")
  if altWheelValue.len > 0:
    pinString(state, pfAltWheelPolicy, altWheelValue.strip().toLowerAscii(), state.snapshot.altWheelPolicy)

  let normalWheelValue = lookup("scroll", "wheel_in_normal_screen")
  if normalWheelValue.len > 0:
    pinString(state, pfNormalWheelPolicy, normalWheelValue.strip().toLowerAscii(), state.snapshot.normalWheelPolicy)

  let meaningfulRowsValue = lookup("scroll", "meaningful_history_rows")
  if meaningfulRowsValue.len > 0:
    pinInt(
      state,
      pfMeaningfulHistoryRows,
      parsePositiveInt(meaningfulRowsValue, state.snapshot.meaningfulHistoryRows),
      state.snapshot.meaningfulHistoryRows,
    )

  let shortcutPresetValue = lookup("profile", "shortcut_preset")
  if shortcutPresetValue.len > 0:
    pinShortcutPreset(state, parseShortcutPreset(shortcutPresetValue, state.snapshot.shortcutPreset))

  let chromeValue = lookup("profile", "chrome")
  if chromeValue.len > 0:
    pinChrome(state, parseChromeFeatures(chromeValue))

proc resolveTerminalProfile*(
    lookup: ConfigLookup;
    envMode = "";
    fallback = pmStandard,
): TerminalProfileState =
  var mode = fallback
  if envMode.strip().len > 0:
    mode = parseProfileMode(envMode, fallback)
  else:
    let modeValue = lookup("profile", "mode")
    if modeValue.len > 0:
      mode = parseProfileMode(modeValue, fallback)

  result = newTerminalProfileState(mode)
  applyConfigOverrides(result, lookup)
  applyPresetFields(result)
