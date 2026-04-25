# Package

version       = "0.1.0"
author        = "benteigland11"
description   = "A high-performance terminal emulator base written in Nim."
license       = "MIT"
srcDir        = "src"
bin           = @["nim_terminal"]


# Dependencies

requires "nim >= 2.0.0"
requires "pixie >= 5.0.0"
requires "staticglfw >= 4.0.0"
requires "opengl >= 1.2.0"
