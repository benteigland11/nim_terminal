## VT500-series escape sequence parser.
##
## Implements Paul Williams' DEC-compatible state machine
## (https://vt100.net/emu/dec_ansi_parser). Byte input is fed via
## `feed` and parsed events are delivered through a caller-supplied
## callback. The parser itself holds no I/O and performs no rendering;
## it is pure transformation of a byte stream into semantic events.
##
## Recognized structures:
##   * Printable characters (GROUND)
##   * C0 / C1 control execution
##   * ESC Fp / ESC Fe / ESC Fs dispatches (with intermediates)
##   * CSI sequences (parameters, sub-parameters, intermediates)
##   * OSC strings (terminated by BEL or ST)
##   * DCS sequences (hook / put / unhook)
##   * SOS / PM / APC strings (consumed and discarded)

const
  MaxParams* = 16
  MaxSubParams* = 8
  MaxIntermediates* = 2

type
  State = enum
    sGround
    sEscape
    sEscapeIntermediate
    sCsiEntry
    sCsiParam
    sCsiIntermediate
    sCsiIgnore
    sDcsEntry
    sDcsParam
    sDcsIntermediate
    sDcsPassthrough
    sDcsIgnore
    sOscString
    sSosPmApcString

  VtEventKind* = enum
    vePrint        ## A printable codepoint (raw byte; UTF-8 reassembly is caller's concern)
    veExecute      ## A C0 or C1 control byte executed in-band
    veEscDispatch  ## ESC Fp/Fe/Fs terminator reached
    veCsiDispatch  ## CSI final byte reached
    veOscDispatch  ## OSC string terminated
    veDcsHook      ## DCS passthrough started (params + final known)
    veDcsPut       ## A byte inside DCS passthrough
    veDcsUnhook    ## DCS passthrough terminated

  VtParam* = object
    ## Numeric parameter with optional sub-parameters (colon-separated, per ECMA-48).
    value*: int          ## -1 if the parameter was omitted / defaulted
    subParams*: seq[int]

  VtEvent* = object
    case kind*: VtEventKind
    of vePrint, veExecute, veDcsPut:
      byteVal*: byte
    of veEscDispatch:
      escIntermediates*: seq[byte]
      escFinal*: byte
    of veCsiDispatch, veDcsHook:
      params*: seq[VtParam]
      intermediates*: seq[byte]
      final*: byte
      ignored*: bool       ## true if the sequence overflowed limits; caller should discard
    of veOscDispatch:
      oscData*: seq[byte]
      bellTerminated*: bool
    of veDcsUnhook:
      discard

  VtEmit* = proc (event: VtEvent) {.closure.}

  VtParser* = object
    state: State
    utf8Mode: bool         ## true keeps 0x80..0x9F available for UTF-8 continuation bytes
    intermediates: seq[byte]
    params: seq[VtParam]
    oscBuf: seq[byte]
    overflowed: bool       ## set when params/intermediates exceed limits
    paramStarted: bool     ## have we begun the current parameter yet?
    pendingStringEnd: bool ## we saw ESC while in a string state; waiting for '\\'
    preStringState: State  ## the string state we left to handle ST

func newVtParser*(utf8Mode = true): VtParser =
  ## Create a fresh parser in GROUND state.
  ##
  ## Modern terminal streams are normally UTF-8. In UTF-8 mode the parser
  ## treats bytes 0x80..0x9F as printable stream bytes so the caller's UTF-8
  ## decoder can reassemble characters such as box drawing and powerline
  ## symbols. Set `utf8Mode = false` for legacy streams that use raw 8-bit C1
  ## controls such as CSI 0x9B or ST 0x9C.
  VtParser(state: sGround, utf8Mode: utf8Mode)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func resetSeq(p: var VtParser) =
  p.intermediates.setLen(0)
  p.params.setLen(0)
  p.oscBuf.setLen(0)
  p.overflowed = false
  p.paramStarted = false
  p.pendingStringEnd = false

func ensureParam(p: var VtParser) =
  if not p.paramStarted:
    if p.params.len >= MaxParams:
      p.overflowed = true
    else:
      p.params.add VtParam(value: -1)
    p.paramStarted = true

func collectParamDigit(p: var VtParser, b: byte) =
  p.ensureParam()
  if p.params.len == 0 or p.overflowed: return
  var cur = p.params[^1].value
  if cur < 0: cur = 0
  # Clamp to a sane upper bound to prevent overflow attacks.
  if cur < 65535:
    cur = cur * 10 + int(b - byte('0'))
  p.params[^1].value = cur

