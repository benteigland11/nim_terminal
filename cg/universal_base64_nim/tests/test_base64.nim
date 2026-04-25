import std/unittest
import base64_codec

suite "encode":
  test "empty string":
    check encode("") == ""

  test "hello":
    check encode("hello") == "aGVsbG8="

  test "binary-safe padding":
    check encode("Man") == "TWFu"
    check encode("Ma") == "TWE="
    check encode("M") == "TQ=="

suite "decode":
  test "empty string":
    check decode("") == ""

  test "hello":
    check decode("aGVsbG8=") == "hello"

  test "roundtrip":
    let inputs = ["hello world", "Nim is fun!", "1234567890"]
    for s in inputs:
      check decode(encode(s)) == s
