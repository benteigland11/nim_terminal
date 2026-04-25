## Example usage of Color Parser.

import color_parser_lib
import std/options

let c1 = parseColor("#ff0000").get()
doAssert c1.r == 255

let c2 = parseColor("rgb:00/ff/00").get()
doAssert c2.g == 255

let c3 = parseColor("#abc").get()
doAssert c3.r == 0xaa # Shorthand expansion

echo "All color-parser examples passed."
