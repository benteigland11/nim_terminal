## GLFW event → Standard input types translator.
##
## Maps GLFW's raw key and mouse constants into the platform-neutral
## types used by the terminal pipeline.

import staticglfw
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
