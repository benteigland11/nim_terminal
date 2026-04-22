## Example: translate a simulated keystroke stream into pty input bytes.
##
## Demonstrates the three things a GUI host needs to know:
##   1. Plain character encoding (including modifiers).
##   2. Navigation / function key encoding (CSI and SS3 forms).
##   3. Mode-sensitive encoding (DECCKM application cursor keys).
##
## No I/O, no external services — the "keystrokes" are a hardcoded list.

import keyboard_vt_input_lib

func render(bytes: seq[byte]): string =
  ## Turn a byte sequence into a readable display form so the example
  ## can show what a terminal would actually receive.
  result = newStringOfCap(bytes.len * 2)
  for b in bytes:
    if b == 0x1B'u8:   result.add "<ESC>"
    elif b == 0x7F'u8: result.add "<DEL>"
    elif b == 0x0D'u8: result.add "<CR>"
    elif b == 0x09'u8: result.add "<TAB>"
    elif b < 0x20'u8:  result.add "<" & $int(b) & ">"
    else:              result.add char(b)

type Step = object
  label: string
  event: KeyEvent

let mode = newKeyboardMode()

var appMode = newKeyboardMode()
appMode.cursorApp = true

let script = @[
  Step(label: "'h'",          event: keyChar(uint32('h'))),
  Step(label: "'i'",          event: keyChar(uint32('i'))),
  Step(label: "Enter",        event: key(kEnter)),
  Step(label: "Ctrl+C",       event: keyChar(uint32('c'), {modCtrl})),
  Step(label: "Alt+b",        event: keyChar(uint32('b'), {modAlt})),
  Step(label: "ArrowUp",      event: key(kArrowUp)),
  Step(label: "Shift+Tab",    event: key(kTab, {modShift})),
  Step(label: "F5",           event: key(kF5)),
  Step(label: "Ctrl+F5",      event: key(kF5, {modCtrl})),
]

var totalBytes = 0
for step in script:
  let bytes = encode(step.event, mode)
  totalBytes += bytes.len
  # We only exercise the encoder here; a real host would now write
  # these bytes to the pty master via its backend.
  discard render(bytes)

# Same ArrowUp, now in application-cursor mode (e.g. vim insert mode).
let appArrow = encode(key(kArrowUp), appMode)
totalBytes += appArrow.len

doAssert totalBytes > 0
