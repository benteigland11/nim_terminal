## Custom validation rules for Nim Terminal project.
## Standards: Nimony / Nim 3 ready.

import std/[json, os, strutils]

const StdModules = [
  "strutils", "os", "json", "times", "options", "unicode", "streams",
  "tables", "sets", "asyncdispatch",
]

const RawMemoryPatterns = [
  "alloc(", "dealloc(", "cast[ptr", "ptr UncheckedArray",
]

const ProcSideEffectNames = [
  "activate", "add", "append", "apply", "clear", "close", "consume", "delete",
  "drain", "emit", "feed", "flush", "insert", "kill", "mark", "move", "open",
  "pop", "push", "read", "remove", "reset", "resize", "restore", "send",
  "set", "split", "start", "step", "stop", "update", "wait", "write",
]

proc lineRef(filename: string, lineNo: int): string =
  filename & " line " & $lineNo

proc procName(signature: string): string =
  var s = signature.strip()
  if not s.startsWith("proc "): return ""
  s = s[5 .. ^1].strip()
  let stopChars = {'*', '(', '[', ' ', ':'}
  for i, ch in s:
    if ch in stopChars:
      return s[0 ..< i]
  s

proc exportedProcLooksPure(signature: string): bool =
  let s = signature.strip()
  if not s.startsWith("proc ") or "*" notin s: return false
  for token in ["var ", "ptr ", "pointer", "File", "Stream", "Window", "Handle", "Callback"]:
    if token in s: return false
  let name = procName(s).toLowerAscii()
  for prefix in ProcSideEffectNames:
    if name.startsWith(prefix): return false
  true

proc validate(widgetPath: string): JsonNode =
  var blocks = newJArray()
  var warnings = newJArray()

  let srcDir = widgetPath / "src"
  let widgetJsonPath = widgetPath / "widget.json"

  var domain = "universal"
  if fileExists(widgetJsonPath):
    try:
      let meta = parseFile(widgetJsonPath)
      domain = meta["meta"]["domain"].getStr()
    except CatchableError:
      discard

  if dirExists(srcDir):
    for fpath in walkDirRec(srcDir):
      if not fpath.endsWith(".nim"): continue
      let content = readFile(fpath)
      let filename = extractFilename(fpath)
      let lines = content.splitLines()

      # 1. Block: Old-style imports (Must use std/ prefix)
      for i, line in lines:
        let trimmed = line.strip()
        if trimmed.startsWith("import "):
          # Simple check: if it contains any of the common stdlib modules
          # but NOT the "std/" prefix.
          for module in StdModules:
            if module in trimmed and "std/" notin trimmed:
              blocks.add(%*(lineRef(filename, i + 1) & ": use 'std/" & module & "' instead of legacy '" & module & "'"))

      # 2. Block: defer statement (Nimony discourages)
      for i, line in lines:
        let trimmed = line.strip()
        if trimmed == "defer:" or trimmed.startsWith("defer "):
          blocks.add(%*(lineRef(filename, i + 1) & ": 'defer' is discouraged in modern Nim; use try/finally or destructors"))

      # 3. Block: Naked echo (Library cleanliness)
      for i, line in lines:
        if line.strip().startsWith("echo "):
          blocks.add(%*(lineRef(filename, i + 1) & ": uses 'echo' - use structured logging or callbacks instead"))

      # 4. Block: Unsafe sequence casts fabricate owned memory.
      for i, line in lines:
        if "cast[seq[" in line:
          blocks.add(%*(lineRef(filename, i + 1) & ": unsafe cast to seq found; use openArray/toOpenArrayByte or explicit sequence construction"))

      # 5. Block: Bare exception swallowing hides parser/terminal failures.
      for i, line in lines:
        let trimmed = line.strip()
        if trimmed == "except:" or trimmed.startsWith("except:"):
          blocks.add(%*(lineRef(filename, i + 1) & ": bare except block found; catch a specific exception and handle or report it"))

      # 6. Warning: Raw memory / Unsafe. FFI may need this, but it should be visible.
      for i, line in lines:
        for banned in RawMemoryPatterns:
          if banned in line:
            warnings.add(%*(lineRef(filename, i + 1) & ": raw memory pattern found ('" & banned & "'). Prefer ref/seq/string unless this is FFI boundary code"))

      # 7. Warning: Top-level mutable widget state makes reuse and tests harder.
      for i, line in lines:
        let trimmed = line.strip()
        if line.len == trimmed.len and (trimmed == "var" or trimmed.startsWith("var ")):
          warnings.add(%*(lineRef(filename, i + 1) & ": potential top-level mutable state; prefer caller-owned state objects in widgets"))

      # 8. Warning: Prefer func over proc when an exported API looks pure.
      for i, line in lines:
        if exportedProcLooksPure(line):
          warnings.add(%*(lineRef(filename, i + 1) & ": exported proc looks pure; consider func unless it performs effects"))

      # 9. Warning: Dense case branches hide terminal state-machine side effects.
      for i, line in lines:
        let trimmed = line.strip()
        if trimmed.startsWith("of ") and (": (" in trimmed or (";" in trimmed and ":" in trimmed)):
          warnings.add(%*(lineRef(filename, i + 1) & ": multi-effect case branch on one line; prefer an indented block for reviewable diffs"))

      # 10. Performance: Table/Json in Renderers
      if "draw" in filename.toLowerAscii() or "render" in filename.toLowerAscii():
        if "Table[" in content or "JsonNode" in content:
          warnings.add(%*(filename & " appears to be rendering code but uses heavy types (Table/JsonNode)"))

  result = %*{"blocks": blocks, "warnings": warnings}

if paramCount() > 0:
  let report = validate(paramStr(1))
  echo $report
else:
  echo "{\"blocks\": [], \"warnings\": []}"
