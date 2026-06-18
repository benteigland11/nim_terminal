import std/unittest
import ../src/gpu_relays_lib

suite "gpu relays":

  test "noop relays are safe":
    let relays = noopGpuRelays()
    check relays.createTexture().uint32Value == 0
    relays.deleteTexture(textureId(7))
    var pixel = 0xffffffff'u32
    relays.uploadSolidRgba8Texture(textureId(7), pixel)
    relays.enableAlphaBlending()
    relays.flush()

  test "callbacks receive texture operations":
    var created = false
    var deleted = 0'u32
    var configured = 0'u32
    var uploaded: tuple[id: uint32, width: int, height: int] = (0'u32, 0, 0)
    var drawn = 0
    var blended = false
    var flushed = false

    proc createExampleTexture(): GpuTextureId =
      created = true
      textureId(42)

    proc deleteExampleTexture(id: GpuTextureId) =
      deleted = id.uint32Value

    proc configureExampleTexture(id: GpuTextureId; options: GpuTextureOptions) =
      configured = id.uint32Value
      check options.minFilter == gtfNearest

    proc uploadExampleTexture(id: GpuTextureId; width, height: int; pixels: pointer) =
      check pixels != nil
      uploaded = (id.uint32Value, width, height)

    proc drawExampleTriangles(id: GpuTextureId; vertices: openArray[GpuVertex]) =
      check id.uint32Value == 42
      drawn = vertices.len

    proc enableExampleBlending() =
      blended = true

    proc flushExample() =
      flushed = true

    let relays = GpuRelays(
      createTextureProc: createExampleTexture,
      deleteTextureProc: deleteExampleTexture,
      configureTextureProc: configureExampleTexture,
      uploadRgba8TextureProc: uploadExampleTexture,
      drawTexturedTrianglesProc: drawExampleTriangles,
      enableAlphaBlendingProc: enableExampleBlending,
      flushProc: flushExample,
    )

    let id = relays.createTexture()
    relays.configureTexture(id, defaultTextureOptions(gtfNearest))
    var pixel = 0xffffffff'u32
    relays.uploadSolidRgba8Texture(id, pixel)
    relays.drawTexturedTriangles(id, [GpuVertex(x: 0, y: 0, u: 0, v: 0, r: 1, g: 1, b: 1, a: 1)])
    relays.enableAlphaBlending()
    relays.flush()
    relays.deleteTexture(id)

    check created
    check configured == 42
    check uploaded == (42'u32, 1, 1)
    check drawn == 1
    check blended
    check flushed
    check deleted == 42

  test "invalid texture ids do not call destructive operations":
    var calls = 0
    proc recordDelete(id: GpuTextureId) =
      inc calls

    proc recordConfigure(id: GpuTextureId; options: GpuTextureOptions) =
      inc calls

    proc recordUpload(id: GpuTextureId; width, height: int; pixels: pointer) =
      inc calls

    let relays = GpuRelays(
      deleteTextureProc: recordDelete,
      configureTextureProc: recordConfigure,
      uploadRgba8TextureProc: recordUpload,
    )
    relays.deleteTexture(textureId(0))
    relays.configureTexture(textureId(0), defaultTextureOptions())
    relays.uploadRgba8Texture(textureId(0), 1, 1, nil)
    check calls == 0
