## Example usage of Process CWD.
##
## This file must compile and run cleanly with no user input,
## no network calls, and no external services. Use fake/hardcoded
## data to demonstrate the API.

import std/options
import process_cwd_lib

doAssert cwdLabel("tmp/example-project") == "example-project"

let cwd = processCwdLabel(0)
doAssert cwd.isNone
