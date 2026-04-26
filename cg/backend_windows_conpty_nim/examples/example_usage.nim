import windows_conpty_lib

let backend = newWindowsBackend()
doAssert backend != nil
doAssert translateErrorCode(267).len > 0
