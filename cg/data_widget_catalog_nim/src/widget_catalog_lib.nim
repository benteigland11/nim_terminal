## Scan a directory tree for module manifests and validation stamps.
##
## Reads per-module widget.json metadata and optional .validation_stamp.json
## from immediate child directories. Intended for tooling UIs that list
## locally installed reusable modules.

import std/[algorithm, json, os, strutils]

type
  CatalogValidationStamp* = object
    validatedAt*: string
    language*: string
    runtime*: string

  CatalogEntry* = object
    dirName*: string
    id*: string
    name*: string
    domain*: string
    version*: string
    language*: string
    description*: string
    validated*: bool
    stamp*: CatalogValidationStamp

  WidgetCatalog* = object
    root*: string
    entries*: seq[CatalogEntry]

const ManifestFileName* = "widget.json"
const StampFileName* = ".validation_stamp.json"

func slugToId*(slug: string): string =
  ## Convert a directory slug like foo_bar_nim into foo-bar-nim.
  slug.replace('_', '-')

proc readStamp(path: string): CatalogValidationStamp =
  result = CatalogValidationStamp()
  if not fileExists(path):
    return
  try:
    let node = parseJson(readFile(path))
    if node.hasKey("validated_at"):
      result.validatedAt = node["validated_at"].getStr("")
    if node.hasKey("language"):
      result.language = node["language"].getStr("")
    if node.hasKey("runtime"):
      result.runtime = node["runtime"].getStr("")
  except CatchableError:
    discard

proc readManifest(moduleDir: string): CatalogEntry =
  result = CatalogEntry(dirName: splitFile(moduleDir).name)
  let manifestPath = moduleDir / ManifestFileName
  if not fileExists(manifestPath):
    return
  try:
    let node = parseJson(readFile(manifestPath))
    if node.hasKey("meta"):
      let meta = node["meta"]
      if meta.hasKey("id"):
        result.id = meta["id"].getStr("")
      if meta.hasKey("name"):
        result.name = meta["name"].getStr("")
      if meta.hasKey("domain"):
        result.domain = meta["domain"].getStr("")
      if meta.hasKey("version"):
        result.version = meta["version"].getStr("")
    if node.hasKey("description"):
      result.description = node["description"].getStr("")
    if node.hasKey("tech_stack") and node["tech_stack"].hasKey("language"):
      result.language = node["tech_stack"]["language"].getStr("")
    if result.id.len == 0:
      result.id = slugToId(result.dirName)
  except CatchableError:
    discard

proc scanWidgetRoot*(root: string): WidgetCatalog =
  result = WidgetCatalog(root: root, entries: @[])
  if not dirExists(root):
    return
  for kind, entry in walkDir(root):
    if kind != pcDir:
      continue
    let moduleDir =
      if isAbsolute(entry): entry
      else: root / entry
    if not fileExists(moduleDir / ManifestFileName):
      continue
    var item = readManifest(moduleDir)
    let stampPath = moduleDir / StampFileName
    if fileExists(stampPath):
      item.stamp = readStamp(stampPath)
      item.validated = item.stamp.validatedAt.len > 0
    result.entries.add item
  result.entries.sort proc (a, b: CatalogEntry): int = cmp(a.name, b.name)

func filterCatalog*(catalog: WidgetCatalog; query: string): seq[CatalogEntry] =
  let needle = query.strip().toLowerAscii()
  if needle.len == 0:
    return catalog.entries
  for entry in catalog.entries:
    if needle in entry.id.toLowerAscii() or
        needle in entry.name.toLowerAscii() or
        needle in entry.domain.toLowerAscii() or
        needle in entry.description.toLowerAscii():
      result.add entry
