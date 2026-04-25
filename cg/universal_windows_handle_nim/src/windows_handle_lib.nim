## RAII wrapper for Windows-style handles.
##
## Ensures that resources (represented as integer handles) are 
## released exactly once when the wrapper goes out of scope.
##
## This widget is platform-agnostic logic. The actual closing 
## function (e.g. CloseHandle) is provided by the caller as a proc.

type
  HandleCloser* = proc(h: int) {.nimcall, raises: [].}

  SafeHandle* = object
    ## A managed handle that automatically closes on destruction.
    raw: int
    closer: HandleCloser
    active: bool

func isValid*(h: SafeHandle): bool =
  ## Returns true if the handle is active and non-zero.
  h.active and h.raw != 0

func value*(h: SafeHandle): int =
  ## Returns the raw handle value.
  h.raw

proc close*(h: var SafeHandle) =
  ## Manually release the handle.
  if h.active:
    if h.closer != nil:
      h.closer(h.raw)
    h.active = false
    h.raw = 0

proc `=destroy`*(h: var SafeHandle) =
  ## Destructor: ensures the handle is closed when out of scope.
  h.close()

proc `=copy`*(dest: var SafeHandle, src: SafeHandle) {.error: "SafeHandle cannot be copied; use move semantics".}
  ## Prevent accidental duplication of resource ownership.

func wrap*(handle: int, closer: HandleCloser): SafeHandle =
  ## Wrap a raw handle with a closer function.
  SafeHandle(raw: handle, closer: closer, active: true)

func claim*(h: var SafeHandle): int =
  ## Transfer ownership out of the wrapper. The wrapper becomes 
  ## inactive and will not close the handle.
  result = h.raw
  h.active = false
  h.raw = 0
