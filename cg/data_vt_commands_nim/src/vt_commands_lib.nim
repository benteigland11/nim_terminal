## Typed VT command translator.
##
## Turns raw CSI / ESC / OSC / C0-control dispatches from a terminal
## escape-sequence parser into a typed `VtCommand` variant. The intent is
## to move semantic interpretation (which CSI final means "cursor up"?
## which OSC prefix means "set title"?) out of the screen-buffer caller
## and into one small, well-tested table.
##
## This widget is parser-agnostic: it depends on no other widget. Callers
## translate their own parser's event fields into the tiny `DispatchParam`
## type below and call the right `translate*` entry point.
##
## Coverage is the xterm-common subset — enough to correctly drive vim,
## tmux, htop, and most TUI frameworks. Unknown sequences produce
## `cmdUnknown` so the caller can log/trace rather than silently drop.

const
  DefaultScrollRegionBottom* = -1   ## sentinel meaning "end of screen"

import std/strutils

# ---------------------------------------------------------------------------
# Input shape
# ---------------------------------------------------------------------------

type
  DispatchParam* = object
    ## A CSI/DCS parameter as delivered by a parser. `value` is -1 when
    ## the parameter was omitted (defaulted); sub-parameters are the
    ## colon-separated ITU T.416 form.
    value*: int
    subParams*: seq[int]

func param*(value: int, subParams: seq[int] = @[]): DispatchParam =
  DispatchParam(value: value, subParams: subParams)

func paramOr*(params: openArray[DispatchParam], idx: int, default: int): int =
  if idx < 0 or idx >= params.len: return default
  if params[idx].value < 0: return default
  params[idx].value

func hasPrivateMarker*(intermediates: openArray[byte], marker: char): bool =
  for b in intermediates:
    if b == byte(marker): return true
  false

# ---------------------------------------------------------------------------
# Command variant
# ---------------------------------------------------------------------------

type
  EraseMode* = enum
    emToEnd
    emToStart
    emAll

  VtCommandKind* = enum
    cmdPrint              ## already-decoded printable rune
    cmdExecute            ## a C0/C1 byte the translator did not specialize
    cmdLineFeed           ## LF / IND
    cmdReverseIndex       ## RI (ESC M)
    cmdCarriageReturn
    cmdBackspace
    cmdHorizontalTab
    cmdBell
    cmdCursorUp
    cmdCursorDown
    cmdCursorForward
    cmdCursorBackward
    cmdCursorNextLine
    cmdCursorPrevLine
    cmdCursorTo
    cmdCursorToColumn
    cmdCursorToRow
    cmdEraseInLine
    cmdEraseInDisplay
    cmdEraseChars
    cmdInsertLines
    cmdDeleteLines
    cmdInsertChars
    cmdDeleteChars
    cmdScrollUp
    cmdScrollDown
    cmdSaveCursor
    cmdRestoreCursor
    cmdSetSgr
    cmdSetScrollRegion
    cmdSetMode            ## SM / DECSET
    cmdResetMode          ## RM / DECRST
    cmdSetTabStop
    cmdClearTabStop
    cmdClearAllTabStops
    cmdRequestStatusReport    ## DSR (CSI 6 n, etc)
    cmdRequestDeviceAttributes ## DA / DA2
    cmdRequestWindowReport     ## CSI t
    cmdSetTitle           ## OSC 0 / 2
    cmdSetIconName        ## OSC 1
    cmdHyperlink          ## OSC 8
    cmdDcsPassthrough     ## DCS hook + put + unhook accumulated
    cmdClipboardRequest   ## OSC 52
    cmdSetPaletteColor    ## OSC 4
    cmdSetThemeColor      ## OSC 10 (fg), 11 (bg), 12 (cursor)
    cmdReset              ## RIS (ESC c)
    cmdIgnored            ## known-good sequence the translator chose to drop
    cmdUnknown            ## not recognized — raw bytes exposed for tracing

  VtCommand* = object
    case kind*: VtCommandKind
    of cmdPrint:
      rune*: uint32
      width*: int            ## 0/1/2 as reported by the caller's decoder
    of cmdExecute, cmdUnknown:
      rawByte*: byte         ## original C0/C1 byte or CSI/ESC final
      rawFinal*: byte        ## duplicated for symmetry with CSI unknowns
    of cmdRequestStatusReport, cmdRequestDeviceAttributes, cmdRequestWindowReport:
      requestArgs*: seq[DispatchParam]
      requestPrivate*: bool
    of cmdDcsPassthrough:
      dcsParams*: seq[DispatchParam]
      dcsIntermediates*: seq[byte]
      dcsFinal*: byte
      dcsData*: seq[byte]
    of cmdCursorUp, cmdCursorDown, cmdCursorForward, cmdCursorBackward,
       cmdCursorNextLine, cmdCursorPrevLine,
       cmdInsertLines, cmdDeleteLines,
       cmdInsertChars, cmdDeleteChars, cmdEraseChars,
       cmdScrollUp, cmdScrollDown:
      count*: int
    of cmdCursorTo:
      row*, col*: int
    of cmdCursorToColumn:
      absCol*: int
    of cmdCursorToRow:
      absRow*: int
    of cmdEraseInLine, cmdEraseInDisplay:
      eraseMode*: EraseMode
    of cmdSetSgr:
      sgrParams*: seq[DispatchParam]
    of cmdSetScrollRegion:
      regionTop*, regionBottom*: int
    of cmdSetMode, cmdResetMode:
      modeCode*: int
      privateMode*: bool
    of cmdSetTitle, cmdSetIconName:
      text*: string
    of cmdHyperlink:
      uri*: string
      hyperlinkParams*: string
    of cmdClipboardRequest:
      clipboardSelector*: string
      base64Data*: string
    of cmdSetPaletteColor:
      paletteIndex*: int
      paletteColorSpec*: string
    of cmdSetThemeColor:
      themeColorItem*: int # 10, 11, 12
      themeColorSpec*: string
    else:
      discard

