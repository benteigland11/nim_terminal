## Example usage of Vt Reports.
##
## This file must compile and run cleanly with no user input,
## no network calls, and no external services. Use fake/hardcoded
## data to demonstrate the API.

import vt_reports_lib

# Generate a cursor position report (for CSI 6 n)
# Internal 0-indexed coords (5, 10) -> VT standard 1-indexed (6, 11)
let cursor = reportCursorPosition(5, 10)
doAssert cursor == "\e[6;11R"

# Generate primary device attributes
let da = reportPrimaryDeviceAttributes({tfAnsiColor, tf256Color, tfTrueColor})
doAssert da == "\e[?62;1;2;3c"

# Generate window size report
let win = reportWindowSize(24, 80)
doAssert win == "\e[8;24;80t"

echo "All vt-reports examples passed."
