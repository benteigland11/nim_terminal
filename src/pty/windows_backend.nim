## Compatibility wrapper for the reusable Windows ConPTY widget.

when defined(windows):
  import ../../cg/backend_windows_conpty_nim/src/windows_conpty_lib
  export windows_conpty_lib
