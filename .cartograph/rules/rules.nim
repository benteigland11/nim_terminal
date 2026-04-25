## Custom validation rules for Nim Terminal project.
## Standards: Nimony / Nim 3 ready.

import std/[json, os, strutils, re]

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
    except: discard

  if dirExists(srcDir):
    for fpath in walkDirRec(srcDir):
      if not fpath.endsWith(".nim"): continue
      let content = readFile(fpath)
      let filename = extractFilename(fpath)
      let lines = content.splitLines()

      # 1. Block: Old-style imports (Must use std/ prefix)
      for line in lines:
        let trimmed = line.strip()
        if trimmed.startsWith("import "):
          # Simple check: if it contains any of the common stdlib modules 
          # but NOT the "std/" prefix.
          for module in ["strutils", "os", "json", "times", "options", "unicode", "streams", "tables", "sets", "asyncdispatch"]:
            if module in trimmed and "std/" notin trimmed:
              blocks.add(%*(filename & ": use 'std/" & module & "' instead of legacy '" & module & "'"))

      # 2. Block: defer statement (Nimony discourages)
      if "defer:" in content or "defer " in content:
        blocks.add(%*(filename & ": 'defer' is discouraged in modern Nim; use try/finally or destructors"))

      # 3. Block: Naked echo (Library cleanliness)
      if "echo " in content:
        blocks.add(%*(filename & " uses 'echo' - use structured logging or callbacks instead"))

      # 4. Warning: Raw memory / Unsafe
      for banned in ["alloc(", "dealloc(", "cast[ptr"]:
        if banned in content:
          warnings.add(%*(filename & ": raw memory op found ('" & banned & "'). Consider using ref/seq/string"))

      # 5. Warning: Global mutable state
      for line in lines:
        if line.startsWith("var ") and not (" " in line.strip()): # Simple top-level check
          warnings.add(%*(filename & ": potential top-level mutable state ('" & line.strip() & "')"))

      # 6. Warning: Prefer func over proc
      for i, line in lines:
        let s = line.strip()
        if s.startsWith("proc ") and "*" in s:
          if "ptr " notin line and "handle" notin line:
            warnings.add(%*(filename & " line " & $(i+1) & ": exported 'proc' found, consider using 'func'"))

      # 7. Performance: Table/Json in Renderers
      if "draw" in filename.toLowerAscii() or "render" in filename.toLowerAscii():
        if "Table[" in content or "JsonNode" in content:
          warnings.add(%*(filename & " appears to be rendering code but uses heavy types (Table/JsonNode)"))

  result = %*{"blocks": blocks, "warnings": warnings}

if paramCount() > 0:
  let report = validate(paramStr(1))
  echo $report
else:
  echo "{\"blocks\": [], \"warnings\": []}"
