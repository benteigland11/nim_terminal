## ConEmu / Windows Terminal OSC 9;4 progress-bar state.
##
## Command-line tools (package managers, Claude Code compact, systemd, …) emit
## `OSC 9 ; 4 ; <state> ; <progress>` to report long-running work. This widget
## owns the pure state machine: parse fields, apply them, and expose a
## renderer-friendly snapshot. Drawing belongs to the host.

import std/strutils

type
  ProgressBarState* = enum
    pbsHidden        ## state 0 — clear / inactive
    pbsNormal        ## state 1 — determinate progress
    pbsError         ## state 2 — failed
    pbsIndeterminate ## state 3 — busy, no percentage
    pbsPaused        ## state 4 — paused / warning

  TerminalProgress* = object
    state*: ProgressBarState
    percent*: int              ## 0..100 when determinate
    generation*: int           ## increments on every successful apply

  ProgressSnapshot* = object
    visible*: bool
    state*: ProgressBarState
    percent*: int              ## clamped 0..100; 0 for indeterminate
    fraction*: float           ## 0.0..1.0 for determinate fills

func newTerminalProgress*(): TerminalProgress =
  TerminalProgress(state: pbsHidden, percent: 0, generation: 0)

func clampPercent(value: int): int =
  max(0, min(100, value))

func progressStateFromCode*(code: int): ProgressBarState =
  case code
  of 1: pbsNormal
  of 2: pbsError
  of 3: pbsIndeterminate
  of 4: pbsPaused
  else: pbsHidden

func isVisible*(p: TerminalProgress): bool =
  p.state != pbsHidden

func snapshot*(p: TerminalProgress): ProgressSnapshot =
  result.state = p.state
  result.visible = p.isVisible
  result.percent =
    if p.state in {pbsNormal, pbsError, pbsPaused}: clampPercent(p.percent)
    else: 0
  result.fraction =
    if result.percent <= 0: 0.0
    elif result.percent >= 100: 1.0
    else: float(result.percent) / 100.0

proc applyProgress*(
    p: var TerminalProgress,
    stateCode: int,
    percent = 0,
): bool =
  ## Apply an OSC 9;4 pair. Returns true when the visible progress changed.
  let nextState = progressStateFromCode(stateCode)
  let nextPercent =
    if nextState in {pbsNormal, pbsError, pbsPaused}: clampPercent(percent)
    else: 0
  if nextState == p.state and nextPercent == p.percent:
    return false
  p.state = nextState
  p.percent = nextPercent
  inc p.generation
  true

proc clearProgress*(p: var TerminalProgress): bool =
  ## Equivalent to OSC 9;4;0.
  p.applyProgress(0, 0)

func parseOsc9ProgressBody*(body: string): tuple[ok: bool, state, percent: int] =
  ## Parse the body of `OSC 9 ; …` when it is the progress form `4 ; st [; pr]`.
  ##
  ## Accepts:
  ##   `4;1;50`  — 50% normal
  ##   `4;3`     — indeterminate (percent defaults to 0)
  ##   `4;0`     — clear
  result.ok = false
  result.state = 0
  result.percent = 0
  if body.len == 0:
    return
  let parts = body.split(';')
  if parts.len < 2:
    return
  if parts[0].strip() != "4":
    return
  try:
    result.state = parseInt(parts[1].strip())
  except ValueError:
    return
  if parts.len >= 3 and parts[2].strip().len > 0:
    try:
      result.percent = parseInt(parts[2].strip())
    except ValueError:
      return
  result.ok = true