func collectSubParam(p: var VtParser) =
  p.ensureParam()
  if p.params.len == 0 or p.overflowed: return
  if p.params[^1].subParams.len >= MaxSubParams:
    p.overflowed = true
  else:
    p.params[^1].subParams.add(-1)

func collectSubParamDigit(p: var VtParser, b: byte) =
  if p.params.len == 0 or p.params[^1].subParams.len == 0 or p.overflowed: return
  var cur = p.params[^1].subParams[^1]
  if cur < 0: cur = 0
  if cur < 65535:
    cur = cur * 10 + int(b - byte('0'))
  p.params[^1].subParams[^1] = cur

func paramSeparator(p: var VtParser) =
  p.ensureParam()
  if p.params.len >= MaxParams:
    p.overflowed = true
    p.paramStarted = true
  else:
    p.params.add VtParam(value: -1)
    p.paramStarted = true

func collectIntermediate(p: var VtParser, b: byte) =
  if p.intermediates.len >= MaxIntermediates:
    p.overflowed = true
  else:
    p.intermediates.add b

# ---------------------------------------------------------------------------
# Event emission shortcuts
# ---------------------------------------------------------------------------

proc emitCsi(p: var VtParser, emit: VtEmit, final: byte) =
  # If no parameter was ever seen, leave params empty (sequence had no params).
  emit VtEvent(
    kind: veCsiDispatch,
    params: p.params,
    intermediates: p.intermediates,
    final: final,
    ignored: p.overflowed,
  )

proc emitEsc(p: var VtParser, emit: VtEmit, final: byte) =
  emit VtEvent(
    kind: veEscDispatch,
    escIntermediates: p.intermediates,
    escFinal: final,
  )

proc emitOsc(p: var VtParser, emit: VtEmit, bellTerminated: bool) =
  emit VtEvent(
    kind: veOscDispatch,
    oscData: p.oscBuf,
    bellTerminated: bellTerminated,
  )

proc emitHook(p: var VtParser, emit: VtEmit, final: byte) =
  emit VtEvent(
    kind: veDcsHook,
    params: p.params,
    intermediates: p.intermediates,
    final: final,
    ignored: p.overflowed,
  )

# ---------------------------------------------------------------------------
# Transition: any-state entry for ESC / CAN / SUB / C1
# ---------------------------------------------------------------------------

func enterEscape(p: var VtParser) =
  p.resetSeq()
  p.state = sEscape

func enterCsi(p: var VtParser) =
  p.resetSeq()
  p.state = sCsiEntry

func enterDcs(p: var VtParser) =
  p.resetSeq()
  p.state = sDcsEntry

func enterOsc(p: var VtParser) =
  p.resetSeq()
  p.state = sOscString

func enterSosPmApc(p: var VtParser) =
  p.resetSeq()
  p.state = sSosPmApcString

# Anywhere transitions from Williams' diagram: 18, 1A, 1B, 80-9F (C1).
# Returns true if handled and caller should continue to next byte.
proc anywhere(p: var VtParser, b: byte, emit: VtEmit): bool =
  case b
  of 0x18, 0x1A:
    if p.state == sDcsPassthrough:
      emit VtEvent(kind: veDcsUnhook)
    emit VtEvent(kind: veExecute, byteVal: b)
    p.resetSeq()
    p.state = sGround
    return true
  of 0x1B:
    # If we were collecting a string, the ESC is the first byte of a
    # 7-bit ST terminator. Emit the pending string now; the following
    # 0x5C will be swallowed as a no-op in sEscape.
    case p.state
    of sOscString:
      p.emitOsc(emit, bellTerminated = false)
    of sDcsPassthrough:
      emit VtEvent(kind: veDcsUnhook)
    else:
      discard
    p.enterEscape()
    return true
  of 0x80..0x8F, 0x91..0x97, 0x99, 0x9A:
    if p.utf8Mode: return false
    # Executable C1 controls (except the ones below that enter string states).
    emit VtEvent(kind: veExecute, byteVal: b)
    p.resetSeq()
    p.state = sGround
    return true
  of 0x98, 0x9E, 0x9F:
    if p.utf8Mode: return false
    # SOS, PM, APC (8-bit).
    p.enterSosPmApc()
    return true
  of 0x9B:
    if p.utf8Mode: return false
    p.enterCsi(); return true
  of 0x9C:
    if p.utf8Mode: return false
    # ST (8-bit) — terminates strings.
    case p.state
    of sOscString:
      p.emitOsc(emit, bellTerminated = false)
    of sDcsPassthrough:
      emit VtEvent(kind: veDcsUnhook)
    of sSosPmApcString, sDcsIgnore:
      discard
    else:
      discard
    p.resetSeq()
    p.state = sGround
    return true
  of 0x9D:
    if p.utf8Mode: return false
    p.enterOsc(); return true
  of 0x90:
    if p.utf8Mode: return false
    p.enterDcs(); return true
  else:
    return false

