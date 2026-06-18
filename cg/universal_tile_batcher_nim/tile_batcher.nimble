# Package

version       = "1.0.0"
author        = "Cartograph"
description   = "Efficiently batches many small quads into textured triangle vertices."
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"

task test, "Run tests":
  exec "nim c -r tests/test_tile_batcher.nim"
