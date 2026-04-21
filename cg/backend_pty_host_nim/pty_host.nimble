# Package
version = "1.0.0"
author = "Cartograph"
description = "Platform-neutral PTY host: PtyBackend concept + generic orchestrator"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "run tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nimble c -r --path:src " & f
