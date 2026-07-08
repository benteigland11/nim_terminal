import std/unittest
import focus_ring_lib

suite "focus ring":
  test "starts unfocused by default":
    var ring = newFocusRing(["terminal", "search", "list"])
    check not ring.hasFocus()
    check ring.current() == ""

  test "focus by id":
    var ring = newFocusRing(["terminal", "search", "list"])
    check ring.focus("search")
    check ring.isFocused("search")
    check not ring.focus("missing")

  test "next and prev wrap in tab order":
    var ring = newFocusRing(["a", "b", "c"])
    ring.focusFirst()
    check ring.current() == "a"
    ring.focusNext()
    check ring.current() == "b"
    ring.focusNext()
    ring.focusNext()
    check ring.current() == "a"
    ring.focusPrev()
    check ring.current() == "c"

  test "next from unfocused focuses first":
    var ring = newFocusRing(["a", "b"])
    ring.focusNext()
    check ring.current() == "a"

  test "clear returns to unfocused":
    var ring = newFocusRing(["a", "b"], focused = "b")
    check ring.isFocused("b")
    ring.clearFocus()
    check not ring.hasFocus()
