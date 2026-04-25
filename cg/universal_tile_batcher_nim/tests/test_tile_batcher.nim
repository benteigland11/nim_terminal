import std/unittest
import ../src/tile_batcher_lib

suite "tile batcher":

  test "creation and basic usage":
    # Just verify the object can be created without crashing.
    # The lib will detect no context and skip GL calls internally.
    let b = newTileBatcher(1)
    check b.textureId == 1
    b.beginBatch()
    b.addTile(0, 0, 1, 1, 0, 0, 1, 1, rgba(1, 1, 1, 1))
    b.endBatch()
