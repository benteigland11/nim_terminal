## Example usage of Clipboard Provider.
##
## This example uses an in-memory provider so it has no desktop or OS
## clipboard dependency.

import clipboard_provider_lib

var stored = "initial"
let item = provider(
  "memory",
  proc (): ClipboardTextResult = clipboardTextSuccess("memory", stored),
  proc (text: string): ClipboardResult =
    stored = text
    clipboardSuccess("memory"),
)

doAssert item.readText().text == "initial"
doAssert item.writeText("copied").success
doAssert item.readText().text == "copied"
