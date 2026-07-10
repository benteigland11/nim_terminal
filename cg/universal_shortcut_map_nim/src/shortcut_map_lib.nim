## Universal keyboard and mouse shortcut manager.
##
## Provides a framework-agnostic way to define, store, and lookup
## action bindings for specific key/modifier combinations.
##
## Dual physical keys (top-row digit vs keypad digit, Enter vs keypad Enter,
## + vs keypad Add, letter case) share one binding identity via `canonicalKey`.

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
  ## Pre-canonical keypad forms. Lookup resolves these via `canonicalKey`.
  kKeypadEnter* = KeyCode(kind: kSpecial, special: 20)
  kKeypadAdd* = KeyCode(kind: kSpecial, special: 21)
  kKeypadSubtract* = KeyCode(kind: kSpecial, special: 22)
  kKeypadMultiply* = KeyCode(kind: kSpecial, special: 23)
  kKeypadDivide* = KeyCode(kind: kSpecial, special: 24)
  kKeypadDecimal* = KeyCode(kind: kSpecial, special: 25)
  kKeypad0* = KeyCode(kind: kSpecial, special: 30)
  kKeypad1* = KeyCode(kind: kSpecial, special: 31)
  kKeypad2* = KeyCode(kind: kSpecial, special: 32)
  kKeypad3* = KeyCode(kind: kSpecial, special: 33)
  kKeypad4* = KeyCode(kind: kSpecial, special: 34)
  kKeypad5* = KeyCode(kind: kSpecial, special: 35)
  kKeypad6* = KeyCode(kind: kSpecial, special: 36)
  kKeypad7* = KeyCode(kind: kSpecial, special: 37)
  kKeypad8* = KeyCode(kind: kSpecial, special: 38)
  kKeypad9* = KeyCode(kind: kSpecial, special: 39)

func key*(c: char): KeyCode = KeyCode(kind: kChar, c: c)

func shortcutKey*(c: char): KeyCode =
  ## Canonicalize printable letter shortcuts so backend-specific keycodes
  ## resolve the same action for Ctrl+Shift+C, Ctrl+Shift+V, etc.
  if c >= 'a' and c <= 'z':
    key(char(ord(c) - ord('a') + ord('A')))
  else:
    key(c)

func digitKey*(n: range[0..9]): KeyCode =
  ## Canonical digit binding identity for both top-row and keypad digits.
  shortcutKey(char(ord('0') + n))

func keypadDigit*(n: range[0..9]): KeyCode =
  ## Pre-canonical keypad digit; `canonicalKey` / `lookup` map it to `digitKey`.
  KeyCode(kind: kSpecial, special: 30 + n)

func canonicalKey*(code: KeyCode): KeyCode =
  ## Collapse dual physical keys onto the binding identity used at bind time.
  ##
  ## - letters → uppercase char keys
  ## - keypad digits → digit char keys
  ## - keypad Enter / Add / Subtract → Enter / Plus / Minus
  ## - keypad * / / / . → char keys
  case code.kind
  of kChar:
    shortcutKey(code.c)
  of kSpecial:
    case code.special
    of 20: kEnter
    of 21: kPlus
    of 22: kMinus
    of 23: key('*')
    of 24: key('/')
    of 25: key('.')
    of 30..39: digitKey(code.special - 30)
    else: code

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
  ## Stores the canonical form so dual physical keys match one binding.
  let s = Shortcut(code: canonicalKey(code), mods: mods)
  m.bindings[s] = action

proc bindAction*(m: ShortcutMap, codes: openArray[KeyCode], mods: set[Modifier],
    action: string) =
  ## Bind several physical/pre-canonical keys to the same action.
  for code in codes:
    m.bindAction(code, mods, action)

func lookup*(m: ShortcutMap, code: KeyCode, mods: set[Modifier]): Option[string] =
  ## Find the action bound to this key combination.
  ## Tries the raw code first, then `canonicalKey(code)`.
  let raw = Shortcut(code: code, mods: mods)
  if m.bindings.hasKey(raw):
    return some(m.bindings[raw])
  let can = canonicalKey(code)
  if can != code:
    let s = Shortcut(code: can, mods: mods)
    if m.bindings.hasKey(s):
      return some(m.bindings[s])
  none(string)

# ---------------------------------------------------------------------------
# Presets / Defaults
# ---------------------------------------------------------------------------

func addStandardTerminalShortcuts*(m: ShortcutMap) =
  ## Load standard terminal shortcuts like Copy/Paste and Zoom.
  ##
  ## Host paste is Ctrl+Shift+V only. Plain Ctrl+V is left for the child so
  ## apps like Claude Code can use it for image paste and other app shortcuts.
  m.bindAction(shortcutKey('C'), {modCtrl, modShift}, "copy")
  m.bindAction(shortcutKey('V'), {modCtrl, modShift}, "paste")
  m.bindAction(shortcutKey('W'), {modCtrl}, "close-tab")
  for i in 1 .. 9:
    m.bindAction(digitKey(i), {modAlt}, "tab-" & $i)
  m.bindAction([kEqual, kPlus, kKeypadAdd], {modCtrl}, "zoom-in")
  m.bindAction([kEqual, kPlus, kKeypadAdd], {modCtrl, modShift}, "zoom-in")
  m.bindAction([kMinus, kKeypadSubtract], {modCtrl}, "zoom-out")

func addAgentTerminalShortcuts*(m: ShortcutMap) =
  ## Load standard shortcuts plus agent-oriented bindings.
  m.addStandardTerminalShortcuts()
  m.bindAction(shortcutKey('A'), {modCtrl, modShift}, "switch-surface")
