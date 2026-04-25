import std/[unittest, options]
import ../src/color_parser_lib

suite "color parser":

  test "parse #RGB shorthand":
    let c = parseColor("#f00").get()
    check c.r == 0xff
    check c.g == 0x00
    check c.b == 0x00

  test "parse #RRGGBB":
    let c = parseColor("#00ff00").get()
    check c.r == 0x00
    check c.g == 0xff
    check c.b == 0x00

  test "parse rgb:RR/GG/BB":
    let c = parseColor("rgb:00/00/ff").get()
    check c.r == 0x00
    check c.g == 0x00
    check c.b == 0xff

  test "parse rgb:RRRR/GGGG/BBBB":
    let c = parseColor("rgb:ffff/0000/1234").get()
    check c.r == 0xff
    check c.g == 0x00
    check c.b == 0x12

  test "invalid formats":
    check parseColor("not-a-color").isNone
    check parseColor("#12").isNone
    check parseColor("rgb:1/2").isNone
