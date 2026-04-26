## Windows implementation of Pseudo-terminal (ConPTY).

when defined(windows):
  import std/[winlean, os]
  import ../../cg/universal_windows_handle_nim/src/windows_handle_lib
  import ../../cg/universal_windows_error_nim/src/windows_error_lib

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

  # For Process Creation
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
      ptyIn*: SafeHandle
      ptyOut*: SafeHandle
      processHandle*: SafeHandle
      threadHandle*: SafeHandle
      pid*: int

  proc newWindowsBackend*(): WindowsBackend = WindowsBackend()

  proc closeHandleCloser(h: int) =
    discard closeHandle(Handle(h))

  proc createPipePair(): (SafeHandle, SafeHandle) =
    var readPipe, writePipe: Handle
    var sa: SECURITY_ATTRIBUTES
    sa.nLength = int32(sizeof(SECURITY_ATTRIBUTES))
    sa.bInheritHandle = 0 # Cannot inherit directly for PTY
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
      if err == 109: return 0 # ERROR_BROKEN_PIPE
      when defined(windows):
        if getEnv("WAYMARK_INPUT_DEBUG", "0") == "1":
          echo "[pty-read] peek failed error=", err
      return -1

    if avail == 0: return -1

    var bytesRead: int32
    if readFile(Handle(b.ptyOut.value), addr buf[0], int32(buf.len), addr bytesRead, nil) == 0:
      let err = osLastError().int64
      if err == 109: return 0 # ERROR_BROKEN_PIPE
      when defined(windows):
        if getEnv("WAYMARK_INPUT_DEBUG", "0") == "1":
          echo "[pty-read] read failed error=", err
      return -1
    when defined(windows):
      if getEnv("WAYMARK_INPUT_DEBUG", "0") == "1":
        echo "[pty-read] avail=", avail, " read=", bytesRead
    int(bytesRead)

  proc ptyWrite*(b: WindowsBackend, h: int, data: openArray[byte]): int =
    if data.len == 0: return 0
    var bytesWritten: int32
    if writeFile(Handle(b.ptyIn.value), unsafeAddr data[0], int32(data.len), addr bytesWritten, nil) == 0:
      when defined(windows):
        if getEnv("WAYMARK_INPUT_DEBUG", "0") == "1":
          echo "[pty-write] failed len=", data.len, " error=", osLastError().int64
      return -1
    when defined(windows):
      if getEnv("WAYMARK_INPUT_DEBUG", "0") == "1":
        echo "[pty-write] len=", data.len, " wrote=", bytesWritten
    int(bytesWritten)

  proc ptyResize*(b: WindowsBackend, h: int, rows, cols: int) =
    var size = COORD(x: int16(cols), y: int16(rows))
    discard ResizePseudoConsole(b.hPC, size)

  proc ptySignal*(b: WindowsBackend, p, s: int) =
    discard terminateProcess(Handle(b.processHandle.value), 1)

  proc ptyWait*(b: WindowsBackend, p: int): int =
    let res = waitForSingleObject(Handle(b.processHandle.value), 0)
    if res == 0: # WAIT_OBJECT_0
      var exitCode: int32
      if getExitCodeProcess(Handle(b.processHandle.value), exitCode) != 0:
        return int(exitCode)
      return 0
    return -1

  proc ptyClose*(b: WindowsBackend, h: int) =
    b.ptyIn.close()
    b.ptyOut.close()
    if b.hPC != 0:
      ClosePseudoConsole(b.hPC)
      b.hPC = 0
    b.processHandle.close()
    b.threadHandle.close()

  # Host integration
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
    if c.len > 0: pCwd = newWideCString(c)

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
    return b.pid
