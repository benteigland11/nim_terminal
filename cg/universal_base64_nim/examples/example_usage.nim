## Example usage of base64_codec.

import base64_codec

let samples = ["hello", "Nim widgets!", "binary\x00data"]
for s in samples:
  let encoded = encode(s)
  let decoded = decode(encoded)
  assert decoded == s
