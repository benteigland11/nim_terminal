## Windows ConPTY backend for terminal hosts.
##
## The implementation exposes the same small PTY backend surface used by
## backend-pty-host-nim: open, resize, fork/exec, read, write, signal, wait,
## and close. On non-Windows platforms the type is present but operations fail
## cleanly so tests and consumers can compile cross-platform.

import std/strformat

type
  WinError* = object of CatchableError
    code*: int64

func translateErrorCode*(code: int64): string =
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
  of -2147024809: "Invalid parameter (E_INVALIDARG)"
  of -2147467259: "Unspecified failure (E_FAIL)"
  of -2147418113: "Unexpected failure (E_UNEXPECTED)"
  else: &"Windows Error 0x{code:X} ({code})"

proc raiseWinError*(code: int64, context: string = "") =
  let msg = translateErrorCode(code)
  let fullMsg = if context.len > 0: &"{context}: {msg}" else: msg
  let exc = newException(WinError, fullMsg)
  exc.code = code
  raise exc

when hostOS == "windows":
  import std/[os, winlean]

  type
    HandleCloser = proc(h: int) {.nimcall, raises: [].}
    SafeHandle = object
      raw: int
      closer: HandleCloser
      active: bool

  func isValid(h: SafeHandle): bool =
    h.active and h.raw != 0

  func value(h: SafeHandle): int =
    h.raw

  proc close(h: var SafeHandle) =
    if h.active:
      if h.closer != nil:
        h.closer(h.raw)
      h.active = false
      h.raw = 0

  proc `=destroy`(h: var SafeHandle) =
    h.close()

  proc `=copy`(dest: var SafeHandle, src: SafeHandle) {.error: "SafeHandle cannot be copied; use move semantics".}

  func wrap(handle: int, closer: HandleCloser): SafeHandle =
    SafeHandle(raw: handle, closer: closer, active: true)

  type
    HPCON* = Handle
    COORD* = object
      x*, y*: int16
    HRESULT* = int32
    DWORD = uint32
    SIZE_T = uint

  proc CreatePseudoConsole*(size: COORD, hInput, hOutput: Handle, flags: DWORD, phPC: ptr HPCON): HRESULT {.stdcall, importc: "CreatePseudoConsole", dynlib: "kernel32.dll".}
  proc ResizePseudoConsole*(hPC: HPCON, size: COORD): HRESULT {.stdcall, importc: "ResizePseudoConsole", dynlib: "kernel32.dll".}
  proc ClosePseudoConsole*(hPC: HPCON) {.stdcall, importc: "ClosePseudoConsole", dynlib: "kernel32.dll".}
  proc PeekNamedPipe*(hNamedPipe: Handle, lpBuffer: pointer, nBufferSize: DWORD, lpBytesRead: ptr DWORD, lpTotalBytesAvail: ptr DWORD, lpBytesLeftThisMessage: ptr DWORD): WINBOOL {.stdcall, importc: "PeekNamedPipe", dynlib: "kernel32.dll".}

  type
    STARTUPINFOEXW = object
      StartupInfo: STARTUPINFO
      lpAttributeList: pointer

  proc InitializeProcThreadAttributeList*(lpAttributeList: pointer, dwAttributeCount: DWORD, dwFlags: DWORD, lpSize: ptr SIZE_T): WINBOOL {.stdcall, importc: "InitializeProcThreadAttributeList", dynlib: "kernel32.dll".}
  proc UpdateProcThreadAttribute*(lpAttributeList: pointer, dwFlags: DWORD, Attribute: SIZE_T, lpValue: pointer, cbSize: SIZE_T, lpPreviousValue: pointer, lpReturnSize: ptr SIZE_T): WINBOOL {.stdcall, importc: "UpdateProcThreadAttribute", dynlib: "kernel32.dll".}
  proc DeleteProcThreadAttributeList*(lpAttributeList: pointer) {.stdcall, importc: "DeleteProcThreadAttributeList", dynlib: "kernel32.dll".}
  proc CreateProcessWithStartupInfoExW(
    lpApplicationName, lpCommandLine: WideCString,
    lpProcessAttributes: ptr SECURITY_ATTRIBUTES,
    lpThreadAttributes: ptr SECURITY_ATTRIBUTES,
    bInheritHandles: WINBOOL,
    dwCreationFlags: int32,
    lpEnvironment: pointer,
    lpCurrentDirectory: WideCString,
    lpStartupInfo: ptr STARTUPINFOEXW,
    lpProcessInformation: var PROCESS_INFORMATION,
  ): WINBOOL {.stdcall, importc: "CreateProcessW", dynlib: "kernel32.dll".}

  const
    EXTENDED_STARTUPINFO_PRESENT = 0x00080000'i32
    PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016'u
    ERROR_DIRECTORY = 267'i64

  type
    WindowsBackend* = ref object
      hPC*: HPCON
      ptyIn: SafeHandle
      ptyOut: SafeHandle
      processHandle: SafeHandle
      threadHandle: SafeHandle
      pid*: int

  proc newWindowsBackend*(): WindowsBackend =
    WindowsBackend()

  proc closeHandleCloser(h: int) =
    discard closeHandle(Handle(h))

  proc createPipePair(): (SafeHandle, SafeHandle) =
    var readPipe, writePipe: Handle
    var sa: SECURITY_ATTRIBUTES
    sa.nLength = int32(sizeof(SECURITY_ATTRIBUTES))
    sa.bInheritHandle = 0
    sa.lpSecurityDescriptor = nil
    if createPipe(readPipe, writePipe, sa, 0) == 0:
      raiseWinError(osLastError().int64, "CreatePipe")
    (wrap(int(readPipe), closeHandleCloser), wrap(int(writePipe), closeHandleCloser))

  proc ptyOpen*(b: WindowsBackend): tuple[handle: int, slaveId: string] =
    var (outRead, outWrite) = createPipePair()
    var (inRead, inWrite) = createPipePair()
    var size = COORD(x: 80, y: 24)
    var hPC: HPCON
    let hr = CreatePseudoConsole(size, Handle(inRead.value), Handle(outWrite.value), 0, addr hPC)
    if hr < 0:
      raiseWinError(hr, "CreatePseudoConsole")
    b.hPC = hPC
    b.ptyIn = inWrite
    b.ptyOut = outRead
    inRead.close()
    outWrite.close()
    (1, "conpty")

  proc ptyRead*(b: WindowsBackend, h: int, buf: var openArray[byte]): int =
    var avail: DWORD
    if PeekNamedPipe(Handle(b.ptyOut.value), nil, 0, nil, addr avail, nil) == 0:
      let err = osLastError().int64
      if err == 109: return 0
      return -1
    if avail == 0:
      return -1
    var bytesRead: int32
    if readFile(Handle(b.ptyOut.value), addr buf[0], int32(buf.len), addr bytesRead, nil) == 0:
      let err = osLastError().int64
      if err == 109: return 0
      return -1
    int(bytesRead)

  proc ptyWrite*(b: WindowsBackend, h: int, data: openArray[byte]): int =
    if data.len == 0:
      return 0
    var bytesWritten: int32
    if writeFile(Handle(b.ptyIn.value), unsafeAddr data[0], int32(data.len), addr bytesWritten, nil) == 0:
      return -1
    int(bytesWritten)

  proc ptyResize*(b: WindowsBackend, h: int, rows, cols: int) =
    var size = COORD(x: int16(cols), y: int16(rows))
    discard ResizePseudoConsole(b.hPC, size)

  proc ptySignal*(b: WindowsBackend, p, s: int) =
    discard terminateProcess(Handle(b.processHandle.value), 1)

  proc ptyWait*(b: WindowsBackend, p: int): int =
    let res = waitForSingleObject(Handle(b.processHandle.value), 0)
    if res == 0:
      var exitCode: int32
      if getExitCodeProcess(Handle(b.processHandle.value), exitCode) != 0:
        return int(exitCode)
      return 0
    -1

  proc ptyClose*(b: WindowsBackend, h: int) =
    b.ptyIn.close()
    b.ptyOut.close()
    if b.hPC != 0:
      ClosePseudoConsole(b.hPC)
      b.hPC = 0
    b.processHandle.close()
    b.threadHandle.close()

  proc ptySetSize*(b: WindowsBackend, h, rows, cols: int) =
    ptyResize(b, h, rows, cols)

  proc ptyForkExec*(b: WindowsBackend, h: string, p: string, a: openArray[string], c: string): int =
    var size: SIZE_T
    discard InitializeProcThreadAttributeList(nil, 1, 0, addr size)
    var attrList = alloc0(size)
    if InitializeProcThreadAttributeList(attrList, 1, 0, addr size) == 0:
      raiseWinError(osLastError().int64, "InitializeProcThreadAttributeList")

    var hPC = b.hPC
    if UpdateProcThreadAttribute(attrList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, cast[pointer](hPC), cast[SIZE_T](sizeof(HPCON)), nil, nil) == 0:
      raiseWinError(osLastError().int64, "UpdateProcThreadAttribute")

    var si: STARTUPINFOEXW
    si.StartupInfo.cb = int32(sizeof(STARTUPINFOEXW))
    si.lpAttributeList = attrList

    var pi: PROCESS_INFORMATION
    var cmdLine = p
    for arg in a:
      cmdLine &= " " & arg

    var wCmdLine = newWideCString(cmdLine)
    var pCwd: WideCString
    if c.len > 0:
      pCwd = newWideCString(c)

    let flags = EXTENDED_STARTUPINFO_PRESENT
    if CreateProcessWithStartupInfoExW(nil, wCmdLine, nil, nil, 0, int32(flags), nil, pCwd, addr si, pi) == 0:
      let err = osLastError().int64
      if err == ERROR_DIRECTORY and pCwd != nil:
        if CreateProcessWithStartupInfoExW(nil, wCmdLine, nil, nil, 0, int32(flags), nil, nil, addr si, pi) == 0:
          raiseWinError(osLastError().int64, "CreateProcessW")
      else:
        raiseWinError(err, "CreateProcessW")

    DeleteProcThreadAttributeList(attrList)
    dealloc(attrList)
    b.processHandle = wrap(int(pi.hProcess), closeHandleCloser)
    b.threadHandle = wrap(int(pi.hThread), closeHandleCloser)
    b.pid = int(pi.dwProcessId)
    b.pid
else:
  type
    WindowsBackend* = ref object
      pid*: int

  proc newWindowsBackend*(): WindowsBackend =
    WindowsBackend()

  proc unavailable() =
    raise newException(OSError, "Windows ConPTY is only available on Windows")

  proc ptyOpen*(b: WindowsBackend): tuple[handle: int, slaveId: string] =
    unavailable()
    (0, "")

  proc ptyRead*(b: WindowsBackend, h: int, buf: var openArray[byte]): int =
    -1

  proc ptyWrite*(b: WindowsBackend, h: int, data: openArray[byte]): int =
    -1

  proc ptyResize*(b: WindowsBackend, h: int, rows, cols: int) =
    discard

  proc ptySignal*(b: WindowsBackend, p, s: int) =
    discard

  proc ptyWait*(b: WindowsBackend, p: int): int =
    -1

  proc ptyClose*(b: WindowsBackend, h: int) =
    discard

  proc ptySetSize*(b: WindowsBackend, h, rows, cols: int) =
    discard

  proc ptyForkExec*(b: WindowsBackend, h: string, p: string, a: openArray[string], c: string): int =
    unavailable()
    0
