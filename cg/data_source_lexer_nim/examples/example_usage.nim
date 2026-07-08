## Example usage of Source Lexer.

import source_lexer_lib

let source = "proc greet() =\n  discard"
let tokens = lexSource(source, "nim")
assert tokens.len > 0
assert tokens[0].kind == stkKeyword
assert inferSourceLanguage("sample.nim") == "nim"
