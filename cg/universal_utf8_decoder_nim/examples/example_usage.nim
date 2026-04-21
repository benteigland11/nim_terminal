## Stream a mix of ASCII, accented Latin, CJK, and emoji bytes into the
## decoder and tally the decoded runes by display width.

import utf8_decoder_lib

# "Hi é 中 🚀" as raw UTF-8 bytes, with a deliberate split to show that
# the decoder resumes correctly across feed boundaries.
let part1: seq[byte] = @[
  byte('H'), byte('i'), byte(' '),
  0xC3'u8, 0xA9'u8,                         # é (U+00E9)
  byte(' '),
  0xE4'u8, 0xB8'u8, 0xAD'u8,                # 中 (U+4E2D)
  byte(' '),
  0xF0'u8, 0x9F'u8,                         # first two bytes of 🚀 ...
]
let part2: seq[byte] = @[
  0x9A'u8, 0x80'u8,                         # ... last two bytes of 🚀 (U+1F680)
]

var narrow = 0
var wide = 0
var zeroWidth = 0
var runes: seq[uint32]

let emit: Utf8Emit = proc (rune: uint32, width: int) =
  runes.add rune
  case width
  of 0: inc zeroWidth
  of 1: inc narrow
  of 2: inc wide
  else: discard

var decoder = newUtf8Decoder()
decoder.feed(part1, emit)
doAssert decoder.pending                     # 🚀 is mid-sequence here
decoder.feed(part2, emit)
doAssert not decoder.pending

doAssert runes[0] == uint32('H')
doAssert runes[3] == 0x00E9'u32
doAssert runes[5] == 0x4E2D'u32
doAssert runes[7] == 0x1F680'u32
doAssert wide == 2
doAssert narrow >= 5
doAssert zeroWidth == 0
