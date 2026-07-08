## Example usage of Focus Ring.

import focus_ring_lib

# A hybrid app where a live terminal is the default surface and chrome
# regions can grab focus explicitly.
var ring = newFocusRing(["terminal", "search", "catalog"])

# Nothing focused yet: the host routes keys to the terminal.
assert not ring.hasFocus()

# Clicking the search box focuses it.
discard ring.focus("search")
assert ring.isFocused("search")

# Tab cycles to the next region.
ring.focusNext()
assert ring.current() == "catalog"

# Escape returns control to the default surface.
ring.clearFocus()
assert not ring.hasFocus()
