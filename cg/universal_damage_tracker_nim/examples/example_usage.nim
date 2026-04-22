## Simulate a render loop over a 5-row grid. The "app" writes to a few
## rows, the "renderer" queries which rows need repainting, paints them,
## and clears. Then a resize event invalidates the whole grid.

import damage_tracker_lib

var damage = newDamage(5)

# Frame 1 — app writes to rows 1 and 3.
damage.markRow(1)
damage.markRow(3)

doAssert damage.anyDirty
doAssert damage.fullRepaint == false
doAssert damage.dirtyRows == @[1, 3]

# Renderer paints only the dirty rows, then clears.
damage.clear
doAssert damage.anyDirty == false

# Frame 2 — app performs a scroll-like operation (whole range changes).
damage.markAll
doAssert damage.fullRepaint
doAssert damage.dirtyRows == @[0, 1, 2, 3, 4]
damage.clear

# Frame 3 — a range mutation (insert lines 2..4).
damage.markRows(2, 4)
doAssert damage.dirtyRows == @[2, 3, 4]
damage.clear

# The user resizes the surface from 5 rows to 8.
damage.resize(8)
doAssert damage.size == 8
doAssert damage.fullRepaint
doAssert damage.dirtyRows == @[0, 1, 2, 3, 4, 5, 6, 7]
damage.clear

# Out-of-range marks are silently ignored — callers don't need to
# bounds-check every upstream mutation.
damage.markRow(-1)
damage.markRow(99)
doAssert damage.anyDirty == false
