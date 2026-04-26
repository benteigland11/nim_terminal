## GLFW event → Standard input types translator.
##
## Maps GLFW's raw key and mouse constants into the platform-neutral
## types used by the terminal pipeline.

import staticglfw
import std/options
import input_types

export input_types

func toModifiers*(glfwMods: cint): set[Modifier] =
  ## Map GLFW modifier bitmask to our Modifier set.
  if (glfwMods and MOD_SHIFT) != 0: result.incl modShift
  if (glfwMods and MOD_CONTROL) != 0: result.incl modCtrl
  if (glfwMods and MOD_ALT) != 0: result.incl modAlt
  if (glfwMods and MOD_SUPER) != 0: result.incl modSuper

func toKeyCode*(glfwKey: cint): KeyCode =
  ## Map GLFW physical key constants to our KeyCode enum.
  case glfwKey
  of KEY_ENTER:       kEnter
  of KEY_TAB:         kTab
  of KEY_BACKSPACE:   kBackspace
  of KEY_ESCAPE:      kEscape
  of KEY_INSERT:      kInsert
  of KEY_DELETE:      kDelete
  of KEY_HOME:        kHome
  of KEY_END:         kEnd
  of KEY_PAGE_UP:     kPageUp
  of KEY_PAGE_DOWN:   kPageDown
  of KEY_UP:          kArrowUp
  of KEY_DOWN:        kArrowDown
  of KEY_LEFT:        kArrowLeft
  of KEY_RIGHT:       kArrowRight
  of KEY_F1:  kF1
  of KEY_F2:  kF2
  of KEY_F3:  kF3
  of KEY_F4:  kF4
  of KEY_F5:  kF5
  of KEY_F6:  kF6
  of KEY_F7:  kF7
  of KEY_F8:  kF8
  of KEY_F9:  kF9
  of KEY_F10: kF10
  of KEY_F11: kF11
  of KEY_F12: kF12
  of KEY_KP_ENTER:    kKeypadEnter
  else: kNone

func toMouseButton*(glfwBtn: cint): MouseButton =
  ## Map GLFW mouse button constants to our MouseButton enum.
  case glfwBtn
  of MOUSE_BUTTON_LEFT:   mbLeft
  of MOUSE_BUTTON_MIDDLE: mbMiddle
  of MOUSE_BUTTON_RIGHT:  mbRight
  else: mbRelease

func toPrintableRune*(glfwKey: cint, glfwMods: cint): Option[uint32] =
  ## Map GLFW's physical printable keys plus shift state to a Unicode rune.
  ##
  ## This is useful for key paths where the GLFW character callback does not
  ## fire, such as Ctrl/Alt combinations that still need a printable base rune.
  let shifted = (glfwMods and MOD_SHIFT) != 0
  case glfwKey
  of KEY_SPACE: some(uint32(' '))
  of KEY_A .. KEY_Z:
    some(uint32((if shifted: ord('A') else: ord('a')) + (glfwKey - KEY_A)))
  of KEY_0 .. KEY_9:
    if shifted:
      case glfwKey
      of KEY_0: some(uint32(')'))
      of KEY_1: some(uint32('!'))
      of KEY_2: some(uint32('@'))
      of KEY_3: some(uint32('#'))
      of KEY_4: some(uint32('$'))
      of KEY_5: some(uint32('%'))
      of KEY_6: some(uint32('^'))
      of KEY_7: some(uint32('&'))
      of KEY_8: some(uint32('*'))
      of KEY_9: some(uint32('('))
      else: none(uint32)
    else:
      some(uint32(ord('0') + (glfwKey - KEY_0)))
  of KEY_APOSTROPHE: some(uint32(if shifted: '"' else: '\''))
  of KEY_COMMA: some(uint32(if shifted: '<' else: ','))
  of KEY_MINUS: some(uint32(if shifted: '_' else: '-'))
  of KEY_PERIOD: some(uint32(if shifted: '>' else: '.'))
  of KEY_SLASH: some(uint32(if shifted: '?' else: '/'))
  of KEY_SEMICOLON: some(uint32(if shifted: ':' else: ';'))
  of KEY_EQUAL: some(uint32(if shifted: '+' else: '='))
  of KEY_LEFT_BRACKET: some(uint32(if shifted: '{' else: '['))
  of KEY_BACKSLASH: some(uint32(if shifted: '|' else: '\\'))
  of KEY_RIGHT_BRACKET: some(uint32(if shifted: '}' else: ']'))
  of KEY_GRAVE_ACCENT: some(uint32(if shifted: '~' else: '`'))
  else: none(uint32)
