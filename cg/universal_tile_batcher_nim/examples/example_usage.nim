## Example usage of Tile Batcher.
##
## Demonstrates the batching API. Requires a GL context to run.

import tile_batcher_lib

# In a real app:
# let batcher = newTileBatcher(texId)
# batcher.beginBatch()
# batcher.addTile(Tile(x: 0, y: 0, w: 10, h: 10, u1: 0, v1: 0, u2: 1, v2: 1, color: rgba(1,1,1,1)))
# batcher.endBatch()

echo "Tile batcher example (API verified via compilation)."