# ---------------------------------------------------------------------------
# Per-state byte handling
# ---------------------------------------------------------------------------

proc stepGround(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F:
    emit VtEvent(kind: veExecute, byteVal: b)
  else:
    # 0x20..0x7F and 0x80+ (the latter only reached via UTF-8 continuation
    # bytes since C1 codes are intercepted by anywhere()).
    emit VtEvent(kind: vePrint, byteVal: b)

proc stepEscape(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F:
    emit VtEvent(kind: veExecute, byteVal: b)
  of 0x20..0x2F:
    p.collectIntermediate(b)
    p.state = sEscapeIntermediate
  of 0x30..0x4F, 0x51..0x57, 0x59, 0x5A, 0x60..0x7E:
    p.emitEsc(emit, b)
    p.resetSeq(); p.state = sGround
  of 0x5C:
    # ESC '\' is the 7-bit form of ST. If we reached sEscape from a
    # string state, the string was already emitted; otherwise this is
    # a stray ST and there is nothing to terminate. Either way, silently
    # return to ground without dispatching.
    p.resetSeq(); p.state = sGround
  of 0x50:            # 'P' → DCS
    p.enterDcs()
  of 0x58, 0x5E, 0x5F: # 'X' SOS, '^' PM, '_' APC
    p.enterSosPmApc()
  of 0x5B:            # '[' → CSI
    p.enterCsi()
  of 0x5D:            # ']' → OSC
    p.enterOsc()
  of 0x7F:
    discard
  else:
    discard

proc stepEscapeIntermediate(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F:
    emit VtEvent(kind: veExecute, byteVal: b)
  of 0x20..0x2F:
    p.collectIntermediate(b)
  of 0x30..0x7E:
    p.emitEsc(emit, b)
    p.resetSeq(); p.state = sGround
  of 0x7F:
    discard
  else:
    discard

proc stepCsiEntry(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F:
    emit VtEvent(kind: veExecute, byteVal: b)
  of 0x20..0x2F:
    p.collectIntermediate(b)
    p.state = sCsiIntermediate
  of 0x30..0x39:
    p.collectParamDigit(b)
    p.state = sCsiParam
  of 0x3A:
    p.collectSubParam()
    p.state = sCsiParam
  of 0x3B:
    p.paramSeparator()
    p.state = sCsiParam
  of 0x3C..0x3F:
    # Private-marker introducer (e.g. '?').
    p.collectIntermediate(b)
    p.state = sCsiParam
  of 0x40..0x7E:
    p.emitCsi(emit, b)
    p.resetSeq(); p.state = sGround
  of 0x7F:
    discard
  else:
    discard

proc stepCsiParam(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F:
    emit VtEvent(kind: veExecute, byteVal: b)
  of 0x30..0x39:
    # Digit — extending whichever param/sub-param was last opened.
    if p.params.len > 0 and p.params[^1].subParams.len > 0:
      p.collectSubParamDigit(b)
    else:
      p.collectParamDigit(b)
  of 0x3A:
    p.collectSubParam()
  of 0x3B:
    p.paramSeparator()
  of 0x20..0x2F:
    p.collectIntermediate(b)
    p.state = sCsiIntermediate
  of 0x3C..0x3F:
    # Illegal here per spec → ignore the whole sequence.
    p.state = sCsiIgnore
  of 0x40..0x7E:
    p.emitCsi(emit, b)
    p.resetSeq(); p.state = sGround
  of 0x7F:
    discard
  else:
    discard

proc stepCsiIntermediate(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F:
    emit VtEvent(kind: veExecute, byteVal: b)
  of 0x20..0x2F:
    p.collectIntermediate(b)
  of 0x30..0x3F:
    p.state = sCsiIgnore
  of 0x40..0x7E:
    p.emitCsi(emit, b)
    p.resetSeq(); p.state = sGround
  of 0x7F:
    discard
  else:
    discard

proc stepCsiIgnore(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F:
    emit VtEvent(kind: veExecute, byteVal: b)
  of 0x40..0x7E:
    p.resetSeq(); p.state = sGround
  else:
    discard

proc stepDcsEntry(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F, 0x7F:
    discard
  of 0x20..0x2F:
    p.collectIntermediate(b); p.state = sDcsIntermediate
  of 0x30..0x39:
    p.collectParamDigit(b); p.state = sDcsParam
  of 0x3A:
    p.collectSubParam(); p.state = sDcsParam
  of 0x3B:
    p.paramSeparator(); p.state = sDcsParam
  of 0x3C..0x3F:
    p.collectIntermediate(b); p.state = sDcsParam
  of 0x40..0x7E:
    p.emitHook(emit, b); p.state = sDcsPassthrough
  else:
    discard

proc stepDcsParam(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F, 0x7F:
    discard
  of 0x30..0x39:
    if p.params.len > 0 and p.params[^1].subParams.len > 0:
      p.collectSubParamDigit(b)
    else:
      p.collectParamDigit(b)
  of 0x3A:
    p.collectSubParam()
  of 0x3B:
    p.paramSeparator()
  of 0x20..0x2F:
    p.collectIntermediate(b); p.state = sDcsIntermediate
  of 0x3C..0x3F:
    p.state = sDcsIgnore
  of 0x40..0x7E:
    p.emitHook(emit, b); p.state = sDcsPassthrough
  else:
    discard

proc stepDcsIntermediate(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F, 0x7F:
    discard
  of 0x20..0x2F:
    p.collectIntermediate(b)
  of 0x30..0x3F:
    p.state = sDcsIgnore
  of 0x40..0x7E:
    p.emitHook(emit, b); p.state = sDcsPassthrough
  else:
    discard

proc stepDcsPassthrough(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x00..0x17, 0x19, 0x1C..0x1F, 0x20..0x7E:
    emit VtEvent(kind: veDcsPut, byteVal: b)
  of 0x7F:
    discard
  else:
    discard

proc stepDcsIgnore(p: var VtParser, b: byte, emit: VtEmit) =
  # Consume everything until ST / CAN / SUB (handled by anywhere()).
  discard

proc stepOscString(p: var VtParser, b: byte, emit: VtEmit) =
  case b
  of 0x07: # BEL — legacy OSC terminator
    p.emitOsc(emit, bellTerminated = true)
    p.resetSeq(); p.state = sGround
  of 0x20..0xFF:
    p.oscBuf.add b
  else:
    discard

proc stepSosPmApcString(p: var VtParser, b: byte, emit: VtEmit) =
  discard  # SOS/PM/APC content is discarded; terminators handled by anywhere()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc advance*(p: var VtParser, b: byte, emit: VtEmit) =
  ## Feed one byte into the parser. `emit` is invoked zero or more times.
  if p.anywhere(b, emit): return
  case p.state
  of sGround:             p.stepGround(b, emit)
  of sEscape:             p.stepEscape(b, emit)
  of sEscapeIntermediate: p.stepEscapeIntermediate(b, emit)
  of sCsiEntry:           p.stepCsiEntry(b, emit)
  of sCsiParam:           p.stepCsiParam(b, emit)
  of sCsiIntermediate:    p.stepCsiIntermediate(b, emit)
  of sCsiIgnore:          p.stepCsiIgnore(b, emit)
  of sDcsEntry:           p.stepDcsEntry(b, emit)
  of sDcsParam:           p.stepDcsParam(b, emit)
  of sDcsIntermediate:    p.stepDcsIntermediate(b, emit)
  of sDcsPassthrough:     p.stepDcsPassthrough(b, emit)
  of sDcsIgnore:          p.stepDcsIgnore(b, emit)
  of sOscString:          p.stepOscString(b, emit)
  of sSosPmApcString:     p.stepSosPmApcString(b, emit)

proc feed*(p: var VtParser, data: openArray[byte], emit: VtEmit) =
  ## Feed a buffer of bytes. Convenience wrapper around `advance`.
  for b in data:
    p.advance(b, emit)

proc feed*(p: var VtParser, data: string, emit: VtEmit) =
  ## String overload for UTF-8 / ASCII input.
  for ch in data:
    p.advance(byte(ch), emit)

func paramOr*(params: openArray[VtParam], idx: int, default: int): int =
  ## Helper: read `params[idx].value`, substituting `default` when missing/defaulted.
  if idx < 0 or idx >= params.len: return default
  if params[idx].value < 0: return default
  params[idx].value

func inGround*(p: VtParser): bool = p.state == sGround
  ## Useful for tests and for callers that want to know if the stream
  ## has settled on a boundary (no partial sequence in flight).
