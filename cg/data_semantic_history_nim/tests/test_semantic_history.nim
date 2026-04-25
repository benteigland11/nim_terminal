import std/[unittest, options]
import ../src/semantic_history_lib

suite "semantic history":

  test "tracks command block phases and rows":
    let h = newSemanticHistory()
    check h.phase == sphIdle
    
    h.markPromptStart(10)
    check h.phase == sphPrompt
    check h.current.promptStartRow == 10
    
    h.markCommandStart(12)
    check h.phase == sphCommand
    check h.current.commandStartRow == 12
    
    h.markCommandExecuted(12)
    check h.phase == sphOutput
    check h.current.outputStartRow == 12
    
    h.markCommandFinished(15, 0)
    check h.phase == sphIdle
    check h.blocks.len == 1
    
    let b = h.blocks[0]
    check b.promptStartRow == 10
    check b.commandStartRow == 12
    check b.outputStartRow == 12
    check b.outputEndRow == 15
    check b.exitCode.get() == 0

  test "handles missing finish gracefully":
    let h = newSemanticHistory()
    h.markPromptStart(0)
    h.markCommandStart(0)
    h.markCommandExecuted(1)
    
    # Prompt starts again without a D
    h.markPromptStart(5)
    
    check h.blocks.len == 1
    let b = h.blocks[0]
    check b.promptStartRow == 0
    check b.outputEndRow == 4
    check b.exitCode.isNone

  test "lookups by row":
    let h = newSemanticHistory()
    h.markPromptStart(10)
    h.markCommandExecuted(12)
    h.markCommandFinished(15, 1)
    
    let b = h.blockAt(13)
    check b.isSome
    check b.get().exitCode.get() == 1
    
    check h.blockAt(9).isNone
    check h.blockAt(16).isNone
