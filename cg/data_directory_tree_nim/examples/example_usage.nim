## Example usage of Directory Tree.

import std/os
import directory_tree_lib

let root = getCurrentDir() / "src"
let tree = newDirectoryTree(root)
loadDirectoryTree(tree)
let rows = flattenDirectoryTree(tree)
assert rows.len > 0
let path = selectedDirectoryPath(tree)
assert path.len > 0