# ---------------------------------------------------------------------------
# Constructors (kept private to the .nim)
# ---------------------------------------------------------------------------

template cmd(k: VtCommandKind): VtCommand = VtCommand(kind: k)
template cmdN(k: static VtCommandKind, n: int): VtCommand =
  VtCommand(kind: k, count: n)

func eraseModeFrom(params: openArray[DispatchParam]): EraseMode =
  case paramOr(params, 0, 0)
  of 1: emToStart
  of 2: emAll
  else: emToEnd

func countFrom(params: openArray[DispatchParam]): int =
  max(1, paramOr(params, 0, 1))

# ---------------------------------------------------------------------------
# Print / Execute
# ---------------------------------------------------------------------------

func translatePrint*(rune: uint32, width: int = 1): VtCommand =
  ## Caller has already UTF-8 decoded the codepoint; this just wraps it.
  VtCommand(kind: cmdPrint, rune: rune, width: width)

func translateExecute*(b: byte): VtCommand =
  ## Map a C0/C1 control byte to a semantic command. Unknown bytes are
  ## returned as `cmdExecute` so the caller can pass them through.
  case b
  of 0x07: cmd(cmdBell)
  of 0x08: cmd(cmdBackspace)
  of 0x09: cmd(cmdHorizontalTab)
  of 0x0A, 0x0B, 0x0C, 0x85: cmd(cmdLineFeed)   # LF, VT, FF, NEL all advance one line
  of 0x0D: cmd(cmdCarriageReturn)
  of 0x8D: cmd(cmdReverseIndex)                 # 8-bit RI
  else:
    VtCommand(kind: cmdExecute, rawByte: b, rawFinal: b)

# ---------------------------------------------------------------------------
# CSI
# ---------------------------------------------------------------------------

