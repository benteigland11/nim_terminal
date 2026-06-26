import std/[os, sequtils, unittest]
import widget_catalog_lib

const FixtureRoot = currentSourcePath().splitFile().dir / "fixtures" / "catalog_root"

suite "widget catalog":
  test "scanWidgetRoot reads manifests and stamps":
    let root = absolutePath(FixtureRoot)
    let catalog = scanWidgetRoot(root)
    check catalog.entries.len == 2
    check catalog.entries[0].name.len > 0
    let sample = catalog.entries.filterIt(it.id == "sample-alpha-nim")
    check sample.len == 1
    check sample[0].validated
    check sample[0].domain == "data"

  test "filterCatalog matches id and description":
    let root = absolutePath(FixtureRoot)
    let catalog = scanWidgetRoot(root)
    let hits = filterCatalog(catalog, "beta")
    check hits.len == 1
    check hits[0].id == "sample-beta-nim"
