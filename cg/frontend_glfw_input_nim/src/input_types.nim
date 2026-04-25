## Shared input types for terminal interaction.

type
  Modifier* = enum
    modShift
    modAlt
    modCtrl
    modSuper

  KeyCode* = enum
    kNone
    kChar
    kEnter
    kTab
    kBackspace
    kEscape
    kInsert
    kDelete
    kHome
    kEnd
    kPageUp
    kPageDown
    kArrowUp
    kArrowDown
    kArrowLeft
    kArrowRight
    kF1, kF2, kF3, kF4, kF5, kF6, kF7, kF8, kF9, kF10, kF11, kF12
    kKeypadEnter

  MouseButton* = enum
    mbLeft
    mbMiddle
    mbRight
    mbRelease
    mbWheelUp
    mbWheelDown
    mbExtra1
    mbExtra2

  MouseEventKind* = enum
    mePress
    meRelease
    meMove
    meDrag

  MouseEvent* = object
    kind*: MouseEventKind
    button*: MouseButton
    row*, col*: int
    xPixel*, yPixel*: int
    mods*: set[Modifier]

  KeyEvent* = object
    code*: KeyCode
    rune*: uint32
    mods*: set[Modifier]

func keyChar*(rune: uint32, mods: set[Modifier] = {}): KeyEvent =
  KeyEvent(code: kChar, rune: rune, mods: mods)

func key*(code: KeyCode, mods: set[Modifier] = {}): KeyEvent =
  KeyEvent(code: code, mods: mods)

func mouse*(kind: MouseEventKind, button: MouseButton, row, col: int, mods: set[Modifier] = {}): MouseEvent =
  MouseEvent(kind: kind, button: button, row: row, col: col, mods: mods)
