import std/unittest
import ../src/terminal_theme_lib

suite "terminal theme":

  test "default theme has expected colors":
    let t = defaultTheme()
    check t.background == rgb(0, 0, 0)
    check t.ansi[1] == rgb(205, 0, 0) # Red

  test "getColor with override":
    let t = defaultTheme()
    t.ansi[1] = rgb(255, 255, 255) # Change red to white
    check t.getColor(1) == rgb(255, 255, 255)
    
  test "getColor fallback to xterm":
    let t = defaultTheme()
    # index 16 is part of the cube, not overridden by ansi[16]
    check t.getColor(16) == rgb(0, 0, 0)
