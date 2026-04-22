import std/unittest
import keyboard_vt_input_lib

func s(bytes: seq[byte]): string =
  result = newStringOfCap(bytes.len)
  for b in bytes: result.add char(b)

suite "printable characters":

  test "lowercase ascii is a single byte":
    check s(encode(keyChar(uint32('a')))) == "a"

  test "uppercase ascii is a single byte":
    check s(encode(keyChar(uint32('Z')))) == "Z"

  test "digit passes through":
    check s(encode(keyChar(uint32('7')))) == "7"

  test "utf-8 multibyte codepoint expands":
    # 'é' = U+00E9 → C3 A9
    let bytes = encode(keyChar(0x00E9'u32))
    check bytes == @[0xC3'u8, 0xA9'u8]

  test "wide codepoint expands to four bytes":
    # U+1F600 😀 → F0 9F 98 80
    let bytes = encode(keyChar(0x1F600'u32))
    check bytes == @[0xF0'u8, 0x9F'u8, 0x98'u8, 0x80'u8]

suite "Ctrl-modified characters":

  test "Ctrl+a → 0x01":
    check encode(keyChar(uint32('a'), {modCtrl})) == @[0x01'u8]

  test "Ctrl+A → 0x01 (uppercase equivalent)":
    check encode(keyChar(uint32('A'), {modCtrl})) == @[0x01'u8]

  test "Ctrl+c → 0x03":
    check encode(keyChar(uint32('c'), {modCtrl})) == @[0x03'u8]

  test "Ctrl+Space → NUL":
    check encode(keyChar(uint32(' '), {modCtrl})) == @[0x00'u8]

  test "Ctrl+[ → ESC":
    check encode(keyChar(uint32('['), {modCtrl})) == @[0x1B'u8]

  test "Ctrl+? → DEL":
    check encode(keyChar(uint32('?'), {modCtrl})) == @[0x7F'u8]

suite "Alt-modified characters":

  test "Alt+a emits ESC then 'a'":
    check encode(keyChar(uint32('a'), {modAlt})) == @[0x1B'u8, byte('a')]

  test "Alt+Ctrl+c combines both transforms":
    # Ctrl+c → 0x03, then Alt prepends ESC → ESC 0x03
    check encode(keyChar(uint32('c'), {modAlt, modCtrl})) == @[0x1B'u8, 0x03'u8]

suite "Enter / Tab / Backspace / Escape":

  test "Enter is CR":
    check encode(key(kEnter)) == @[0x0D'u8]

  test "Alt+Enter prepends ESC":
    check encode(key(kEnter, {modAlt})) == @[0x1B'u8, 0x0D'u8]

  test "Tab is HT":
    check encode(key(kTab)) == @[0x09'u8]

  test "Shift-Tab is CSI Z":
    check s(encode(key(kTab, {modShift}))) == "\x1B[Z"

  test "Backspace is DEL":
    check encode(key(kBackspace)) == @[0x7F'u8]

  test "Escape is ESC":
    check encode(key(kEscape)) == @[0x1B'u8]

  test "Alt+Escape is ESC ESC":
    check encode(key(kEscape, {modAlt})) == @[0x1B'u8, 0x1B'u8]

suite "arrow keys — default (CSI)":

  test "Up is CSI A":
    check s(encode(key(kArrowUp))) == "\x1B[A"

  test "Down is CSI B":
    check s(encode(key(kArrowDown))) == "\x1B[B"

  test "Right is CSI C":
    check s(encode(key(kArrowRight))) == "\x1B[C"

  test "Left is CSI D":
    check s(encode(key(kArrowLeft))) == "\x1B[D"

suite "arrow keys — application cursor mode":

  test "Up becomes SS3 A when cursorApp is on":
    var m = newKeyboardMode(); m.cursorApp = true
    check s(encode(key(kArrowUp), m)) == "\x1BOA"

  test "Right becomes SS3 C when cursorApp is on":
    var m = newKeyboardMode(); m.cursorApp = true
    check s(encode(key(kArrowRight), m)) == "\x1BOC"

  test "modifier forces CSI 1;p form even in cursorApp":
    var m = newKeyboardMode(); m.cursorApp = true
    check s(encode(key(kArrowUp, {modCtrl}), m)) == "\x1B[1;5A"

suite "modifier-decorated cursor keys":

  test "Shift+Up is CSI 1;2 A":
    check s(encode(key(kArrowUp, {modShift}))) == "\x1B[1;2A"

  test "Alt+Right is CSI 1;3 C":
    check s(encode(key(kArrowRight, {modAlt}))) == "\x1B[1;3C"

  test "Ctrl+Left is CSI 1;5 D":
    check s(encode(key(kArrowLeft, {modCtrl}))) == "\x1B[1;5D"

  test "Ctrl+Shift+End is CSI 1;6 F":
    check s(encode(key(kEnd, {modCtrl, modShift}))) == "\x1B[1;6F"

suite "Home / End / nav cluster":

  test "Home is CSI H":
    check s(encode(key(kHome))) == "\x1B[H"

  test "End is CSI F":
    check s(encode(key(kEnd))) == "\x1B[F"

  test "Insert is CSI 2~":
    check s(encode(key(kInsert))) == "\x1B[2~"

  test "Delete is CSI 3~":
    check s(encode(key(kDelete))) == "\x1B[3~"

  test "PageUp is CSI 5~":
    check s(encode(key(kPageUp))) == "\x1B[5~"

  test "PageDown is CSI 6~":
    check s(encode(key(kPageDown))) == "\x1B[6~"

  test "Ctrl+Delete is CSI 3;5~":
    check s(encode(key(kDelete, {modCtrl}))) == "\x1B[3;5~"

suite "function keys":

  test "F1 is SS3 P":
    check s(encode(key(kF1))) == "\x1BOP"

  test "F4 is SS3 S":
    check s(encode(key(kF4))) == "\x1BOS"

  test "F5 is CSI 15~":
    check s(encode(key(kF5))) == "\x1B[15~"

  test "F12 is CSI 24~":
    check s(encode(key(kF12))) == "\x1B[24~"

  test "Shift+F1 uses CSI 1;2 P":
    check s(encode(key(kF1, {modShift}))) == "\x1B[1;2P"

  test "Ctrl+F5 is CSI 15;5~":
    check s(encode(key(kF5, {modCtrl}))) == "\x1B[15;5~"

suite "keypad Enter":

  test "default mode is CR":
    check encode(key(kKeypadEnter)) == @[0x0D'u8]

  test "app keypad mode is SS3 M":
    var m = newKeyboardMode(); m.keypadApp = true
    check s(encode(key(kKeypadEnter), m)) == "\x1BOM"

suite "misc":

  test "kNone emits nothing":
    check encode(key(kNone)).len == 0

  test "kChar with rune 0 emits nothing":
    check encode(keyChar(0'u32)).len == 0

  test "encodeString passes ASCII through":
    check s(encodeString("hello")) == "hello"

  test "xterm modParam bitmask: all modifiers → 16":
    # 1 + shift(1) + alt(2) + ctrl(4) + meta(8) = 16
    check s(encode(key(kArrowUp, {modShift, modAlt, modCtrl, modSuper}))) ==
      "\x1B[1;16A"
