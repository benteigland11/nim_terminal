## Resolve candidate paths and select the first available file.

import std/[options, os, strutils]

proc resolveCandidatePath*(candidate: string, baseDir = ""): string =
  ## Expand a single candidate path.
  ##
  ## Empty candidates stay empty. Tilde-prefixed paths expand through the
  ## platform's home directory. Relative paths are anchored to baseDir when it
  ## is provided.
  let trimmed = candidate.strip()
  if trimmed.len == 0:
    return ""
  result = expandTilde(trimmed)
  if baseDir.len > 0 and not result.isAbsolute:
    result = baseDir / result

proc firstExistingPath*(candidates: openArray[string], baseDir = ""): Option[string] =
  ## Return the first candidate that exists on disk.
  for candidate in candidates:
    let path = resolveCandidatePath(candidate, baseDir)
    if path.len > 0 and fileExists(path):
      return some(path)
  none(string)

proc existingPaths*(candidates: openArray[string], baseDir = ""): seq[string] =
  ## Return every candidate that exists on disk after expansion.
  for candidate in candidates:
    let path = resolveCandidatePath(candidate, baseDir)
    if path.len > 0 and fileExists(path):
      result.add path
