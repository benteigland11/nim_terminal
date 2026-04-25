import std/unittest
import ../src/color_palette_lib

suite "color palette":

  test "getXterm256Color basic ANSI":
    check getXterm256Color(1).r == 0xcd # Red
    check getXterm256Color(1).g == 0x00
    check getXterm256Color(1).b == 0x00

  test "getXterm256Color cube":
    # Index 16 should be (0,0,0) in the cube
    check getXterm256Color(16).r == 0
    # Index 231 should be (255,255,255)
    check getXterm256Color(231).r == 255

  test "findClosestXterm256":
    # Exactly red
    check findClosestXterm256(rgb(255, 0, 0)) == 9
    # Exactly black
    check findClosestXterm256(rgb(0, 0, 0)) == 0

  test "luminance and dark check":
    check rgb(0, 0, 0).isDark == true
    check rgb(255, 255, 255).isDark == false
