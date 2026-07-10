## Command-backed system clipboard helper.
##
## Tries common clipboard commands at runtime and returns structured results.
## Paste paths are hard-bounded by an external `timeout` wrapper when available
## so hung tools like `wl-paste` cannot freeze the host UI.

import std/[options, os, osproc, streams, strutils]

const
  DefaultPasteTimeoutMs* = 250
  DefaultCopyTimeoutMs* = 1_000

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
    backend("wayland-wl-paste", "wl-paste", ["--no-newline", "--type", "text"]),
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

func timeoutSecondsArg(timeoutMs: int): string =
  let ms = max(50, timeoutMs)
  ## GNU coreutils timeout accepts fractional seconds.
  let whole = ms div 1000
  let frac = ms mod 1000
  if whole == 0:
    "0." & intToStr(frac, 3)
  elif frac == 0:
    $whole
  else:
    $whole & "." & intToStr(frac, 3)

proc copyTextWith*(
    text: string;
    item: ClipboardBackend;
    timeoutMs = DefaultCopyTimeoutMs,
): ClipboardResult =
  discard timeoutMs
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
    ## Many clipboard writers (wl-copy) keep running as a data source. If they
    ## accepted stdin without exiting, treat that as success without waiting.
    let code = process.peekExitCode()
    if code == -1:
      result = ClipboardResult(
        status: csSuccess,
        backend: item.name,
        exitCode: -1,
        message: "clipboard command accepted input and remains active",
      )
    elif code == 0:
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

proc copyText*(
    text: string;
    backends: openArray[ClipboardBackend] = defaultCopyBackends();
    timeoutMs = DefaultCopyTimeoutMs,
): ClipboardResult =
  let selected = firstAvailableBackend(backends)
  if selected.isNone:
    return ClipboardResult(
      status: csNoBackend,
      backend: "",
      exitCode: -1,
      message: "no clipboard backend command available",
    )
  copyTextWith(text, selected.get(), timeoutMs)

proc pasteTextWith*(
    item: ClipboardBackend;
    timeoutMs = DefaultPasteTimeoutMs,
): ClipboardTextResult =
  if item.command.len == 0 or not commandAvailable(item.command):
    return ClipboardTextResult(
      status: csNoBackend,
      backend: item.name,
      exitCode: -1,
      message: "clipboard command not available",
    )
  try:
    var cmd = item.command
    var args = item.args
    var usedTimeout = false
    ## Prefer `timeout(1)` so a hung paste backend cannot block the host.
    if commandAvailable("timeout"):
      args = @["--kill-after=0.1s", timeoutSecondsArg(timeoutMs), item.command] & item.args
      cmd = "timeout"
      usedTimeout = true
    var process = startProcess(
      command = cmd,
      args = args,
      options = {poUsePath, poStdErrToStdOut},
    )
    let code = process.waitForExit()
    let output = process.outputStream.readAll()
    process.close()
    if usedTimeout and code in {124, 137}:
      return ClipboardTextResult(
        status: csCommandFailed,
        backend: item.name,
        exitCode: code,
        message: "clipboard paste timed out",
      )
    if code == 0:
      result = ClipboardTextResult(
        status: csSuccess,
        backend: item.name,
        exitCode: code,
        text: output,
      )
    else:
      result = ClipboardTextResult(
        status: csCommandFailed,
        backend: item.name,
        exitCode: code,
        message: "clipboard paste exited nonzero",
        text: output,
      )
  except CatchableError as error:
    result = ClipboardTextResult(
      status: csCommandFailed,
      backend: item.name,
      exitCode: -1,
      message: error.msg,
    )

proc pasteText*(
    backends: openArray[ClipboardBackend] = defaultPasteBackends();
    timeoutMs = DefaultPasteTimeoutMs,
): ClipboardTextResult =
  ## Use the first available backend only. Cascading through hang-prone tools
  ## multiplies latency; the host can install a native provider first instead.
  let selected = firstAvailableBackend(backends)
  if selected.isNone:
    return ClipboardTextResult(
      status: csNoBackend,
      backend: "",
      exitCode: -1,
      message: "no clipboard backend command available",
    )
  pasteTextWith(selected.get(), timeoutMs)
