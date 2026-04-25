## Example usage of Windows Handle RAII wrapper.

import windows_handle_lib

# 1. Define a custom closer (e.g. for a mock system resource)
proc mockClose(h: int) =
  echo "Resource ", h, " has been closed."

# 2. Use SafeHandle to manage the resource lifecycle
block:
  let h = wrap(101, mockClose)
  if h.isValid:
    echo "Using resource ", h.value
  
  # Resource 101 will be automatically closed at the end of this block.

echo "Example complete."
