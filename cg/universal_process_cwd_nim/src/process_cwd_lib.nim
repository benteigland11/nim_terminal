## Resolve and label a process current working directory.

import std/[options, os, strutils]

proc processCwd*(pid: int, procRoot = "/proc"): Option[string] =
  ## Resolve a process current working directory from a procfs-style root.
  ##
  ## On systems without a procfs cwd symlink, or when the process no longer
  ## exists, returns none instead of raising.
  if pid <= 0 or procRoot.len == 0:
    return none(string)
  try:
    let path = expandSymlink(procRoot / $pid / "cwd")
    if path.len == 0: none(string) else: some(path)
  except OSError:
    none(string)

func cwdLabel*(path: string): string =
  ## Return the last path component suitable for compact UI labels.
  let normalized = path.strip(chars = {'/', '\\'})
  if normalized.len == 0:
    return path
  let (_, tail) = splitPath(normalized)
  if tail.len == 0: path else: tail

proc processCwdLabel*(pid: int, procRoot = "/proc"): Option[string] =
  ## Resolve a process cwd and return its compact label.
  let path = processCwd(pid, procRoot)
  if path.isNone: none(string) else: some(cwdLabel(path.get()))
