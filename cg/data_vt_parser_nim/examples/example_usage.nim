## Feed a mixed byte stream into the parser and classify every event.
##
## The input contains:
##   * plain text
##   * a C0 control (LF)
##   * an SGR CSI sequence (ESC[1;31m)
##   * an OSC window-title sequence terminated by BEL
## so that each event kind produced by the parser is demonstrated.

import std/strformat
import vt_parser_lib

let input =
  "hello\n" &
  "\x1B[1;31mworld\x1B[0m" &
  "\x1B]0;my-title\x07"

var parser = newVtParser()
var printed = 0
var executed = 0
var csiDispatches = 0
var oscDispatches: seq[string]

proc handle(ev: VtEvent) =
  case ev.kind
  of vePrint:
    inc printed
  of veExecute:
    inc executed
  of veCsiDispatch:
    inc csiDispatches
    # Resolve the first SGR parameter with a default of 0, as a spec reader would.
    let first = paramOr(ev.params, 0, 0)
    discard first
  of veOscDispatch:
    var s = ""
    for b in ev.oscData: s.add char(b)
    oscDispatches.add s
  else:
    discard

parser.feed(input, handle)

doAssert parser.inGround
doAssert printed == len("hello") + len("world")
doAssert executed == 1                 # the LF
doAssert csiDispatches == 2            # SGR set + SGR reset
doAssert oscDispatches == @["0;my-title"]

let summary = &"print={printed} exec={executed} csi={csiDispatches} osc={oscDispatches.len}"
doAssert summary.len > 0
