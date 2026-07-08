## Hierarchical directory tree with lazy child loading and selection.

import std/[algorithm, os, strutils]

type
  DirNodeKind* = enum
    dnkDirectory
    dnkFile

  DirNode* = object
    name*: string
    relPath*: string
    kind*: DirNodeKind
    parent*: int
    children*: seq[int]
    expanded*: bool
    loaded*: bool

  DirectoryTree* = ref object
    rootPath*: string
    nodes*: seq[DirNode]
    selectedIndex*: int

  TreeFlatRow* = object
    depth*: int
    label*: string
    nodeIndex*: int
    isBranch*: bool
    expanded*: bool

const defaultIgnoredDirNames* = [
  "node_modules", ".git", "__pycache__", "dist", "build", "nimcache", ".cursor",
]

func shouldIgnoreEntry*(name: string; ignored: openArray[string]): bool =
  if name.len == 0 or name == "." or name == "..":
    true
  else:
    for needle in ignored:
      if name == needle:
        return true
    false

func newDirectoryTree*(rootPath: string): DirectoryTree =
  DirectoryTree(rootPath: rootPath, nodes: @[], selectedIndex: -1)

proc appendNode(tree: DirectoryTree; name, relPath: string; kind: DirNodeKind; parent: int): int =
  result = tree.nodes.len
  tree.nodes.add DirNode(
    name: name,
    relPath: relPath,
    kind: kind,
    parent: parent,
    expanded: false,
    loaded: kind == dnkFile,
  )

proc absPathFor(tree: DirectoryTree; nodeIndex: int): string =
  if nodeIndex < 0 or nodeIndex >= tree.nodes.len:
    ""
  else:
    tree.rootPath / tree.nodes[nodeIndex].relPath

func pathEntryName*(path: string): string =
  ## Full file or directory name including extension (splitFile().name drops ext).
  splitPath(path).tail

proc loadChildren(tree: DirectoryTree; nodeIndex: int; ignored: openArray[string]) =
  if nodeIndex < 0 or nodeIndex >= tree.nodes.len:
    return
  var node = tree.nodes[nodeIndex]
  if node.kind != dnkDirectory or node.loaded:
    return
  let base = absPathFor(tree, nodeIndex)
  if not dirExists(base):
    node.loaded = true
    tree.nodes[nodeIndex] = node
    return
  var dirs: seq[string] = @[]
  var files: seq[string] = @[]
  for kind, path in walkDir(base):
    let name = pathEntryName(path)
    if shouldIgnoreEntry(name, ignored):
      continue
    if kind == pcDir:
      dirs.add name
    elif kind == pcFile:
      files.add name
  dirs.sort()
  files.sort()
  for name in dirs:
    let childRel =
      if node.relPath.len == 0:
        name
      else:
        node.relPath / name
    node.children.add appendNode(tree, name, childRel, dnkDirectory, nodeIndex)
  for name in files:
    let childRel =
      if node.relPath.len == 0:
        name
      else:
        node.relPath / name
    node.children.add appendNode(tree, name, childRel, dnkFile, nodeIndex)
  node.loaded = true
  tree.nodes[nodeIndex] = node

proc loadDirectoryTree*(
  tree: DirectoryTree;
  ignored: openArray[string] = defaultIgnoredDirNames,
) =
  if tree == nil or tree.rootPath.len == 0 or not dirExists(tree.rootPath):
    return
  tree.nodes.setLen(0)
  tree.selectedIndex = -1
  let rootName = splitFile(tree.rootPath).name
  discard appendNode(tree, rootName, "", dnkDirectory, -1)
  tree.nodes[0].expanded = true
  loadChildren(tree, 0, ignored)
  if tree.nodes[0].children.len > 0:
    tree.selectedIndex = tree.nodes[0].children[0]

proc toggleDirectoryNode*(tree: DirectoryTree; nodeIndex: int; ignored: openArray[string] = defaultIgnoredDirNames) =
  if tree == nil or nodeIndex < 0 or nodeIndex >= tree.nodes.len:
    return
  if tree.nodes[nodeIndex].kind != dnkDirectory:
    return
  tree.nodes[nodeIndex].expanded = not tree.nodes[nodeIndex].expanded
  if tree.nodes[nodeIndex].expanded:
    loadChildren(tree, nodeIndex, ignored)

proc selectDirectoryNode*(tree: DirectoryTree; nodeIndex: int) =
  if tree == nil or nodeIndex < 0 or nodeIndex >= tree.nodes.len:
    return
  tree.selectedIndex = nodeIndex

func selectedDirectoryNode*(tree: DirectoryTree): DirNode =
  if tree == nil or tree.selectedIndex < 0 or tree.selectedIndex >= tree.nodes.len:
    DirNode()
  else:
    tree.nodes[tree.selectedIndex]

func selectedDirectoryPath*(tree: DirectoryTree): string =
  absPathFor(tree, if tree == nil: -1 else: tree.selectedIndex)

proc readBoundedTextFile*(path: string; maxBytes = 256_000): string =
  if path.len == 0 or not fileExists(path):
    return ""
  try:
    let data = readFile(path)
    if data.len <= maxBytes:
      data
    else:
      data[0 ..< maxBytes] & "\n…"
  except CatchableError:
    ""

proc flattenDirectoryTree*(tree: DirectoryTree): seq[TreeFlatRow] =
  if tree == nil or tree.nodes.len == 0:
    return @[]
  var rows: seq[TreeFlatRow] = @[]
  proc visit(nodeIndex, depth: int) =
    if nodeIndex < 0 or nodeIndex >= tree.nodes.len:
      return
    let node = tree.nodes[nodeIndex]
    if nodeIndex != 0:
      rows.add TreeFlatRow(
        depth: depth,
        label: node.name,
        nodeIndex: nodeIndex,
        isBranch: node.kind == dnkDirectory,
        expanded: node.expanded,
      )
    if node.kind == dnkDirectory and node.expanded:
      for child in node.children:
        visit(child, if nodeIndex == 0: 0 else: depth + 1)
  visit(0, 0)
  rows
