## Command-backed system clipboard helper.
##
## Tries common clipboard commands at runtime and returns structured results.

import std/[options, os, osproc, streams, strutils]

type
  ClipboardBackend* = object
    name*: string
    command*: string
    args*: seq[string]

  ClipboardStatus* = enum
    csSuccess,
    csNoBackend,
    csCommandFailed

  ClipboardResult* = object
    status*: ClipboardStatus
    backend*: string
    exitCode*: int
    message*: string

  ClipboardTextResult* = object
    status*: ClipboardStatus
    backend*: string
    exitCode*: int
    text*: string
    message*: string

func backend*(name, command: string; args: openArray[string] = []): ClipboardBackend =
  ClipboardBackend(name: name, command: command, args: @args)

func defaultCopyBackends*(): seq[ClipboardBackend] =
  @[
    backend("wayland-wl-copy", "wl-copy"),
    backend("x11-xclip", "xclip", ["-selection", "clipboard"]),
    backend("x11-xsel", "xsel", ["--clipboard", "--input"]),
    backend("macos-pbcopy", "pbcopy"),
    backend("windows-clip", "clip.exe"),
    backend("powershell-set-clipboard", "powershell", [
      "-NoProfile", "-Command", "Set-Clipboard -Value ([Console]::In.ReadToEnd())"
    ]),
    backend("powershell-core-set-clipboard", "pwsh", [
      "-NoProfile", "-Command", "Set-Clipboard -Value ([Console]::In.ReadToEnd())"
    ]),
  ]

func defaultPasteBackends*(): seq[ClipboardBackend] =
  @[
    backend("wayland-wl-paste", "wl-paste", ["--no-newline"]),
    backend("x11-xclip", "xclip", ["-selection", "clipboard", "-out"]),
    backend("x11-xsel", "xsel", ["--clipboard", "--output"]),
    backend("macos-pbpaste", "pbpaste"),
    backend("powershell-get-clipboard", "powershell", [
      "-NoProfile", "-Command", "Get-Clipboard -Raw"
    ]),
    backend("powershell-core-get-clipboard", "pwsh", [
      "-NoProfile", "-Command", "Get-Clipboard -Raw"
    ]),
  ]

func success*(r: ClipboardResult): bool =
  r.status == csSuccess

func success*(r: ClipboardTextResult): bool =
  r.status == csSuccess

proc commandAvailable*(command: string): bool =
  findExe(command).len > 0

proc firstAvailableBackend*(backends: openArray[ClipboardBackend]): Option[ClipboardBackend] =
  for item in backends:
    if item.command.len > 0 and commandAvailable(item.command):
      return some(item)
  none(ClipboardBackend)

proc copyTextWith*(text: string; item: ClipboardBackend): ClipboardResult =
  if item.command.len == 0 or not commandAvailable(item.command):
    return ClipboardResult(
      status: csNoBackend,
      backend: item.name,
      exitCode: -1,
      message: "clipboard command not available",
    )
  var process: Process
  try:
    process = startProcess(
      command = item.command,
      args = item.args,
      options = {poUsePath, poStdErrToStdOut},
    )
    process.inputStream.write(text)
    process.inputStream.close()
    let code = process.waitForExit()
    if code == 0:
      result = ClipboardResult(status: csSuccess, backend: item.name, exitCode: code)
    else:
      result = ClipboardResult(
        status: csCommandFailed,
        backend: item.name,
        exitCode: code,
        message: "clipboard command exited nonzero",
      )
  except CatchableError as error:
    result = ClipboardResult(
      status: csCommandFailed,
      backend: item.name,
      exitCode: -1,
      message: error.msg,
    )
  finally:
    if process != nil:
      process.close()

proc copyText*(text: string; backends: openArray[ClipboardBackend] = defaultCopyBackends()): ClipboardResult =
  let selected = firstAvailableBackend(backends)
  if selected.isNone:
    return ClipboardResult(
      status: csNoBackend,
      backend: "",
      exitCode: -1,
      message: "no clipboard backend command available",
    )
  copyTextWith(text, selected.get())

proc pasteTextWith*(item: ClipboardBackend): ClipboardTextResult =
  if item.command.len == 0 or not commandAvailable(item.command):
    return ClipboardTextResult(
      status: csNoBackend,
      backend: item.name,
      exitCode: -1,
      message: "clipboard command not available",
    )
  try:
    let output = execProcess(
      item.command,
      args = item.args,
      options = {poUsePath, poStdErrToStdOut},
    )
    result = ClipboardTextResult(
      status: csSuccess,
      backend: item.name,
      exitCode: 0,
      text: output,
    )
  except CatchableError as error:
    result = ClipboardTextResult(
      status: csCommandFailed,
      backend: item.name,
      exitCode: -1,
      message: error.msg,
    )

proc pasteText*(backends: openArray[ClipboardBackend] = defaultPasteBackends()): ClipboardTextResult =
  let selected = firstAvailableBackend(backends)
  if selected.isNone:
    return ClipboardTextResult(
      status: csNoBackend,
      backend: "",
      exitCode: -1,
      message: "no clipboard backend command available",
    )
  pasteTextWith(selected.get())
