import std/unittest
import std/[options, os]
import path_candidates_lib

suite "Path Candidates":
  test "resolveCandidatePath trims and anchors relative paths":
    let base = getTempDir() / "path-candidates-test"
    check resolveCandidatePath(" item.txt ", base) == base / "item.txt"
    check resolveCandidatePath("", base) == ""

  test "firstExistingPath returns the first available file":
    let base = getTempDir() / "path-candidates-test-first"
    createDir(base)
    let selected = base / "selected.txt"
    writeFile(selected, "ok")

    let found = firstExistingPath(["missing.txt", "selected.txt"], base)
    check found.isSome
    check found.get() == selected

  test "existingPaths returns every available file":
    let base = getTempDir() / "path-candidates-test-all"
    createDir(base)
    writeFile(base / "first.txt", "1")
    writeFile(base / "second.txt", "2")

    let found = existingPaths(["first.txt", "missing.txt", "second.txt"], base)
    check found == @[base / "first.txt", base / "second.txt"]
