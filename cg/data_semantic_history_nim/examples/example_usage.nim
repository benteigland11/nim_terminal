import semantic_history_lib
import std/options

let h = newSemanticHistory()

h.markPromptStart(0)
h.markCommandStart(0)
h.markCommandExecuted(1)
h.markCommandFinished(5, 0)

let blockData = h.blockAt(2)
if blockData.isSome:
  echo "Found command spanning rows ", blockData.get().promptStartRow, " to ", blockData.get().outputEndRow
  echo "Exit code: ", blockData.get().exitCode.get(0)
