## Base64 encode and decode using Nim's standard library.

import std/base64 as stdBase64

proc encode*(s: string): string =
  ## Return the base64 encoding of s.
  stdBase64.encode(s)

proc decode*(s: string): string =
  ## Return the decoded string from a base64-encoded s.
  stdBase64.decode(s)
