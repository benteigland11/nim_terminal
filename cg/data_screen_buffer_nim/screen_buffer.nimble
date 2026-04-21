# Package
version = "1.0.0"
author = "Cartograph"
description = "Terminal screen buffer: grid, cursor, SGR, scroll region, alt buffer, scrollback"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "run tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nimble c -r --path:src " & f
