import std/[os, unittest]
import directory_tree_lib

suite "directory tree":
  test "loads and flattens widget source tree":
    let root = getCurrentDir() / "src"
    let tree = newDirectoryTree(root)
    loadDirectoryTree(tree)
    let rows = flattenDirectoryTree(tree)
    check rows.len > 0
    check rows[0].label == "directory_tree_lib.nim" or rows[0].isBranch

  test "preserves file extensions in labels and paths":
    let root = getCurrentDir() / "src"
    let tree = newDirectoryTree(root)
    loadDirectoryTree(tree)
    var found = false
    for row in flattenDirectoryTree(tree):
      if row.label == "directory_tree_lib.nim":
        selectDirectoryNode(tree, row.nodeIndex)
        check fileExists(selectedDirectoryPath(tree))
        check readBoundedTextFile(selectedDirectoryPath(tree)).len > 0
        found = true
        break
    check found
