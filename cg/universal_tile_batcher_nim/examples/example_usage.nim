## Example usage of Tile Batcher.
##
## Demonstrates the batching API.

import tile_batcher_lib

let batcher = newTileBatcher(1)
batcher.beginBatch()
batcher.addTile(0, 0, 1, 1, 0, 0, 1, 1, rgba(1, 1, 1, 1))

var submitted = 0
batcher.endBatch(proc (textureId: uint32; vertices: openArray[TileVertex]) =
  doAssert textureId == 1
  submitted = vertices.len
)

doAssert submitted == 6
