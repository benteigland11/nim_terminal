## Base64 encode and decode using Nim's standard library.

import std/base64 as stdBase64
import std/options

func encode*(s: string): string =
  ## Return the base64 encoding of s.
  stdBase64.encode(s)

func decode*(s: string): string =
  ## Return the decoded string from a base64-encoded s.
  stdBase64.decode(s)

func tryDecode*(s: string): Option[string] =
  ## Return decoded base64 text, or none when the payload is malformed.
  try:
    some(stdBase64.decode(s))
  except ValueError:
    none(string)
