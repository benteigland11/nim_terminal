# Package

version       = "1.0.0"
author        = "Cartograph"
description   = "Efficiently draws many small quads (tiles) using OpenGL in a single pass."
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"
requires "opengl >= 1.2.0"

task test, "Run tests":
  exec "nim c -r -d:glHeadless tests/test_tile_batcher.nim"
