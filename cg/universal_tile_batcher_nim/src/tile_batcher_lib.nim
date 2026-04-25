## OpenGL Tile Batcher.
##
## Efficiently draws many small quads (tiles) in a single pass.
## Designed for terminal grids, where each cell is a tile from an atlas.
##
## This widget uses OpenGL to render tiles.

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

func rgba*(r, g, b, a: float32): RgbaColor = RgbaColor(r: r, g: g, b: b, a: a)

var glActive: bool = true

proc newTileBatcher*(textureId: uint32, capacity: int = 10000): TileBatcher =
  TileBatcher(
    textureId: textureId,
    vboId: 0, # Defer creation
    vertices: newSeqOfCap[Vertex](capacity),
    capacity: capacity
  )

proc beginBatch*(b: TileBatcher) =
  if b.vboId == 0 and glActive:
    when not defined(glHeadless):
      try:
        glGenBuffers(1, addr b.vboId)
      except:
        glActive = false
    else:
      b.vboId = 1 # dummy for tests
  b.vertices.setLen(0)

proc addTile*(b: TileBatcher, x, y, w, h: float32, u1, v1, u2, v2: float32, color: RgbaColor) =
  if b.vertices.len + 6 > b.capacity: return
  
  let 
    r = color.r
    g = color.g
    b1 = color.b
    a = color.a
  
  b.vertices.add Vertex(x: x,     y: y,     u: u1, v: v1, r: r, g: g, b: b1, a: a)
  b.vertices.add Vertex(x: x + w, y: y,     u: u2, v: v1, r: r, g: g, b: b1, a: a)
  b.vertices.add Vertex(x: x + w, y: y - h, u: u2, v: v2, r: r, g: g, b: b1, a: a)
  
  b.vertices.add Vertex(x: x,     y: y,     u: u1, v: v1, r: r, g: g, b: b1, a: a)
  b.vertices.add Vertex(x: x + w, y: y - h, u: u2, v: v2, r: r, g: g, b: b1, a: a)
  b.vertices.add Vertex(x: x,     y: y - h, u: u1, v: v2, r: r, g: g, b: b1, a: a)

proc endBatch*(b: TileBatcher) =
  if b.vertices.len == 0 or not glActive: return
  
  when not defined(glHeadless):
    glBindTexture(GL_TEXTURE_2D, b.textureId)
    glBindBuffer(GL_ARRAY_BUFFER, b.vboId)
    
    # Upload to GPU in one go
    glBufferData(GL_ARRAY_BUFFER, GLsizeiptr(b.vertices.len * sizeof(Vertex)), addr b.vertices[0], GL_STREAM_DRAW)
    
    glEnableClientState(GL_VERTEX_ARRAY)
    glEnableClientState(GL_TEXTURE_COORD_ARRAY)
    glEnableClientState(GL_COLOR_ARRAY)
    
    let stride = GLsizei(sizeof(Vertex))
    
    # Pointers are now offsets into the VBO
    glVertexPointer(2.GLint, cGL_FLOAT, stride, nil)
    glTexCoordPointer(2.GLint, cGL_FLOAT, stride, cast[pointer](8))
    glColorPointer(4.GLint, cGL_FLOAT, stride, cast[pointer](16))
    
    glDrawArrays(GL_TRIANGLES, 0, cint(b.vertices.len))
    
    glDisableClientState(GL_VERTEX_ARRAY)
    glDisableClientState(GL_TEXTURE_COORD_ARRAY)
    glDisableClientState(GL_COLOR_ARRAY)
    glBindBuffer(GL_ARRAY_BUFFER, 0)
