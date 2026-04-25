## Universal Link Detector.
##
## Scans text to identify actionable links (URLs, file paths) and their
## bounding indices within the string. Designed to be fast and pure Nim
## without relying on external PCRE libraries.

import std/strutils

type
  LinkKind* = enum
    lkUrl
    lkPath

  DetectedLink* = object
    kind*: LinkKind
    text*: string
    startIdx*: int
    endIdx*: int  ## Exclusive (like Nim's typical slices/lengths)

func isTerminalPunctuation(c: char): bool =
  c in {'.', ',', ';', ':', '!', '?', ')', ']', '}'}

func scanForUrls(s: string): seq[DetectedLink] =
  var results: seq[DetectedLink] = @[]
  var i = 0
  let prefixes = ["http://", "https://"]

  while i < s.len:
    var foundPrefix = ""
    for p in prefixes:
      if i + p.len <= s.len and s[i ..< i + p.len] == p:
        foundPrefix = p
        break

    if foundPrefix.len > 0:
      let startIdx = i
      i += foundPrefix.len
      while i < s.len and not (s[i] in {' ', '\t', '\r', '\n', '<', '>', '"', '\''}):
        inc i

      # Backtrack over terminal punctuation
      var endIdx = i
      while endIdx > startIdx + foundPrefix.len and isTerminalPunctuation(s[endIdx - 1]):
        dec endIdx

      if endIdx > startIdx + foundPrefix.len:
        results.add DetectedLink(
          kind: lkUrl,
          text: s[startIdx ..< endIdx],
          startIdx: startIdx,
          endIdx: endIdx
        )
      i = endIdx
    else:
      inc i
  results

func detectLinks*(text: string): seq[DetectedLink] =
  ## Find all URLs (and eventually file paths) in a given string.
  result = @[]
  result.add scanForUrls(text)
  # TODO: Add file path detection (e.g., starts with / or C:\ and exists)
