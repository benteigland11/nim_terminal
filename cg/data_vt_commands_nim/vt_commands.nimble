# Package
version = "1.0.0"
author = "Cartograph"
description = "Typed VT command translator for CSI / ESC / OSC dispatches"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "run tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nimble c -r --path:src " & f
