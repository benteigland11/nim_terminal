## Windows error and HRESULT translator.
##
## Maps numerical Windows error codes (from GetLastError) and HRESULTs 
## to human-readable strings and Nim exceptions.
##
## This widget is pure logic mapping and does not call Win32 APIs 
## directly, ensuring it can be validated on all platforms.

import std/[strformat]

type
  WinError* = object of CatchableError
    code*: int64

func translateErrorCode*(code: int64): string =
  ## Maps common Win32 and COM error codes to messages.
  case code
  of 0: "Success (S_OK)"
  of 1: "Incorrect function (ERROR_INVALID_FUNCTION)"
  of 2: "The system cannot find the file specified (ERROR_FILE_NOT_FOUND)"
  of 5: "Access is denied (ERROR_ACCESS_DENIED)"
  of 6: "The handle is invalid (ERROR_INVALID_HANDLE)"
  of 109: "The pipe has been ended (ERROR_BROKEN_PIPE)"
  of 232: "The pipe is being closed (ERROR_NO_DATA)"
  of 267: "The directory name is invalid (ERROR_DIRECTORY)"
  of 997: "Overlapped I/O operation is in progress (ERROR_IO_PENDING)"
  # Common HRESULTs (cast to int64)
  of -2147024809: "Invalid parameter (E_INVALIDARG)" # 0x80070057
  of -2147467259: "Unspecified failure (E_FAIL)"      # 0x80004005
  of -2147418113: "Unexpected failure (E_UNEXPECTED)" # 0x8000FFFF
  else: &"Windows Error 0x{code:X} ({code})"

proc raiseWinError*(code: int64, context: string = "") =
  ## Raise a WinError exception with the translated message.
  let msg = translateErrorCode(code)
  let fullMsg = if context.len > 0: &"{context}: {msg}" else: msg
  raise newException(WinError, fullMsg)
