## Example usage of Windows Error translator.

import windows_error_lib

# 1. Translate a raw error code to a message
let msg = translateErrorCode(109)
echo "Error 109 means: ", msg

# 2. Raise a descriptive exception
try:
  # Simulate a failure in a system call
  raiseWinError(2, "Opening configuration file")
except WinError as e:
  echo "Caught expected error: ", e.msg

echo "Example complete."
