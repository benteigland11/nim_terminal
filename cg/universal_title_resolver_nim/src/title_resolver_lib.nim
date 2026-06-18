## Dynamic title and label resolver for terminal sessions.
##
## Resolves a display string for tabs or windows by arbitrating between
## explicit titles (OSC), foreground process names, and CWD labels
## based on a configurable priority policy.

import std/[strutils, unicode]

type
  TitlePolicy* = enum
    tpPreferTitle    ## OSC Title > Program Name > CWD
    tpPreferProgram  ## Program Name > OSC Title > CWD
    tpCwdOnly        ## Always CWD

  TitleState* = object
    oscTitle*: string
    programName*: string
    cwd*: string
    policy*: TitlePolicy

func newTitleState*(policy = tpPreferTitle): TitleState =
  TitleState(policy: policy)

func cwdLabel*(path: string): string =
  ## Compact label for a directory path.
  if path == "/" or path == "": return "/"
  let normalized = path.strip(trailing = true, chars = {'/', '\\'})
  let slash = max(normalized.rfind('/'), normalized.rfind('\\'))
  if slash < 0 or slash >= normalized.high:
    normalized
  else:
    normalized[slash + 1 .. ^1]

func isLikelyTitleStart(r: Rune): bool =
  let code = int32(r)
  (code >= int32(ord('A')) and code <= int32(ord('Z'))) or
    (code >= int32(ord('a')) and code <= int32(ord('z'))) or
    (code >= int32(ord('0')) and code <= int32(ord('9'))) or
    r in [Rune(ord('~')), Rune(ord('/')), Rune(ord('\\')), Rune(ord('.')),
          Rune(ord('_')), Rune(ord('-')), Rune(ord('$'))]

func hasLikelyTitleStart(text: string): bool =
  for r in text.runes:
    if r.isWhiteSpace:
      continue
    return r.isLikelyTitleStart
  false

func stripLeadingDecorativeToken(text: string): string =
  var first = Rune(0)
  var firstSeen = false
  var byteIndex = 0
  for r in text.runes:
    if not firstSeen:
      first = r
      firstSeen = true
    if firstSeen and r.isWhiteSpace:
      let rest = text[byteIndex .. ^1].strip()
      if not first.isLikelyTitleStart and rest.hasLikelyTitleStart:
        return rest
      return text
    byteIndex += ($r).len
  text

func cleanTitle*(title: string): string =
  ## Remove control bytes and leading icon/mojibake prefixes from display titles.
  var normalized = ""
  var previousSpace = false
  for r in title.runes:
    let code = int32(r)
    if code == 0xFFFD'i32 or code < 32'i32 or (code >= 0x80'i32 and code <= 0x9F'i32):
      continue
    if r.isWhiteSpace:
      if normalized.len > 0 and not previousSpace:
        normalized.add ' '
        previousSpace = true
    else:
      normalized.add r
      previousSpace = false
  normalized.strip().stripLeadingDecorativeToken()

func resolve*(state: TitleState): string =
  ## Returns the best display string based on current state and policy.
  case state.policy
  of tpCwdOnly:
    return cwdLabel(state.cwd)
    
  of tpPreferTitle:
    let title = cleanTitle(state.oscTitle)
    if title.len > 0:
      return title
    let program = cleanTitle(state.programName)
    if program.len > 0:
      return program
    return cwdLabel(state.cwd)
    
  of tpPreferProgram:
    let program = cleanTitle(state.programName)
    if program.len > 0:
      return program
    let title = cleanTitle(state.oscTitle)
    if title.len > 0:
      return title
    return cwdLabel(state.cwd)

proc updateOscTitle*(state: var TitleState, title: string): bool =
  ## Returns true if the resolved title changed.
  let old = state.resolve()
  state.oscTitle = title
  state.resolve() != old

proc updateProgramName*(state: var TitleState, name: string): bool =
  ## Returns true if the resolved title changed.
  let old = state.resolve()
  state.programName = name
  state.resolve() != old

proc updateCwd*(state: var TitleState, path: string): bool =
  ## Returns true if the resolved title changed.
  let old = state.resolve()
  state.cwd = path
  state.resolve() != old
