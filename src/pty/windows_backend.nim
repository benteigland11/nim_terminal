## Windows implementation of Pseudo-terminal (ConPTY).

when defined(windows):
  import std/winlean

  type
    HPCON* = Handle
    COORD* = object
      x*, y*: int16
    HRESULT* = int32

  proc CreatePseudoConsole*(size: COORD, hInput, hOutput: Handle, flags: DWORD, phPC: ptr HPCON): HRESULT {.stdcall, importc: "CreatePseudoConsole", dynlib: "kernel32.dll".}
  proc ResizePseudoConsole*(hPC: HPCON, size: COORD): HRESULT {.stdcall, importc: "ResizePseudoConsole", dynlib: "kernel32.dll".}
  proc ClosePseudoConsole*(hPC: HPCON) {.stdcall, importc: "ClosePseudoConsole", dynlib: "kernel32.dll".}

  type
    WindowsBackend* = ref object
      hPC*: HPCON

  proc newWindowsBackend*(): WindowsBackend = WindowsBackend()

  # Note: Spawning a process and attaching pipes is complex.
  # This serves as the Alpha architecture stub for Windows.
  
  proc ptyOpen*(b: WindowsBackend): tuple[handle: int, slaveId: string] = (0, "")
  proc ptyRead*(b: WindowsBackend, h: int, buf: var openArray[byte]): int = 0
  proc ptyWrite*(b: WindowsBackend, h: int, data: openArray[byte]): int = 0
  proc ptyResize*(b: WindowsBackend, h: int, r, c: int) = discard
  proc ptySignal*(b: WindowsBackend, p, s: int) = discard
  proc ptyWait*(b: WindowsBackend, p: int): int = 0
  proc ptyClose*(b: WindowsBackend, h: int) = discard
