#!/usr/bin/env bash
# Mix of ASCII, CJK, emoji, combining marks — exercises utf8_decoder + glyph_atlas.
while :; do
  printf 'hello 世界 🌍 café e\xcc\x81 한국 🎉\n'
done
