## SDL3 event → standard input types translator.
##
## Maps SDL3-compatible scancode, keycode, modifier, and mouse constants into
## platform-neutral terminal input types. Numpad digits and operators share
## identity with the main key row for printables and shortcut bindings.
##
## Constants match SDL3 numeric values so callers may pass raw SDL3 fields
## without this widget importing the SDL package (keeps validation portable).

import std/options
import input_types

export input_types

# ---------------------------------------------------------------------------
# SDL3-compatible constants (numeric values match SDL3)
# ---------------------------------------------------------------------------

const
  # Modifier masks
  KmodShift* = 0x0003'u32
  KmodCtrl* = 0x00C0'u32
  KmodAlt* = 0x0300'u32
  KmodGui* = 0x0C00'u32

  # Mouse buttons
  ButtonLeft* = 1'u8
  ButtonMiddle* = 2'u8
  ButtonRight* = 3'u8

  # Scancodes used for special terminal keys
  ScReturn* = 40
  ScEscape* = 41
  ScBackspace* = 42
  ScTab* = 43
  ScInsert* = 73
  ScHome* = 74
  ScPageUp* = 75
  ScDelete* = 76
  ScEnd* = 77
  ScPageDown* = 78
  ScRight* = 79
  ScLeft* = 80
  ScDown* = 81
  ScUp* = 82
  ScF1* = 58
  ScF2* = 59
  ScF3* = 60
  ScF4* = 61
  ScF5* = 62
  ScF6* = 63
  ScF7* = 64
  ScF8* = 65
  ScF9* = 66
  ScF10* = 67
  ScF11* = 68
  ScF12* = 69
  ScKpEnter* = 88

  # Keycodes (ASCII-range + extended keypad)
  KeyReturn* = 0x0000000d'u32
  KeyEscape* = 0x0000001b'u32
  KeyBackspace* = 0x00000008'u32
  KeyTab* = 0x00000009'u32
  KeyPlus* = 0x0000002b'u32
  KeyMinus* = 0x0000002d'u32
  KeyEquals* = 0x0000003d'u32
  Key0* = 0x00000030'u32
  Key1* = 0x00000031'u32
  Key9* = 0x00000039'u32
  KeyA* = 0x00000061'u32
  KeyZ* = 0x0000007a'u32
  KeyKpDivide* = 0x40000054'u32
  KeyKpMultiply* = 0x40000055'u32
  KeyKpMinus* = 0x40000056'u32
  KeyKpPlus* = 0x40000057'u32
  KeyKpEnter* = 0x40000058'u32
  KeyKp1* = 0x40000059'u32
  KeyKp2* = 0x4000005a'u32
  KeyKp3* = 0x4000005b'u32
  KeyKp4* = 0x4000005c'u32
  KeyKp5* = 0x4000005d'u32
  KeyKp6* = 0x4000005e'u32
  KeyKp7* = 0x4000005f'u32
  KeyKp8* = 0x40000060'u32
  KeyKp9* = 0x40000061'u32
  KeyKp0* = 0x40000062'u32
  KeyKpPeriod* = 0x40000063'u32
  KeyKpEquals* = 0x40000067'u32

type
  ShortcutIdKind* = enum
    siNone
    siChar
    siEnter
    siEqual
    siMinus
    siPlus

  ShortcutId* = object
    ## Backend-neutral shortcut identity for one physical key.
    case kind*: ShortcutIdKind
    of siChar:
      ch*: char
    else:
      discard

func toModifiers*(modMask: uint32): set[Modifier] =
  ## Map an SDL3-compatible modifier bitmask to our Modifier set.
  if (modMask and KmodShift) != 0: result.incl modShift
  if (modMask and KmodCtrl) != 0: result.incl modCtrl
  if (modMask and KmodAlt) != 0: result.incl modAlt
  if (modMask and KmodGui) != 0: result.incl modSuper

