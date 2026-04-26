## Terminal report generator.
##
## Provides a clean API for generating the response strings that a
## terminal emulator writes back to the PTY in response to queries
## (DSR, DA, etc.).
##
## This widget is pure string/byte formatting. It does not perform any
## I/O itself.

import std/strutils

func csi(body: string): string = "\e[" & body

# ---------------------------------------------------------------------------
# Cursor Position (DSR 6)
# ---------------------------------------------------------------------------

func reportCursorPosition*(row, col: int): string =
  ## Format a Device Status Report (DSR) response for cursor position.
  ## Coordinates are passed as 0-indexed (internal terminal state)
  ## and formatted as 1-indexed (VT standard).
  csi($(row + 1) & ";" & $(col + 1) & "R")

# ---------------------------------------------------------------------------
# Device Attributes (DA)
# ---------------------------------------------------------------------------

type
  TerminalFeature* = enum
    tfCpc          ## Column Address (CSI G)
    tfLrc          ## Line Address (CSI d)
    tfVpa          ## Vertical Position Attribute
    tfHpa          ## Horizontal Position Attribute
    tfAnsiColor    ## 16-color ANSI
    tf256Color     ## 256-color extended
    tfTrueColor    ## 24-bit RGB
    tfSixel        ## Sixel graphics
    tfMouse1000    ## Basic mouse tracking
    tfMouse1006    ## SGR mouse tracking

func reportPrimaryDeviceAttributes*(features: set[TerminalFeature]): string =
  ## Format a Primary Device Attributes (DA) response.
  ## This is the "I am an xterm-compatible terminal" string.
  ## Common xterm response: CSI ? 6 2 ; 1 ; 2 ; 6 ; 8 ; 9 ; 1 5 ; c
  var parts = @["?62"] # VT220-ish base
  
  # Note: The mapping of features to xterm parameter codes is complex.
  # This implementation uses a common subset.
  if tfAnsiColor in features: parts.add "1"
  if tf256Color in features: parts.add "2"
  if tfTrueColor in features: parts.add "3"
  if tfSixel in features: parts.add "4"
  if tfMouse1000 in features: parts.add "6"
  if tfMouse1006 in features: parts.add "8"
  
  csi(parts.join(";") & "c")

func reportSecondaryDeviceAttributes*(version: int): string =
  ## Format Secondary Device Attributes (DA2) response.
  ## Format: CSI > <type> ; <version> ; <cartridge> c
  ## xterm uses type 0 or 1.
  csi(">0;" & $version & ";0c")

# ---------------------------------------------------------------------------
# Window State (CSI t)
# ---------------------------------------------------------------------------

func reportWindowSize*(rows, cols: int): string =
  ## Format the response for CSI 18 t (report text area size in chars).
  csi("8;" & $rows & ";" & $cols & "t")

func reportScreenSize*(rows, cols: int): string =
  ## Format the response for CSI 19 t (report screen size in chars).
  csi("9;" & $rows & ";" & $cols & "t")

func reportWindowTitle*(title: string): string =
  ## Format the response for CSI 21 t (report window title).
  csi("l" & title & "\e\\")

# ---------------------------------------------------------------------------
# Mode Status (DECRPM)
# ---------------------------------------------------------------------------

type
  ModeStatus* = enum
    msNotRecognized = 0
    msSet = 1
    msReset = 2
    msPermanentlySet = 3
    msPermanentlyReset = 4

  ModeSupport* = object
    code*: int
    privateMode*: bool
    status*: ModeStatus

func reportModeStatus*(mode: int, status: ModeStatus, privateMode = true): string =
  ## Format a DECRPM response for DECRQM mode status queries.
  let prefix = if privateMode: "?" else: ""
  csi(prefix & $mode & ";" & $(ord(status)) & "$y")

func modeStatusFrom*(modes: openArray[ModeSupport], code: int, privateMode = true): ModeStatus =
  ## Lookup a mode status in a small caller-owned capability table.
  for m in modes:
    if m.code == code and m.privateMode == privateMode:
      return m.status
  msNotRecognized

func modeSupport*(code: int, status: ModeStatus, privateMode = true): ModeSupport =
  ModeSupport(code: code, status: status, privateMode: privateMode)

# ---------------------------------------------------------------------------
# Focus (CSI I / CSI O)
# ---------------------------------------------------------------------------

func reportFocus*(gained: bool): string =
  ## Format Focus In (CSI I) or Focus Out (CSI O) report.
  csi(if gained: "I" else: "O")

# ---------------------------------------------------------------------------
# Clipboard (OSC 52)
# ---------------------------------------------------------------------------

func reportClipboard*(selector, base64Data: string): string =
  ## Format OSC 52 response for clipboard queries.
  "\e]52;" & selector & ";" & base64Data & "\e\\"

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

func reportAnswerback*(answer: string): string =
  ## Format the ENQ (0x05) answerback response.
  answer
