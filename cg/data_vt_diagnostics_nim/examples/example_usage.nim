## Example usage of VT Diagnostics.

import vt_diagnostics_lib

let diagnostics = newVtDiagnostics(capacity = 3)
diagnostics.record(vekUnknownCsi, "CSI", "final=x")
diagnostics.record(vekStateQuery, "DECRQSS", "m")

let snap = diagnostics.snapshot()
doAssert snap.retained == 2
doAssert snap.unknownCount == 1
doAssert snap.queryCount == 1
