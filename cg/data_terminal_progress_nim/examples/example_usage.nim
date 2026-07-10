import terminal_progress_lib

## Simulate Claude Code / ConEmu compact progress and clear it when done.

var bar = newTerminalProgress()
let fields = parseOsc9ProgressBody("4;1;35")
doAssert fields.ok
doAssert bar.applyProgress(fields.state, fields.percent)
doAssert bar.snapshot().percent == 35

discard bar.applyProgress(1, 100)
doAssert bar.snapshot().fraction == 1.0

discard bar.clearProgress()
doAssert not bar.isVisible

echo "terminal-progress example ok"
