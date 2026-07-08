## Lightweight source tokenizer with language-specific lexers.

import std/[os, sets, strutils]

type
  SourceTokenKind* = enum
    stkPlain
    stkComment
    stkString
    stkNumber
    stkKeyword
    stkType
    stkOperator

  SourceToken* = object
    kind*: SourceTokenKind
    start*, endEx*: int

const nimKeywords* = toHashSet([
  "proc", "func", "const", "var", "let", "type", "object", "enum", "import", "from",
  "include", "when", "if", "elif", "else", "case", "of", "discard", "return", "for",
  "while", "break", "continue", "block", "template", "macro", "method", "iterator",
  "converter", "raise", "try", "except", "finally", "defer", "static", "using",
  "bind", "addr", "unsafeAddr", "out", "ref", "ptr", "distinct", "concept", "mixin",
  "echo", "do", "nil", "true", "false",
])

const nimTypes* = toHashSet([
  "int", "float", "string", "bool", "char", "byte", "cstring", "seq", "array",
  "set", "openArray", "void", "auto", "sink", "lent", "owned", "unown",
])

func inferSourceLanguage*(path: string): string =
  var ext = splitFile(path).ext.toLowerAscii()
  if ext.len > 0 and ext[0] == '.':
    ext = ext[1 .. ^1]
  case ext
  of "nim", "nims": "nim"
  of "json": "json"
  of "py": "python"
  of "js", "ts", "tsx": "javascript"
  of "md", "markdown": "markdown"
  else: "plain"

proc addToken(tokens: var seq[SourceToken]; kind: SourceTokenKind; start, endEx: int) =
  if endEx > start:
    tokens.add SourceToken(kind: kind, start: start, endEx: endEx)

proc lexPlainSource*(source: string): seq[SourceToken] =
  if source.len > 0:
    result.add SourceToken(kind: stkPlain, start: 0, endEx: source.len)

proc lexNimSource*(source: string): seq[SourceToken] =
  var i = 0
  while i < source.len:
    let ch = source[i]
    if ch == '#':
      let start = i
      while i < source.len and source[i] != '\n':
        inc i
      addToken(result, stkComment, start, i)
    elif ch == '"' or ch == '\'':
      let quote = ch
      let start = i
      inc i
      while i < source.len:
        if source[i] == '\\' and i + 1 < source.len:
          inc i, 2
          continue
        if source[i] == quote:
          inc i
          break
        inc i
      addToken(result, stkString, start, i)
    elif ch in {'0'..'9'}:
      let start = i
      while i < source.len and source[i] in {'0'..'9', '_', '.', 'e', 'E', '+', '-'}:
        inc i
      addToken(result, stkNumber, start, i)
    elif ch in {'a'..'z', 'A'..'Z', '_'}:
      let start = i
      while i < source.len and source[i] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
        inc i
      let word = source[start ..< i]
      if word in nimKeywords:
        addToken(result, stkKeyword, start, i)
      elif word in nimTypes:
        addToken(result, stkType, start, i)
      else:
        addToken(result, stkPlain, start, i)
    elif ch in {'(', ')', '[', ']', '{', '}', ':', '.', ',', ';', '=', '+', '-', '*', '/', '<', '>', '@', '$', '&', '|', '^', '~'}:
      addToken(result, stkOperator, i, i + 1)
      inc i
    else:
      let start = i
      inc i
      addToken(result, stkPlain, start, i)

proc lexJsonSource*(source: string): seq[SourceToken] =
  var i = 0
  while i < source.len:
    let ch = source[i]
    if ch <= ' ':
      inc i
      continue
    if ch == '"':
      let start = i
      inc i
      while i < source.len:
        if source[i] == '\\' and i + 1 < source.len:
          inc i, 2
          continue
        if source[i] == '"':
          inc i
          break
        inc i
      addToken(result, stkString, start, i)
    elif ch in {'0'..'9', '-'}:
      let start = i
      while i < source.len and source[i] in {'0'..'9', '-', '+', '.', 'e', 'E'}:
        inc i
      addToken(result, stkNumber, start, i)
    elif i + 4 <= source.len and source[i ..< i + 4] == "true":
      addToken(result, stkKeyword, i, i + 4); inc i, 4
    elif i + 5 <= source.len and source[i ..< i + 5] == "false":
      addToken(result, stkKeyword, i, i + 5); inc i, 5
    elif i + 4 <= source.len and source[i ..< i + 4] == "null":
      addToken(result, stkKeyword, i, i + 4); inc i, 4
    elif ch in {'{', '}', '[', ']', ':', ','}:
      addToken(result, stkOperator, i, i + 1); inc i
    else:
      let start = i
      inc i
      addToken(result, stkPlain, start, i)

proc lexSource*(source, language: string): seq[SourceToken] =
  case language
  of "nim": lexNimSource(source)
  of "json": lexJsonSource(source)
  else: lexPlainSource(source)
