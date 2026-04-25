import std/unittest
import ../src/link_detector_lib

suite "link detector":
  test "finds simple http and https links":
    let s = "Check out https://github.com and http://example.com"
    let links = detectLinks(s)
    check links.len == 2
    check links[0].text == "https://github.com"
    check links[1].text == "http://example.com"

  test "ignores terminal punctuation":
    let s = "Visit (https://rust-lang.org) and [https://nim-lang.org]."
    let links = detectLinks(s)
    check links.len == 2
    check links[0].text == "https://rust-lang.org"
    check links[1].text == "https://nim-lang.org"

  test "handles multiple links consecutively":
    let s = "https://one.com https://two.com"
    let links = detectLinks(s)
    check links.len == 2
    check links[0].text == "https://one.com"
    check links[1].text == "https://two.com"
