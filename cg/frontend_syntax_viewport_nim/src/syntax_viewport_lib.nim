## Map tokenized source into wrapped, viewport-clipped colored runs.

import std/[strutils, unicode]

type
  SourceTokenKind* = enum
    tvPlain
    tvComment
    tvString
    tvNumber
    tvKeyword
    tvType
    tvOperator

  ColoredRun* = object
    text*: string
    kind*: SourceTokenKind

  SourceViewportLine* = object
    runs*: seq[ColoredRun]

  SourceViewport* = object
    lines*: seq[SourceViewportLine]
    totalLines*: int
    scrollRow*: int

  SourceTokenSpan* = tuple[start, endEx: int, kind: SourceTokenKind]

func mapLexerTokenKind*(raw: int): SourceTokenKind =
  ## Host passes enum ordinal from its lexer; keep viewport decoupled.
  case raw
  of 1: tvComment
  of 2: tvString
  of 3: tvNumber
  of 4: tvKeyword
  of 5: tvType
  of 6: tvOperator
  else: tvPlain

func tokenKindFromName*(name: string): SourceTokenKind =
  case name
  of "comment": tvComment
  of "string": tvString
  of "number": tvNumber
  of "keyword": tvKeyword
  of "type": tvType
  of "operator": tvOperator
  else: tvPlain

proc kindAtOffset(
  kinds: openArray[SourceTokenSpan];
  offset: int,
): SourceTokenKind =
  for item in kinds:
    if offset >= item.start and offset < item.endEx:
      return item.kind
  tvPlain

proc buildSourceViewport*(
  source: string;
  kinds: openArray[SourceTokenSpan];
  cols, maxRows, scrollRow: int,
): SourceViewport =
  if cols <= 0 or maxRows <= 0:
    return
  var allLines: seq[SourceViewportLine] = @[]
  var current = SourceViewportLine(runs: @[])
  var col = 0
  proc flushLine() =
    if current.runs.len == 0:
      current.runs.add ColoredRun(text: "", kind: tvPlain)
    allLines.add current
    current = SourceViewportLine(runs: @[])
    col = 0
  proc appendRuneStr(s: string; kind: SourceTokenKind) =
    if current.runs.len == 0 or current.runs[^1].kind != kind:
      current.runs.add ColoredRun(text: s, kind: kind)
    else:
      current.runs[^1].text.add s
  var i = 0
  for rune in source.runes:
    let rStr = $rune
    if rStr == "\r":
      continue
    if rStr == "\n":
      flushLine()
      i += rStr.len
      continue
    let kind = kindAtOffset(kinds, i)
    if rStr == "\t":
      let spaces = 4 - (col mod 4)
      for _ in 0 ..< spaces:
        if col >= cols:
          flushLine()
        appendRuneStr(" ", kind)
        inc col
    else:
      if col >= cols:
        flushLine()
      appendRuneStr(rStr, kind)
      inc col
    i += rStr.len
  if current.runs.len > 0 or allLines.len == 0:
    flushLine()
  result.totalLines = allLines.len
  result.scrollRow = max(0, min(scrollRow, max(0, allLines.len - maxRows)))
  let endRow = min(allLines.len, result.scrollRow + maxRows)
  if result.scrollRow < endRow:
    result.lines = allLines[result.scrollRow ..< endRow]