proc translateCsi*(
    params: openArray[DispatchParam],
    intermediates: openArray[byte],
    final: byte,
): VtCommand =
  ## Translate a completed CSI sequence into a typed command.
  ##
  ## `intermediates` carries any `< = > ?` private-marker bytes that
  ## preceded the parameters, plus `SPACE !` etc. that may follow them.
  let isPrivate = hasPrivateMarker(intermediates, '?')
  let n = countFrom(params)
  case char(final)
  of 'A': return cmdN(cmdCursorUp, n)
  of 'B', 'e': return cmdN(cmdCursorDown, n)
  of 'C', 'a': return cmdN(cmdCursorForward, n)
  of 'D': return cmdN(cmdCursorBackward, n)
  of 'E': return cmdN(cmdCursorNextLine, n)
  of 'F': return cmdN(cmdCursorPrevLine, n)
  of 'G', '`':
    return VtCommand(kind: cmdCursorToColumn, absCol: max(0, paramOr(params, 0, 1) - 1))
  of 'd':
    return VtCommand(kind: cmdCursorToRow, absRow: max(0, paramOr(params, 0, 1) - 1))
  of 'H', 'f':
    let row = max(0, paramOr(params, 0, 1) - 1)
    let col = max(0, paramOr(params, 1, 1) - 1)
    return VtCommand(kind: cmdCursorTo, row: row, col: col)
  of 'J':
    return VtCommand(kind: cmdEraseInDisplay, eraseMode: eraseModeFrom(params))
  of 'K':
    return VtCommand(kind: cmdEraseInLine, eraseMode: eraseModeFrom(params))
  of 'L': return cmdN(cmdInsertLines, n)
  of 'M': return cmdN(cmdDeleteLines, n)
  of 'P': return cmdN(cmdDeleteChars, n)
  of 'S': return cmdN(cmdScrollUp, n)
  of 'T': return cmdN(cmdScrollDown, n)
  of 'X': return cmdN(cmdEraseChars, n)
  of '@': return cmdN(cmdInsertChars, n)
  of 'm':
    var copy: seq[DispatchParam] = @[]
    for p in params: copy.add p
    return VtCommand(kind: cmdSetSgr, sgrParams: copy)
  of 'r':
    let top = max(0, paramOr(params, 0, 1) - 1)
    let bot = paramOr(params, 1, 0)
    let bottom = if bot <= 0: DefaultScrollRegionBottom else: bot - 1
    return VtCommand(kind: cmdSetScrollRegion,
                     regionTop: top, regionBottom: bottom)
  of 'h':
    return VtCommand(kind: cmdSetMode,
                     modeCode: paramOr(params, 0, 0),
                     privateMode: isPrivate)
  of 'l':
    return VtCommand(kind: cmdResetMode,
                     modeCode: paramOr(params, 0, 0),
                     privateMode: isPrivate)
  of 's':
    return cmd(cmdSaveCursor)
  of 'u':
    return cmd(cmdRestoreCursor)
  of 'n':
    var copy: seq[DispatchParam] = @[]
    for p in params: copy.add p
    return VtCommand(kind: cmdRequestStatusReport, requestArgs: copy, requestPrivate: isPrivate)
  of 'c':
    var copy: seq[DispatchParam] = @[]
    for p in params: copy.add p
    return VtCommand(kind: cmdRequestDeviceAttributes, requestArgs: copy, requestPrivate: isPrivate)
  of 't':
    var copy: seq[DispatchParam] = @[]
    for p in params: copy.add p
    return VtCommand(kind: cmdRequestWindowReport, requestArgs: copy, requestPrivate: isPrivate)
  of 'g':
    case paramOr(params, 0, 0)
    of 3: return cmd(cmdClearAllTabStops)
    else: return cmd(cmdClearTabStop)
  else:
    return VtCommand(kind: cmdUnknown, rawByte: final, rawFinal: final)

proc translateDcs*(
    params: openArray[DispatchParam],
    intermediates: openArray[byte],
    final: byte,
    data: seq[byte],
): VtCommand =
  ## Translate a completed and accumulated DCS sequence.
  var pseq: seq[DispatchParam] = @[]
  for p in params: pseq.add p
  var iseq: seq[byte] = @[]
  for i in intermediates: iseq.add i
  VtCommand(
    kind: cmdDcsPassthrough,
    dcsParams: pseq,
    dcsIntermediates: iseq,
    dcsFinal: final,
    dcsData: data
  )

