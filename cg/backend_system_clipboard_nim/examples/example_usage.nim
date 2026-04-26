## Example usage of System Clipboard.

import system_clipboard_lib

let copyBackends = defaultCopyBackends()
let pasteBackends = defaultPasteBackends()

doAssert copyBackends.len >= 5
doAssert pasteBackends.len >= 5
doAssert copyText("example", []).status == csNoBackend
doAssert pasteText([]).status == csNoBackend
