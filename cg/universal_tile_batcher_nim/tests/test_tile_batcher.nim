import std/unittest
import ../src/tile_batcher_lib

suite "tile batcher":

  test "creation and basic usage":
    let b = newTileBatcher(1)
    check b.textureId == 1
    b.beginBatch()
    b.addTile(0, 0, 1, 1, 0, 0, 1, 1, rgba(1, 1, 1, 1))
    var drew = false
    b.endBatch(proc (textureId: uint32; vertices: openArray[TileVertex]) =
      drew = true
      check textureId == 1
      check vertices.len == 6
      check vertices[0].x == 0
      check vertices[1].x == 1
    )
    check drew

  test "capacity limits added tiles":
    let b = newTileBatcher(7, capacity = 6)
    b.beginBatch()
    b.addTile(0, 0, 1, 1, 0, 0, 1, 1, rgba(1, 1, 1, 1))
    b.addTile(2, 0, 1, 1, 0, 0, 1, 1, rgba(1, 1, 1, 1))
    check b.vertexCount == 6
