import std/options
import tab_set_lib

var tabs = newTabSet()
let first = tabs.addTab("alpha")
let second = tabs.addTab("beta")

doAssert tabs.len == 2
doAssert tabs.activeId.get() == second

discard tabs.activate(first)
doAssert tabs.activeTab().get().label == "alpha"

discard tabs.rename(first, "renamed")
doAssert tabs.activeTab().get().label == "renamed"

discard tabs.activateNext()
doAssert tabs.activeId.get() == second
