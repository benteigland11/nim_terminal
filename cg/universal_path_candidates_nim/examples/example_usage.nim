## Example usage of Path Candidates.
##
## This file must compile and run cleanly with no user input,
## no network calls, and no external services. Use fake/hardcoded
## data to demonstrate the API.

import std/[options, os]
import path_candidates_lib

let resolved = resolveCandidatePath("font.ttf", "assets")
doAssert resolved == "assets" / "font.ttf"

let missing = firstExistingPath(["missing-a", "missing-b"], "assets")
doAssert missing.isNone
