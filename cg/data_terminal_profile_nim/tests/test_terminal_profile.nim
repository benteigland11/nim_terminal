import std/[tables, unittest]
import terminal_profile_lib

proc testLookup(values: Table[string, string]): ConfigLookup =
  proc lookup(section, key: string): string =
    values.getOrDefault(section & "." & key, "")
  lookup

suite "terminal profile":
  test "standard preset defaults":
    let snap = presetSnapshot(pmStandard)
    check snap.maxPanes == StandardMaxPanes
    check snap.altWheelPolicy == StandardAltWheelPolicy
    check snap.normalWheelPolicy == StandardNormalWheelPolicy
    check snap.normalWheelPolicy == "smart"
    check snap.shortcutPreset == spStandard
    check snap.chrome == {}

  test "agent preset defaults":
    let snap = presetSnapshot(pmAgent)
    check snap.maxPanes == AgentMaxPanes
    check snap.altWheelPolicy == AgentAltWheelPolicy
    check snap.normalWheelPolicy == AgentNormalWheelPolicy
    check snap.normalWheelPolicy == "smart"
    check snap.shortcutPreset == spAgent
    check cfHistoryRail in snap.chrome
    check cfDiagnosticsHud in snap.chrome

  test "config overrides pin fields across mode switch":
    var values = initTable[string, string]()
    values["profile.mode"] = "agent"
    values["terminal.max_panes"] = "12"
    values["scroll.wheel_in_alt_screen"] = "terminal"

    let state = resolveTerminalProfile(testLookup(values))
    check state.mode == pmAgent
    check state.snapshot.maxPanes == 12
    check state.snapshot.altWheelPolicy == "terminal"
    check hasPinned(state, pfMaxPanes)
    check hasPinned(state, pfAltWheelPolicy)

    switchMode(state, pmStandard)
    check state.mode == pmStandard
    check state.snapshot.maxPanes == 12
    check state.snapshot.altWheelPolicy == "terminal"
    check state.snapshot.altScreenScrollback == StandardAltScreenScrollback
    check state.snapshot.shortcutPreset == spStandard

  test "env mode wins over config file mode":
    var values = initTable[string, string]()
    values["profile.mode"] = "standard"
    let state = resolveTerminalProfile(testLookup(values), envMode = "agent")
    check state.mode == pmAgent

  test "chrome override replaces preset chrome":
    var values = initTable[string, string]()
    values["profile.mode"] = "agent"
    values["profile.chrome"] = "resource_hud"
    let state = resolveTerminalProfile(testLookup(values))
    check state.snapshot.chrome == {cfResourceHud}
