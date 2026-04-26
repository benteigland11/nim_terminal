## Dependency-free clipboard provider contract.
##
## UI frameworks and platform backends can adapt their native clipboard APIs
## into this small callback shape. Applications can then compose providers,
## enforce paste limits, and return structured errors without depending on any
## one windowing toolkit.

type
  ClipboardStatus* = enum
    csSuccess
    csUnavailable
    csTooLarge
    csFailed

  ClipboardResult* = object
    status*: ClipboardStatus
    provider*: string
    message*: string

  ClipboardTextResult* = object
    status*: ClipboardStatus
    provider*: string
    text*: string
    message*: string

  ClipboardReadProc* = proc (): ClipboardTextResult {.closure.}
  ClipboardWriteProc* = proc (text: string): ClipboardResult {.closure.}

  ClipboardProvider* = object
    name*: string
    readText*: ClipboardReadProc
    writeText*: ClipboardWriteProc

  ClipboardPolicy* = object
    maxReadBytes*: int
    maxWriteBytes*: int
    normalizeNewlines*: bool

func defaultClipboardPolicy*(): ClipboardPolicy =
  ClipboardPolicy(maxReadBytes: 1_000_000, maxWriteBytes: 1_000_000, normalizeNewlines: false)

func clipboardSuccess*(provider: string): ClipboardResult =
  ClipboardResult(status: csSuccess, provider: provider)

func clipboardUnavailable*(provider, message: string): ClipboardResult =
  ClipboardResult(status: csUnavailable, provider: provider, message: message)

func clipboardTooLarge*(provider, message: string): ClipboardResult =
  ClipboardResult(status: csTooLarge, provider: provider, message: message)

func clipboardFailed*(provider, message: string): ClipboardResult =
  ClipboardResult(status: csFailed, provider: provider, message: message)

func clipboardTextSuccess*(provider, text: string): ClipboardTextResult =
  ClipboardTextResult(status: csSuccess, provider: provider, text: text)

func clipboardTextUnavailable*(provider, message: string): ClipboardTextResult =
  ClipboardTextResult(status: csUnavailable, provider: provider, message: message)

func clipboardTextTooLarge*(provider, message: string): ClipboardTextResult =
  ClipboardTextResult(status: csTooLarge, provider: provider, message: message)

func clipboardTextFailed*(provider, message: string): ClipboardTextResult =
  ClipboardTextResult(status: csFailed, provider: provider, message: message)

func success*(value: ClipboardResult): bool =
  value.status == csSuccess

func success*(value: ClipboardTextResult): bool =
  value.status == csSuccess

func normalizeClipboardText*(text: string): string =
  ## Convert CRLF and CR newlines to LF without otherwise rewriting text.
  result = newStringOfCap(text.len)
  var i = 0
  while i < text.len:
    if text[i] == '\r':
      result.add '\n'
      if i + 1 < text.len and text[i + 1] == '\n':
        inc i
    else:
      result.add text[i]
    inc i

func withinLimit(text: string, limit: int): bool =
  limit <= 0 or text.len <= limit

func applyReadPolicy(value: ClipboardTextResult, policy: ClipboardPolicy): ClipboardTextResult =
  if not value.success:
    return value
  if not value.text.withinLimit(policy.maxReadBytes):
    return clipboardTextTooLarge(value.provider, "clipboard text exceeds read limit")
  let text = if policy.normalizeNewlines: normalizeClipboardText(value.text) else: value.text
  clipboardTextSuccess(value.provider, text)

func applyWritePolicy(provider, text: string, policy: ClipboardPolicy): ClipboardResult =
  if not text.withinLimit(policy.maxWriteBytes):
    return clipboardTooLarge(provider, "clipboard text exceeds write limit")
  clipboardSuccess(provider)

func provider*(name: string, readText: ClipboardReadProc, writeText: ClipboardWriteProc): ClipboardProvider =
  ClipboardProvider(name: name, readText: readText, writeText: writeText)

func unavailableProvider*(name, message: string): ClipboardProvider =
  ClipboardProvider(
    name: name,
    readText: proc (): ClipboardTextResult = clipboardTextUnavailable(name, message),
    writeText: proc (text: string): ClipboardResult = clipboardUnavailable(name, message),
  )

proc readText*(item: ClipboardProvider, policy = defaultClipboardPolicy()): ClipboardTextResult =
  if item.readText == nil:
    return clipboardTextUnavailable(item.name, "clipboard read is not available")
  applyReadPolicy(item.readText(), policy)

proc writeText*(item: ClipboardProvider, text: string, policy = defaultClipboardPolicy()): ClipboardResult =
  let check = applyWritePolicy(item.name, text, policy)
  if not check.success:
    return check
  if item.writeText == nil:
    return clipboardUnavailable(item.name, "clipboard write is not available")
  item.writeText(if policy.normalizeNewlines: normalizeClipboardText(text) else: text)

proc readText*(items: openArray[ClipboardProvider], policy = defaultClipboardPolicy()): ClipboardTextResult =
  for item in items:
    let attempt = readText(item, policy)
    if attempt.success:
      return attempt
  clipboardTextUnavailable("", "no clipboard provider could read text")

proc writeText*(items: openArray[ClipboardProvider], text: string, policy = defaultClipboardPolicy()): ClipboardResult =
  for item in items:
    let attempt = writeText(item, text, policy)
    if attempt.success:
      return attempt
  clipboardUnavailable("", "no clipboard provider could write text")
