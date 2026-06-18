## Backend-neutral GPU relay contract.
##
## The widget owns the small graphics-device surface that renderers can call
## without importing a concrete graphics API. Applications install callbacks
## backed by OpenGL, a mock driver, or another GPU implementation.

type
  GpuTextureId* = distinct uint32
  GpuBufferId* = distinct uint32

  GpuVertex* = object
    x*, y*: float32
    u*, v*: float32
    r*, g*, b*, a*: float32

  GpuTextureFilter* = enum
    gtfNearest
    gtfLinear

  GpuTextureWrap* = enum
    gtwClampToEdge
    gtwRepeat

  GpuTextureOptions* = object
    minFilter*: GpuTextureFilter
    magFilter*: GpuTextureFilter
    wrapS*: GpuTextureWrap
    wrapT*: GpuTextureWrap

  GpuRelays* = object
    createTextureProc*: proc (): GpuTextureId {.closure.}
    deleteTextureProc*: proc (id: GpuTextureId) {.closure.}
    configureTextureProc*: proc (id: GpuTextureId; options: GpuTextureOptions) {.closure.}
    uploadRgba8TextureProc*: proc (id: GpuTextureId; width, height: int; pixels: pointer) {.closure.}
    drawTexturedTrianglesProc*: proc (textureId: GpuTextureId; vertices: openArray[GpuVertex]) {.closure.}
    enableAlphaBlendingProc*: proc () {.closure.}
    flushProc*: proc () {.closure.}

func textureId*(value: uint32): GpuTextureId = GpuTextureId(value)
func uint32Value*(id: GpuTextureId): uint32 = uint32(id)
func bufferId*(value: uint32): GpuBufferId = GpuBufferId(value)
func uint32Value*(id: GpuBufferId): uint32 = uint32(id)

func defaultTextureOptions*(filter: GpuTextureFilter = gtfLinear): GpuTextureOptions =
  GpuTextureOptions(
    minFilter: filter,
    magFilter: filter,
    wrapS: gtwClampToEdge,
    wrapT: gtwClampToEdge,
  )

func noopGpuRelays*(): GpuRelays =
  GpuRelays()

proc createTexture*(relays: GpuRelays): GpuTextureId =
  if relays.createTextureProc == nil:
    return textureId(0)
  relays.createTextureProc()

proc deleteTexture*(relays: GpuRelays; id: GpuTextureId) =
  if relays.deleteTextureProc != nil and id.uint32Value != 0:
    relays.deleteTextureProc(id)

proc configureTexture*(relays: GpuRelays; id: GpuTextureId; options: GpuTextureOptions) =
  if relays.configureTextureProc != nil and id.uint32Value != 0:
    relays.configureTextureProc(id, options)

proc uploadRgba8Texture*(relays: GpuRelays; id: GpuTextureId; width, height: int; pixels: pointer) =
  if relays.uploadRgba8TextureProc != nil and id.uint32Value != 0 and width > 0 and height > 0:
    relays.uploadRgba8TextureProc(id, width, height, pixels)

proc uploadSolidRgba8Texture*(relays: GpuRelays; id: GpuTextureId; pixel: var uint32) =
  relays.uploadRgba8Texture(id, 1, 1, addr pixel)

proc drawTexturedTriangles*(relays: GpuRelays; textureId: GpuTextureId; vertices: openArray[GpuVertex]) =
  if relays.drawTexturedTrianglesProc != nil and textureId.uint32Value != 0 and vertices.len > 0:
    relays.drawTexturedTrianglesProc(textureId, vertices)

proc enableAlphaBlending*(relays: GpuRelays) =
  if relays.enableAlphaBlendingProc != nil:
    relays.enableAlphaBlendingProc()

proc flush*(relays: GpuRelays) =
  if relays.flushProc != nil:
    relays.flushProc()

func hasTextureSupport*(relays: GpuRelays): bool =
  relays.createTextureProc != nil and relays.deleteTextureProc != nil and
    relays.configureTextureProc != nil and relays.uploadRgba8TextureProc != nil
