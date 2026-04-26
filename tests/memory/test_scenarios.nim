## Validates the Tier 2 scenario cfg/script files and the temp-dir
## machinery without spawning the terminal.

import std/[unittest, os, osproc, parsecfg, strutils, times]
import ./rss_sampler

const ExpectedScenarios = ["urandom_flood", "scroll_churn", "sgr_storm",
                           "alt_buffer_toggle", "utf8_mix"]

proc scenariosDir(): string =
  projectRoot() / "tests" / "memory" / "scenarios"

suite "scenarios:files":

  test "every scenario has both a .cfg and a .sh":
    for name in ExpectedScenarios:
      check fileExists(scenariosDir() / (name & ".cfg"))
      check fileExists(scenariosDir() / (name & ".sh"))

  test "every cfg parses cleanly and points at its sibling script":
    # Regression guard: previous cfgs inlined `bash -c \"...\"` which
    # std/parsecfg silently truncated at the first quote, making Tier 2
    # a no-op masquerading as a real soak.
    for name in ExpectedScenarios:
      let p = scenariosDir() / (name & ".cfg")
      let dict = loadConfig(p)
      let prog = dict.getSectionValue("shell", "program").strip()
      check prog == "./" & name & ".sh"
      let title = dict.getSectionValue("app", "title").strip()
      check title.len > 0
      check (not title.contains(":"))   # colons break parsecfg
      let sb = dict.getSectionValue("terminal", "scrollback").strip()
      check sb.len > 0
      let n = parseInt(sb)
      check n > 0 and n <= 100_000
      echo "[scenario:", name, "] program=", prog, " scrollback=", n

suite "scenarios:scripts":

  test "every scenario script has a bash shebang and is executable in source":
    for name in ExpectedScenarios:
      let path = scenariosDir() / (name & ".sh")
      let firstLine = readFile(path).split('\n')[0]
      check firstLine.startsWith("#!") and firstLine.contains("bash")
      let perms = getFilePermissions(path)
      check fpUserExec in perms

  test "utf8_mix.sh contains the raw-byte combining-acute escape":
    # Regression guard: ́ in printf is treated literally by bash.
    # The script must use \xcc\x81 (UTF-8 bytes for U+0301).
    let body = readFile(scenariosDir() / "utf8_mix.sh")
    check body.contains("\\xcc\\x81")
    check (not body.contains("\\u0301"))

suite "scenarios:tempdir":

  test "the copy-to-tempdir flow stages cfg + script + resources":
    # Mirrors copyScenarioCfg from test_soak.nim (which is private).
    let scenario = "scroll_churn"
    let scenarioPath = scenariosDir() / (scenario & ".cfg")
    let scriptPath = scenariosDir() / (scenario & ".sh")
    let tmp = getTempDir() / ("nim_terminal_soak_test_" & scenario & "_" & $epochTime().int)
    createDir(tmp)
    let resSrc = projectRoot() / "resources"
    if dirExists(resSrc):
      createSymlink(resSrc, tmp / "resources")
    copyFile(scenarioPath, tmp / "nim_terminal.cfg")
    copyFile(scriptPath, tmp / (scenario & ".sh"))
    setFilePermissions(tmp / (scenario & ".sh"),
      {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})

    check fileExists(tmp / "nim_terminal.cfg")
    check fileExists(tmp / (scenario & ".sh"))
    check fpUserExec in getFilePermissions(tmp / (scenario & ".sh"))
    check (not dirExists(resSrc)) or symlinkExists(tmp / "resources")

    let dict = loadConfig(tmp / "nim_terminal.cfg")
    check dict.getSectionValue("shell", "program") == "./" & scenario & ".sh"

    removeDir(tmp)
    check (not dirExists(tmp))

suite "scenarios:execution":

  test "every scenario script actually emits output when run":
    # End-to-end on the scripts themselves (not the terminal). Catches
    # bash syntax errors, missing tools, and silent no-ops without paying
    # for a full soak.
    for name in ExpectedScenarios:
      let path = scenariosDir() / (name & ".sh")
      # Cap output at 1KB so the loop scenarios terminate fast.
      let cmd = "timeout 1 bash " & path.quoteShell & " 2>&1 | head -c 1024"
      let output = execProcess(cmd)
      echo "[exec:", name, "] produced ", output.len, " bytes"
      check output.len > 0
