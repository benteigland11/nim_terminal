import std/[sequtils, unittest]
import ../src/system_clipboard_lib

suite "System Clipboard":
  test "default copy backends cover common desktop families":
    let names = defaultCopyBackends().mapIt(it.name)
    check "wayland-wl-copy" in names
    check "x11-xclip" in names
    check "x11-xsel" in names
    check "macos-pbcopy" in names
    check "windows-clip" in names

  test "default paste backends cover common desktop families":
    let names = defaultPasteBackends().mapIt(it.name)
    check "wayland-wl-paste" in names
    check "x11-xclip" in names
    check "x11-xsel" in names
    check "macos-pbpaste" in names
    check "powershell-get-clipboard" in names

  test "empty backend list reports no backend":
    let copyResult = copyText("hello", [])
    check copyResult.status == csNoBackend
    let pasteResult = pasteText([])
    check pasteResult.status == csNoBackend

  test "unavailable explicit backend reports no backend":
    let item = backend("missing", "definitely-not-a-clipboard-command")
    let result = copyTextWith("hello", item)
    check result.status == csNoBackend
    check result.backend == "missing"