func toKeyCode*(scancode: int): KeyCode =
  ## Map an SDL3-compatible scancode to a terminal KeyCode.
  case scancode
  of ScReturn: kEnter
  of ScTab: kTab
  of ScBackspace: kBackspace
  of ScEscape: kEscape
  of ScInsert: kInsert
  of ScDelete: kDelete
  of ScHome: kHome
  of ScEnd: kEnd
  of ScPageUp: kPageUp
  of ScPageDown: kPageDown
  of ScUp: kArrowUp
  of ScDown: kArrowDown
  of ScLeft: kArrowLeft
  of ScRight: kArrowRight
  of ScF1: kF1
  of ScF2: kF2
  of ScF3: kF3
  of ScF4: kF4
  of ScF5: kF5
  of ScF6: kF6
  of ScF7: kF7
  of ScF8: kF8
  of ScF9: kF9
  of ScF10: kF10
  of ScF11: kF11
  of ScF12: kF12
  of ScKpEnter: kKeypadEnter
  else: kNone

func toMouseButton*(button: uint8): MouseButton =
  ## Map an SDL3-compatible mouse button id to our MouseButton enum.
  case button
  of ButtonLeft: mbLeft
  of ButtonMiddle: mbMiddle
  of ButtonRight: mbRight
  else: mbRelease

func shortcutChar(c: char): char =
  if c >= 'a' and c <= 'z':
    char(ord(c) - ord('a') + ord('A'))
  else:
    c

func toShortcutId*(keycode: uint32): ShortcutId =
  ## Map an SDL3-compatible keycode to a unified shortcut identity.
  ##
  ## Top-row digits and keypad digits both become `siChar` digits so one
  ## Alt+1 binding matches both keys.
  case keycode
  of KeyReturn, KeyKpEnter:
    ShortcutId(kind: siEnter)
  of KeyEquals, KeyKpEquals:
    ShortcutId(kind: siEqual)
  of KeyMinus, KeyKpMinus:
    ShortcutId(kind: siMinus)
  of KeyPlus, KeyKpPlus:
    ShortcutId(kind: siPlus)
  of Key0 .. Key9:
    ShortcutId(kind: siChar, ch: char(keycode))
  of KeyKp0:
    ShortcutId(kind: siChar, ch: '0')
  of KeyKp1:
    ShortcutId(kind: siChar, ch: '1')
  of KeyKp2:
    ShortcutId(kind: siChar, ch: '2')
  of KeyKp3:
    ShortcutId(kind: siChar, ch: '3')
  of KeyKp4:
    ShortcutId(kind: siChar, ch: '4')
  of KeyKp5:
    ShortcutId(kind: siChar, ch: '5')
  of KeyKp6:
    ShortcutId(kind: siChar, ch: '6')
  of KeyKp7:
    ShortcutId(kind: siChar, ch: '7')
  of KeyKp8:
    ShortcutId(kind: siChar, ch: '8')
  of KeyKp9:
    ShortcutId(kind: siChar, ch: '9')
  of KeyA .. KeyZ:
    ShortcutId(kind: siChar, ch: shortcutChar(char(keycode)))
  else:
    if keycode >= 32'u32 and keycode <= 126'u32:
      ShortcutId(kind: siChar, ch: shortcutChar(char(keycode)))
    else:
      ShortcutId(kind: siNone)

func toPrintableRune*(keycode: uint32): Option[uint32] =
  ## Map an SDL3-compatible keycode to a Unicode rune when it is printable.
  ##
  ## Keypad digits and operators use the same characters as the main set.
  case keycode
  of KeyKp0:
    some(uint32('0'))
  of KeyKp1:
    some(uint32('1'))
  of KeyKp2:
    some(uint32('2'))
  of KeyKp3:
    some(uint32('3'))
  of KeyKp4:
    some(uint32('4'))
  of KeyKp5:
    some(uint32('5'))
  of KeyKp6:
    some(uint32('6'))
  of KeyKp7:
    some(uint32('7'))
  of KeyKp8:
    some(uint32('8'))
  of KeyKp9:
    some(uint32('9'))
  of KeyKpPeriod:
    some(uint32('.'))
  of KeyKpDivide:
    some(uint32('/'))
  of KeyKpMultiply:
    some(uint32('*'))
  of KeyKpMinus:
    some(uint32('-'))
  of KeyKpPlus:
    some(uint32('+'))
  of KeyKpEquals:
    some(uint32('='))
  else:
    if keycode >= 32'u32 and keycode <= 126'u32:
      some(keycode)
    else:
      none(uint32)
