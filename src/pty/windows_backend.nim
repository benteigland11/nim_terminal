## Windows implementation of Pseudo-terminal (ConPTY).

when defined(windows):
  import std/winlean

  type
    HPCON* = Handle
    COORD* = object
      x*, y*: int16
    HRESULT* = int32
    DWORD = uint32

  proc CreatePseudoConsole*(size: COORD, hInput, hOutput: Handle, flags: DWORD, phPC: ptr HPCON): HRESULT {.stdcall, importc: "CreatePseudoConsole", dynlib: "kernel32.dll".}
  proc ResizePseudoConsole*(hPC: HPCON, size: COORD): HRESULT {.stdcall, importc: "ResizePseudoConsole", dynlib: "kernel32.dll".}
  proc ClosePseudoConsole*(hPC: HPCON) {.stdcall, importc: "ClosePseudoConsole", dynlib: "kernel32.dll".}

  type
    WindowsBackend* = ref object
      hPC*: HPCON

  proc newWindowsBackend*(): WindowsBackend = WindowsBackend()

  proc ptyOpen*(b: WindowsBackend): tuple[handle: int, slaveId: string] = (0, "")
  proc ptyRead*(b: WindowsBackend, h: int, buf: var openArray[byte]): int = 0
  proc ptyWrite*(b: WindowsBackend, h: int, data: openArray[byte]): int = 0
  proc ptyResize*(b: WindowsBackend, h: int, rows, cols: int) = discard
  proc ptySignal*(b: WindowsBackend, p, s: int) = discard
  proc ptyWait*(b: WindowsBackend, p: int): int = 0
  proc ptyClose*(b: WindowsBackend, h: int) = discard

  # Mandatory Host integration stubs
  proc ptySetSize*(b: WindowsBackend, h, rows, cols: int) = discard
  proc ptyForkExec*(b: WindowsBackend, h: string, p: string, a: openArray[string], c: string): int = 0
