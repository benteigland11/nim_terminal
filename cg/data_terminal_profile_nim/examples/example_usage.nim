## Example usage of Terminal Profile.

import terminal_profile_lib

proc exampleLookup(section, key: string): string =
  case section & "." & key
  of "profile.mode":
    "agent"
  of "terminal.max_panes":
    "6"
  else:
    ""

let profile = resolveTerminalProfile(exampleLookup)
let snap = snapshot(profile)

doAssert snap.mode == pmAgent
doAssert snap.maxPanes == 6
doAssert snap.altWheelPolicy == AgentAltWheelPolicy
doAssert cfHistoryRail in snap.chrome

switchMode(profile, pmStandard)
doAssert snapshot(profile).maxPanes == 6
doAssert snapshot(profile).shortcutPreset == spStandard
