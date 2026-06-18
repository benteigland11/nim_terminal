import std/unittest
import ../src/title_resolver_lib

suite "Title Resolver":

  test "Default policy (PreferTitle)":
    var s = newTitleState(tpPreferTitle)
    s.cwd = "project"
    check s.resolve() == "project"
    
    discard s.updateProgramName("vim")
    check s.resolve() == "vim"
    
    discard s.updateOscTitle("editing README")
    check s.resolve() == "editing README"

  test "PreferProgram policy":
    var s = newTitleState(tpPreferProgram)
    s.cwd = "/tmp"
    s.oscTitle = "my window"
    s.programName = "htop"
    check s.resolve() == "htop"

  test "CwdOnly policy":
    var s = newTitleState(tpCwdOnly)
    s.oscTitle = "ignore me"
    s.cwd = "/etc/nginx"
    check s.resolve() == "nginx"

  test "Update detection":
    var s = newTitleState()
    s.cwd = "/a"
    check s.updateOscTitle("title") == true
    check s.updateOscTitle("title") == false

  test "cleans decorative mojibake prefixes from titles":
    var s = newTitleState(tpPreferTitle)
    s.cwd = "/work/project"
    discard s.updateOscTitle("â   Claude Code")
    check s.resolve() == "Claude Code"

  test "cleans control and replacement characters from titles":
    check cleanTitle("\x1b bad \x00 title") == "bad title"
    check cleanTitle("\xef\xbf\xbd Claude") == "Claude"

  test "preserves path-like cwd labels and normal titles":
    check cleanTitle("~/project") == "~/project"
    check cleanTitle("Claude Code") == "Claude Code"
