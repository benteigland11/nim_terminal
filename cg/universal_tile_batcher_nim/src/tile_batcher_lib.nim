## Tile Batcher.
##
## Efficiently collects many small quads (tiles) as triangles. The caller owns
## the backend-specific upload/draw step by passing a sink to `endBatch`.

type
  RgbaColor* = object
    r*, g*, b*, a*: float32

  TileVertex* = object
    x*, y*: float32
    u*, v*: float32
    r*, g*, b*, a*: float32

  TileBatchSink* = proc (textureId: uint32; vertices: openArray[TileVertex]) {.closure.}

  TileBatcher* = ref object
    textureId*: uint32
    vertices: seq[TileVertex]
    capacity: int
    count: int

func rgba*(r, g, b, a: float32): RgbaColor = RgbaColor(r: r, g: g, b: b, a: a)

proc newTileBatcher*(textureId: uint32, capacity: int = 50000): TileBatcher =
  TileBatcher(
    textureId: textureId,
    vertices: newSeq[TileVertex](capacity),
    capacity: capacity,
    count: 0,
  )

func gpuBufferId*(b: TileBatcher): uint32 =
  0'u32

func vertexCapacity*(b: TileBatcher): int =
  if b == nil: 0 else: b.capacity

func vertexCount*(b: TileBatcher): int =
  if b == nil: 0 else: b.count

func vertexCapacityBytes*(b: TileBatcher): int64 =
  if b == nil: 0'i64 else: int64(b.capacity) * int64(sizeof(TileVertex))

func uploadedVertexBytes*(b: TileBatcher): int64 =
  if b == nil: 0'i64 else: int64(b.count) * int64(sizeof(TileVertex))

proc beginBatch*(b: TileBatcher) =
  if b == nil: return
  b.count = 0

proc addTile*(b: TileBatcher, x, y, w, h: float32, u1, v1, u2, v2: float32, color: RgbaColor) =
  if b == nil: return
  if b.count + 6 > b.capacity: return

  let r = color.r
  let g = color.g
  let b1 = color.b
  let a = color.a
  let i = b.count

  b.vertices[i + 0] = TileVertex(x: x,     y: y,     u: u1, v: v1, r: r, g: g, b: b1, a: a)
  b.vertices[i + 1] = TileVertex(x: x + w, y: y,     u: u2, v: v1, r: r, g: g, b: b1, a: a)
  b.vertices[i + 2] = TileVertex(x: x + w, y: y - h, u: u2, v: v2, r: r, g: g, b: b1, a: a)
  b.vertices[i + 3] = TileVertex(x: x,     y: y,     u: u1, v: v1, r: r, g: g, b: b1, a: a)
  b.vertices[i + 4] = TileVertex(x: x + w, y: y - h, u: u2, v: v2, r: r, g: g, b: b1, a: a)
  b.vertices[i + 5] = TileVertex(x: x,     y: y - h, u: u1, v: v2, r: r, g: g, b: b1, a: a)
  b.count += 6

proc endBatch*(b: TileBatcher) =
  discard

proc endBatch*(b: TileBatcher; sink: TileBatchSink) =
  if b == nil or b.count == 0 or sink == nil: return
  sink(b.textureId, b.vertices.toOpenArray(0, b.count - 1))

proc dispose*(b: TileBatcher) =
  if b == nil: return
  b.count = 0
