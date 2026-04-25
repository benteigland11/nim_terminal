import std/[options, unittest]
import tab_set_lib

suite "Tab Set":
  test "first added tab becomes active":
    var tabs = newTabSet()
    let first = tabs.addTab("one", activate = false)

    check tabs.len == 1
    check tabs.activeId.isSome
    check tabs.activeId.get() == first

  test "add can activate a later tab":
    var tabs = newTabSet()
    let first = tabs.addTab("one")
    let second = tabs.addTab("two")

    check tabs.activeId.get() == second
    check tabs.activeIndex() == 1
    check tabs.activeTab().get().label == "two"
    check tabs.contains(first)

  test "activation rejects unknown ids":
    var tabs = newTabSet()
    discard tabs.addTab("one")

    check tabs.activate(TabId(999)) == false
    check tabs.activeIndex() == 0

  test "closing active tab activates the next available tab":
    var tabs = newTabSet()
    let first = tabs.addTab("one")
    let second = tabs.addTab("two")
    let third = tabs.addTab("three")
    discard tabs.activate(second)

    check tabs.close(second)
    check tabs.activeId.get() == third
    check tabs.close(third)
    check tabs.activeId.get() == first

  test "closing final tab clears active id":
    var tabs = newTabSet()
    let first = tabs.addTab("one")

    check tabs.close(first)
    check tabs.isEmpty
    check tabs.activeId.isNone

  test "rename and cycle tabs":
    var tabs = newTabSet()
    let first = tabs.addTab("one")
    let second = tabs.addTab("two")

    check tabs.rename(first, "renamed")
    discard tabs.activate(first)
    check tabs.activeTab().get().label == "renamed"
    check tabs.activateNext()
    check tabs.activeId.get() == second
    check tabs.activatePrevious()
    check tabs.activeId.get() == first
