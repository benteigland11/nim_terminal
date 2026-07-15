## Semantic history state machine.
##
## Tracks shell integration sequences (OSC 133) to build a structured
## history of commands, their prompts, their output, and their exit codes.
##
## Uses absolute row indices (scrollback length + screen row) to remain
## stable across scrolling.

import std/options

type
  SemanticPhase* = enum
    sphIdle
    sphPrompt
    sphCommand
    sphOutput

  CommandBlock* = object
    promptStartRow*: int
    commandStartRow*: int
    outputStartRow*: int
    outputEndRow*: int
    exitCode*: Option[int]

  SemanticHistory* = ref object
    phase*: SemanticPhase
    blocks*: seq[CommandBlock]
    current*: CommandBlock
    maxBlocks*: int  ## 0 = unlimited; positive caps retained completed blocks

const DefaultMaxSemanticBlocks* = 2048

func newSemanticHistory*(maxBlocks: int = DefaultMaxSemanticBlocks): SemanticHistory =
  SemanticHistory(
    phase: sphIdle,
    blocks: @[],
    maxBlocks: max(0, maxBlocks),
    current: CommandBlock(
      promptStartRow: -1,
      commandStartRow: -1,
      outputStartRow: -1,
      outputEndRow: -1,
      exitCode: none(int)
    )
  )

proc trimBlocks(h: SemanticHistory) =
  if h.maxBlocks <= 0: return
  if h.blocks.len > h.maxBlocks:
    let drop = h.blocks.len - h.maxBlocks
    h.blocks = h.blocks[drop .. ^1]

proc markPromptStart*(h: SemanticHistory, absRow: int) =
  ## OSC 133 ; A
  if h.phase == sphOutput or h.phase == sphIdle:
    if h.phase == sphOutput:
      h.current.outputEndRow = max(h.current.outputStartRow, absRow - 1)
      h.blocks.add(h.current)
      h.trimBlocks()
    h.current = CommandBlock(
      promptStartRow: absRow,
      commandStartRow: -1,
      outputStartRow: -1,
      outputEndRow: -1,
      exitCode: none(int)
    )
  h.phase = sphPrompt

proc markCommandStart*(h: SemanticHistory, absRow: int) =
  ## OSC 133 ; B
  h.current.commandStartRow = absRow
  h.phase = sphCommand

proc markCommandExecuted*(h: SemanticHistory, absRow: int) =
  ## OSC 133 ; C
  h.current.outputStartRow = absRow
  h.phase = sphOutput

proc markCommandFinished*(h: SemanticHistory, absRow: int, exitCode: int) =
  ## OSC 133 ; D ; <exitCode>
  h.current.outputEndRow = max(h.current.outputStartRow, absRow)
  h.current.exitCode = some(exitCode)
  h.blocks.add(h.current)
  h.trimBlocks()
  h.phase = sphIdle
  h.current = CommandBlock(
    promptStartRow: -1,
    commandStartRow: -1,
    outputStartRow: -1,
    outputEndRow: -1,
    exitCode: none(int)
  )

func blockAt*(h: SemanticHistory, absRow: int): Option[CommandBlock] =
  ## Returns the completed command block that spans the given absolute row, if any.
  for b in h.blocks:
    if absRow >= b.promptStartRow and absRow <= b.outputEndRow:
      return some(b)
  
  # Check if it's currently in the active block
  if h.phase != sphIdle and h.current.promptStartRow != -1:
    let endRow = if h.current.outputEndRow != -1: h.current.outputEndRow else: absRow
    if absRow >= h.current.promptStartRow and absRow <= endRow:
      return some(h.current)

  none(CommandBlock)
