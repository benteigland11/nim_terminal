import std/unittest
import clipboard_provider_lib

proc memoryProvider(name: string, value: string): ClipboardProvider =
  var stored = value
  provider(
    name,
    proc (): ClipboardTextResult = clipboardTextSuccess(name, stored),
    proc (text: string): ClipboardResult =
      stored = text
      clipboardSuccess(name),
  )

suite "Clipboard Provider":
  test "provider reads and writes text":
    var item = memoryProvider("memory", "hello")
    check item.readText().text == "hello"
    check item.writeText("world").success
    check item.readText().text == "world"

  test "fallback uses first successful provider":
    let missing = unavailableProvider("missing", "not available")
    let memory = memoryProvider("memory", "value")
    let result = readText([missing, memory])
    check result.success
    check result.provider == "memory"
    check result.text == "value"

  test "write fallback skips unavailable providers":
    let missing = unavailableProvider("missing", "not available")
    var memory = memoryProvider("memory", "")
    check writeText([missing, memory], "copied").provider == "memory"

  test "read limit rejects large paste payloads":
    let item = memoryProvider("memory", "abcdef")
    let policy = ClipboardPolicy(maxReadBytes: 3, maxWriteBytes: 100, normalizeNewlines: false)
    let result = readText(item, policy)
    check result.status == csTooLarge

  test "write limit rejects large copy payloads before provider call":
    var called = false
    let item = provider(
      "memory",
      proc (): ClipboardTextResult = clipboardTextSuccess("memory", ""),
      proc (text: string): ClipboardResult =
        called = true
        clipboardSuccess("memory"),
    )
    let policy = ClipboardPolicy(maxReadBytes: 100, maxWriteBytes: 3, normalizeNewlines: false)
    let result = writeText(item, "abcdef", policy)
    check result.status == csTooLarge
    check not called

  test "newline normalization converts CRLF and CR to LF":
    check normalizeClipboardText("a\r\nb\rc\n") == "a\nb\nc\n"
    let item = memoryProvider("memory", "a\r\nb")
    let policy = ClipboardPolicy(maxReadBytes: 100, maxWriteBytes: 100, normalizeNewlines: true)
    check readText(item, policy).text == "a\nb"
