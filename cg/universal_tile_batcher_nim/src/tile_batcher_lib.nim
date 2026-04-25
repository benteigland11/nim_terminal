## OpenGL Tile Batcher.
##
## Efficiently draws many small quads (tiles) using Vertex Arrays.
## Optimized for high-performance terminal grid rendering.

import opengl

type
  RgbaColor* = object
    r*, g*, b*, a*: float32

  Vertex = object
    x, y: float32
    u, v: float32
    r, g, b, a: float32

  TileBatcher* = ref object
    textureId*: uint32
    vboId: uint32
    vertices: seq[Vertex]
    capacity: int
    count: int

func rgba*(r, g, b, a: float32): RgbaColor = RgbaColor(r: r, g: g, b: b, a: a)

var glActive: bool = true

proc newTileBatcher*(textureId: uint32, capacity: int = 50000): TileBatcher =
  TileBatcher(
    textureId: textureId,
    vboId: 0,
    vertices: newSeq[Vertex](capacity),
    capacity: capacity,
    count: 0
  )

proc beginBatch*(b: TileBatcher) =
  if b.vboId == 0 and glActive:
    when not defined(glHeadless):
      try:
        glGenBuffers(1, addr b.vboId)
      except: glActive = false
    else: b.vboId = 1
  b.count = 0

proc addTile*(b: TileBatcher, x, y, w, h: float32, u1, v1, u2, v2: float32, color: RgbaColor) =
  if b.count + 6 > b.capacity: return
  
  let r = color.r; let g = color.g; let b1 = color.b; let a = color.a
  let v = cast[ptr array[6, Vertex]](addr b.vertices[b.count])
  
  v[0] = Vertex(x: x,     y: y,     u: u1, v: v1, r: r, g: g, b: b1, a: a)
  v[1] = Vertex(x: x + w, y: y,     u: u2, v: v1, r: r, g: g, b: b1, a: a)
  v[2] = Vertex(x: x + w, y: y - h, u: u2, v: v2, r: r, g: g, b: b1, a: a)
  v[3] = Vertex(x: x,     y: y,     u: u1, v: v1, r: r, g: g, b: b1, a: a)
  v[4] = Vertex(x: x + w, y: y - h, u: u2, v: v2, r: r, g: g, b: b1, a: a)
  v[5] = Vertex(x: x,     y: y - h, u: u1, v: v2, r: r, g: g, b: b1, a: a)
  b.count += 6

proc endBatch*(b: TileBatcher) =
  if b.count == 0 or not glActive: return
  
  when not defined(glHeadless):
    glBindTexture(GL_TEXTURE_2D, b.textureId)
    
    glEnableClientState(GL_VERTEX_ARRAY)
    glEnableClientState(GL_TEXTURE_COORD_ARRAY)
    glEnableClientState(GL_COLOR_ARRAY)
    
    let stride = GLsizei(sizeof(Vertex))
    
    if b.vboId != 0:
      glBindBuffer(GL_ARRAY_BUFFER, b.vboId)
      glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(b.count * sizeof(Vertex)), addr b.vertices[0], GL_STREAM_DRAW)
      glVertexPointer(2.GLint, cGL_FLOAT, stride, nil)
      glTexCoordPointer(2.GLint, cGL_FLOAT, stride, cast[pointer](8))
      glColorPointer(4.GLint, cGL_FLOAT, stride, cast[pointer](16))
    else:
      let base = addr b.vertices[0]
      glVertexPointer(2.GLint, cGL_FLOAT, stride, base)
      glTexCoordPointer(2.GLint, cGL_FLOAT, stride, cast[pointer](cast[int](base) + 8))
      glColorPointer(4.GLint, cGL_FLOAT, stride, cast[pointer](cast[int](base) + 16))
    
    glDrawArrays(GL_TRIANGLES, 0, cint(b.count))
    
    glDisableClientState(GL_VERTEX_ARRAY)
    glDisableClientState(GL_TEXTURE_COORD_ARRAY)
    glDisableClientState(GL_COLOR_ARRAY)
    if b.vboId != 0: glBindBuffer(GL_ARRAY_BUFFER, 0)
