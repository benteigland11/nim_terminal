import std/unittest
import source_lexer_lib

suite "source lexer":
  test "infers nim language from extension":
    check inferSourceLanguage("widget.nim") == "nim"
    check inferSourceLanguage("data.json") == "json"

  test "lexes nim keywords and strings":
    let tokens = lexSource("proc greet = discard", "nim")
    check tokens.len >= 2
    check tokens[0].kind == stkKeyword
    check tokens[0].start == 0

  test "lexes json literals":
    let tokens = lexSource("{\"ok\": true}", "json")
    check tokens.len >= 3
    check tokens[^1].kind in {stkOperator, stkPlain}
