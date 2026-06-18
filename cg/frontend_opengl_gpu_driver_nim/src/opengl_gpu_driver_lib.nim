## OpenGL GPU operation helpers.
##
## This widget intentionally does not depend on a relay contract widget. It
## exposes small standalone operations that an application can adapt into any
## relay surface after it has created and made current an OpenGL context.

import opengl

type
  TexturedVertex* = object
    x*, y*: float32
    u*, v*: float32
    r*, g*, b*, a*: float32

  OpenGlTriangleDriver* = ref object
    bufferId*: uint32

  TextureFilter* = enum
    tfNearest
    tfLinear

  TextureWrap* = enum
    twClampToEdge
    twRepeat

  TextureOptions* = object
    minFilter*: TextureFilter
    magFilter*: TextureFilter
    wrapS*: TextureWrap
    wrapT*: TextureWrap

func defaultTextureOptions*(filter: TextureFilter = tfLinear): TextureOptions =
  TextureOptions(
    minFilter: filter,
    magFilter: filter,
    wrapS: twClampToEdge,
    wrapT: twClampToEdge,
  )

func toGlFilter(value: TextureFilter): GLint =
  case value
  of tfNearest: GL_NEAREST.GLint
  of tfLinear: GL_LINEAR.GLint

func toGlWrap(value: TextureWrap): GLint =
  case value
  of twClampToEdge: GL_CLAMP_TO_EDGE.GLint
  of twRepeat: GL_REPEAT.GLint

proc createTexture*(): uint32 =
  var id: uint32
  glGenTextures(1, addr id)
  id

proc deleteTexture*(id: uint32) =
  if id == 0: return
  var local = id
  glDeleteTextures(1, addr local)

proc configureTexture*(id: uint32; options: TextureOptions) =
  if id == 0: return
  glBindTexture(GL_TEXTURE_2D, id)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, options.minFilter.toGlFilter)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, options.magFilter.toGlFilter)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, options.wrapS.toGlWrap)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, options.wrapT.toGlWrap)

proc uploadRgba8Texture*(id: uint32; width, height: int; pixels: pointer) =
  if id == 0 or width <= 0 or height <= 0 or pixels == nil: return
  glBindTexture(GL_TEXTURE_2D, id)
  glTexImage2D(
    GL_TEXTURE_2D,
    0,
    GL_RGBA8.cint,
    cint(width),
    cint(height),
    0,
    GL_RGBA,
    GL_UNSIGNED_BYTE,
    pixels,
  )

proc newOpenGlTriangleDriver*(): OpenGlTriangleDriver =
  OpenGlTriangleDriver(bufferId: 0)

proc gpuBufferId*(driver: OpenGlTriangleDriver): uint32 =
  if driver == nil: 0'u32 else: driver.bufferId

proc drawTexturedTriangles*(driver: OpenGlTriangleDriver; textureId: uint32; vertices: openArray[TexturedVertex]) =
  if driver == nil or textureId == 0 or vertices.len == 0: return
  if driver.bufferId == 0:
    glGenBuffers(1, addr driver.bufferId)

  glBindTexture(GL_TEXTURE_2D, textureId)
  glEnableClientState(GL_VERTEX_ARRAY)
  glEnableClientState(GL_TEXTURE_COORD_ARRAY)
  glEnableClientState(GL_COLOR_ARRAY)

  let stride = GLsizei(sizeof(TexturedVertex))
  glBindBuffer(GL_ARRAY_BUFFER, driver.bufferId)
  glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(vertices.len * sizeof(TexturedVertex)), unsafeAddr vertices[0], GL_STREAM_DRAW)
  glVertexPointer(2.GLint, cGL_FLOAT, stride, nil)
  glTexCoordPointer(2.GLint, cGL_FLOAT, stride, cast[pointer](8))
  glColorPointer(4.GLint, cGL_FLOAT, stride, cast[pointer](16))
  glDrawArrays(GL_TRIANGLES, 0, cint(vertices.len))

  glDisableClientState(GL_VERTEX_ARRAY)
  glDisableClientState(GL_TEXTURE_COORD_ARRAY)
  glDisableClientState(GL_COLOR_ARRAY)
  glBindBuffer(GL_ARRAY_BUFFER, 0)

proc dispose*(driver: OpenGlTriangleDriver) =
  if driver == nil or driver.bufferId == 0: return
  var local = driver.bufferId
  glDeleteBuffers(1, addr local)
  driver.bufferId = 0

proc enableAlphaTexturing*() =
  glEnable(GL_TEXTURE_2D)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

proc flush*() =
  glFlush()
