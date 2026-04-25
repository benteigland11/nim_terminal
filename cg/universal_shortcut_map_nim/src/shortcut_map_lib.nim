## Universal keyboard and mouse shortcut manager.
##
## Provides a framework-agnostic way to define, store, and lookup
## action bindings for specific key/modifier combinations.

import std/[tables, options, hashes]

# ---------------------------------------------------------------------------
# Shared Input Types (Local copy for self-containment)
# ---------------------------------------------------------------------------

type
  Modifier* = enum
    modShift
    modAlt
    modCtrl
    modSuper

  KeyCodeKind* = enum
    kSpecial
    kChar

  KeyCode* = object
    case kind*: KeyCodeKind
    of kSpecial:
      special*: int # Map to our standard enum values
    of kChar:
      c*: char

# Standard special key constants
const
  kNone* = KeyCode(kind: kSpecial, special: 0)
  kEnter* = KeyCode(kind: kSpecial, special: 1)
  kTab* = KeyCode(kind: kSpecial, special: 2)
  kBackspace* = KeyCode(kind: kSpecial, special: 3)
  kEscape* = KeyCode(kind: kSpecial, special: 4)
  kEqual* = KeyCode(kind: kSpecial, special: 5)
  kMinus* = KeyCode(kind: kSpecial, special: 6)
  kPlus* = KeyCode(kind: kSpecial, special: 7)

func key*(c: char): KeyCode = KeyCode(kind: kChar, c: c)

func `==`*(a, b: KeyCode): bool =
  if a.kind != b.kind: return false
  case a.kind
  of kSpecial: result = a.special == b.special
  of kChar: result = a.c == b.c

func hash*(k: KeyCode): Hash =
  var h: Hash = 0
  h = h !& hash(k.kind)
  case k.kind
  of kSpecial: h = h !& hash(k.special)
  of kChar: h = h !& hash(k.c)
  result = !$h

# ---------------------------------------------------------------------------
# Shortcut Map
# ---------------------------------------------------------------------------

type
  Shortcut* = object
    code*: KeyCode
    mods*: set[Modifier]

func `==`*(a, b: Shortcut): bool =
  a.code == b.code and a.mods == b.mods

func hash*(s: Shortcut): Hash =
  result = hash(s.code) !& hash(s.mods)

type
  ShortcutMap* = ref object
    bindings: Table[Shortcut, string]

func newShortcutMap*(): ShortcutMap =
  ShortcutMap(bindings: initTable[Shortcut, string]())

proc bindAction*(m: ShortcutMap, code: KeyCode, mods: set[Modifier], action: string) =
  ## Associate a key combination with an action name.
  let s = Shortcut(code: code, mods: mods)
  m.bindings[s] = action

func lookup*(m: ShortcutMap, code: KeyCode, mods: set[Modifier]): Option[string] =
  ## Find the action bound to this key combination.
  let s = Shortcut(code: code, mods: mods)
  if m.bindings.hasKey(s):
    return some(m.bindings[s])
  none(string)

# ---------------------------------------------------------------------------
# Presets / Defaults
# ---------------------------------------------------------------------------

func addStandardTerminalShortcuts*(m: ShortcutMap) =
  ## Load standard terminal shortcuts like Copy/Paste and Zoom.
  m.bindAction(key('C'), {modCtrl, modShift}, "copy")
  m.bindAction(key('V'), {modCtrl, modShift}, "paste")
  m.bindAction(kEqual, {modCtrl}, "zoom-in")
  m.bindAction(kPlus, {modCtrl}, "zoom-in")
  m.bindAction(kMinus, {modCtrl}, "zoom-out")
