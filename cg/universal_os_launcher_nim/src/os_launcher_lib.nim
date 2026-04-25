## Universal OS Launcher.
##
## Safely opens URIs, URLs, and file paths using the native
## desktop environment's default handler (xdg-open, open, start).

import std/browsers

proc launchUri*(uri: string) =
  ## Open the provided URI in the default system handler.
  ## Wraps standard library functionality to provide a clean,
  ## unified API for interactive elements.
  openDefaultBrowser(uri)
