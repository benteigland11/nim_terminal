import std/unittest
import text_field_lib

suite "text field":
  test "insert and backspace":
    var field = newTextField()
    field.insertText("hello")
    check field.text == "hello"
    check field.caret == 5
    check field.backspace()
    check field.text == "hell"

  test "caret movement and mid-string insert":
    var field = newTextField("abc")
    field.moveHome()
    check field.caret == 0
    field.moveRight()
    field.insertText("X")
    check field.text == "aXbc"
    check field.caret == 2

  test "selection replace on insert":
    var field = newTextField("hello")
    field.moveHome()
    field.selectAll()
    check field.hasSelection()
    field.insertText("hi")
    check field.text == "hi"
    check not field.hasSelection()

  test "delete forward and selection bounds":
    var field = newTextField("world")
    field.moveHome()
    check field.deleteForward()
    check field.text == "orld"
    field.moveEnd()
    field.moveLeft(extend = true)
    let (lo, hi) = field.selectionBounds()
    check lo == 3
    check hi == 4

  test "viewport scrolls to keep caret visible":
    var field = newTextField("abcdefghij")
    field.moveEnd()
    let view = field.viewport(4)
    check view.text.len == 4
    check view.caretCol == 4
    check view.text == "ghij"

  test "multibyte runes counted correctly":
    var field = newTextField()
    field.insertText("café")
    check field.len == 4
    check field.backspace()
    check field.text == "caf"
