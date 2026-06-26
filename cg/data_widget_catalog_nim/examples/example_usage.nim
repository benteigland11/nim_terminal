## Example usage of Widget Catalog.

import std/os
import widget_catalog_lib

const FixtureRoot = currentSourcePath().splitFile().dir / ".." / "tests" / "fixtures" / "catalog_root"

let catalog = scanWidgetRoot(absolutePath(FixtureRoot))
doAssert catalog.entries.len == 2
doAssert filterCatalog(catalog, "alpha").len == 1
