import std/[unittest, json, strutils]

# Extract the exact formatting logic from nim_terminal.nim to verify correctness
proc formatSearchResults(output: string; activeSearchQuery: string): string =
  var title = "Registry Search Results"
  var body = ""

  try:
    let jsonNode = parseJson(output)
    let localNode = jsonNode{"local"}
    let registryNode = jsonNode{"registry"}

    var results: seq[string] = @[]

    proc formatWidgets(node: JsonNode; header: string) =
      if node != nil:
        let count = if node{"count"} != nil and node{"count"}.kind == JInt: node{"count"}.num.int else: 0
        let widgets = node{"widgets"}
        if widgets != nil and widgets.kind == JArray and widgets.len > 0:
          if results.len > 0:
            results.add ""
          results.add "=== " & header & " (" & $count & ") ==="
          for widget in widgets:
            let id = if widget{"id"} != nil and widget{"id"}.kind == JString: widget{"id"}.str else: ""
            let desc = if widget{"description"} != nil and widget{"description"}.kind == JString: widget{"description"}.str else: ""
            let lang = if widget{"language"} != nil and widget{"language"}.kind == JString: widget{"language"}.str else: ""
            if id.len > 0:
              results.add "* " & id & " [" & lang & "]"
              if desc.len > 0:
                let shortDesc = if desc.len > 120: desc[0..117] & "..." else: desc
                results.add "  " & shortDesc.strip().replace("\n", " ")

    formatWidgets(localNode, "Installed Widgets")
    formatWidgets(registryNode, "Registry Widgets")

    if results.len == 0:
      body = "No widgets found matching '" & activeSearchQuery & "'."
    else:
      body = results.join("\n")
  except CatchableError as e:
    body = "Search Output for '" & activeSearchQuery & "':\n\n" & output.strip()
  body

suite "search results formatting":
  test "empty search results":
    let input = """{"local": {"count": 0, "widgets": []}, "registry": {"count": 0, "widgets": []}}"""
    let res = formatSearchResults(input, "foo")
    check res == "No widgets found matching 'foo'."

  test "successful search results formatting":
    let input = """{
      "local": {
        "count": 1,
        "widgets": [
          {"id": "universal-slug-nim", "name": "Slug", "description": "Convert a string to slug", "language": "nim"}
        ]
      },
      "registry": {
        "count": 1,
        "widgets": [
          {"id": "@benteigland11/cg-universal-base64-nim", "description": "Base64 encoding", "language": "nim"}
        ]
      }
    }"""
    let res = formatSearchResults(input, "test")
    let lines = res.splitLines()
    check lines[0] == "=== Installed Widgets (1) ==="
    check lines[1] == "* universal-slug-nim [nim]"
    check lines[2] == "  Convert a string to slug"
    check lines[4] == "=== Registry Widgets (1) ==="
    check lines[5] == "* @benteigland11/cg-universal-base64-nim [nim]"
    check lines[6] == "  Base64 encoding"

  test "fallback to raw output on invalid json":
    let input = "invalid json error output"
    let res = formatSearchResults(input, "bar")
    check res.startsWith("Search Output for 'bar':")
    check "invalid json error output" in res
