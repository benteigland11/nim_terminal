import gpu_relays_lib

var uploaded = false
var drawn = false
let relays = GpuRelays(
  createTextureProc: proc (): GpuTextureId = textureId(1),
  uploadRgba8TextureProc: proc (id: GpuTextureId; width, height: int; pixels: pointer) =
    uploaded = id.uint32Value == 1 and width == 1 and height == 1 and pixels != nil,
  drawTexturedTrianglesProc: proc (id: GpuTextureId; vertices: openArray[GpuVertex]) =
    drawn = id.uint32Value == 1 and vertices.len == 1,
)

let id = relays.createTexture()
var pixel = 0xffffffff'u32
relays.uploadSolidRgba8Texture(id, pixel)
relays.drawTexturedTriangles(id, [GpuVertex(x: 0, y: 0, u: 0, v: 0, r: 1, g: 1, b: 1, a: 1)])
doAssert uploaded
doAssert drawn