# ---------------------------------------------------------------------------
# ESC (Fp/Fe/Fs, no CSI introducer)
# ---------------------------------------------------------------------------

proc translateEsc*(intermediates: openArray[byte], final: byte): VtCommand =
  if intermediates.len == 0:
    case char(final)
    of '7': return cmd(cmdSaveCursor)
    of '8': return cmd(cmdRestoreCursor)
    of 'D': return cmd(cmdLineFeed)          # IND — index (down one line)
    of 'E': return cmdN(cmdCursorNextLine, 1)  # NEL
    of 'H': return cmd(cmdSetTabStop)         # HTS
    of 'M': return cmd(cmdReverseIndex)       # RI
    of 'c': return cmd(cmdReset)              # RIS
    else: discard
  VtCommand(kind: cmdUnknown, rawByte: final, rawFinal: final)

# ---------------------------------------------------------------------------
# OSC
# ---------------------------------------------------------------------------

proc findChar(data: openArray[byte], ch: char, start: int = 0): int =
  for i in start ..< data.len:
    if data[i] == byte(ch): return i
  -1

proc asciiString(data: openArray[byte], startIdx, endIdx: int): string =
  result = newStringOfCap(max(0, endIdx - startIdx))
  for i in startIdx ..< endIdx:
    result.add char(data[i])

proc parsePrefix(data: openArray[byte]): tuple[code: int, bodyStart: int] =
  ## OSC payloads are "<number> ; <body>". Returns (-1, 0) when unparsable.
  var i = 0
  var n = 0
  var any = false
  while i < data.len and data[i] >= byte('0') and data[i] <= byte('9'):
    n = n * 10 + int(data[i] - byte('0'))
    any = true
    inc i
  if not any: return (-1, 0)
  if i >= data.len or data[i] != byte(';'): return (-1, 0)
  (n, i + 1)

proc translateOsc*(data: openArray[byte]): VtCommand =
  ## Translate an OSC payload (everything between `ESC ]` and the ST/BEL
  ## terminator, terminator bytes not included) into a typed command.
  let (code, body) = parsePrefix(data)
  if code < 0:
    return VtCommand(kind: cmdUnknown, rawByte: 0, rawFinal: 0)
  case code
  of 0, 2:
    return VtCommand(kind: cmdSetTitle, text: asciiString(data, body, data.len))
  of 1:
    return VtCommand(kind: cmdSetIconName, text: asciiString(data, body, data.len))
  of 8:
    # OSC 8 ; params ; uri
    let sep = findChar(data, ';', body)
    if sep < 0:
      return VtCommand(kind: cmdHyperlink, uri: "",
                       hyperlinkParams: asciiString(data, body, data.len))
    return VtCommand(kind: cmdHyperlink,
                     hyperlinkParams: asciiString(data, body, sep),
                     uri: asciiString(data, sep + 1, data.len))
  of 52:
    # OSC 52 ; pc ; data
    let sep = findChar(data, ';', body)
    if sep < 0:
      return VtCommand(kind: cmdClipboardRequest, clipboardSelector: "",
                       base64Data: asciiString(data, body, data.len))
    return VtCommand(kind: cmdClipboardRequest,
                     clipboardSelector: asciiString(data, body, sep),
                     base64Data: asciiString(data, sep + 1, data.len))
  of 4:
    # OSC 4 ; index ; spec
    let sep = findChar(data, ';', body)
    if sep < 0: return VtCommand(kind: cmdIgnored)
    try:
      let idx = parseInt(asciiString(data, body, sep))
      return VtCommand(kind: cmdSetPaletteColor, paletteIndex: idx,
                       paletteColorSpec: asciiString(data, sep + 1, data.len))
    except: return VtCommand(kind: cmdIgnored)
  of 10, 11, 12:
    # OSC 10/11/12 ; spec
    return VtCommand(kind: cmdSetThemeColor, themeColorItem: code,
                     themeColorSpec: asciiString(data, body, data.len))
  else:
    return VtCommand(kind: cmdIgnored)
