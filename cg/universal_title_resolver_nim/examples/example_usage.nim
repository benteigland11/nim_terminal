## Example: Using the Title Resolver to manage tab labels.

import std/options
import ../src/title_resolver_lib

var state = newTitleState(tpPreferTitle)
state.cwd = "nim_terminal"

echo "Initial label: ", state.resolve()

discard state.updateProgramName("vim")
echo "With program running: ", state.resolve()

discard state.updateOscTitle("Terminal Research")
echo "With explicit OSC title: ", state.resolve()

state.policy = tpPreferProgram
echo "With 'PreferProgram' policy: ", state.resolve()
