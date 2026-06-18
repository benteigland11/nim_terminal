# Package
version = "0.1.0"
author = "Widget Author"
description = "OpenGL GPU Driver"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "opengl >= 1.2.9"

# Tasks
task test, "run tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nimble c -r --path:src " & f
