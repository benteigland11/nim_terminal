import std/unittest
import vt_diagnostics_lib

suite "vt diagnostics":
  test "records bounded events in insertion order":
    let d = newVtDiagnostics(2)
    d.record(vekUnknownCsi, "CSI", "x")
    d.record(vekModeQuery, "DECRQM", "?2026")
    d.record(vekReportSent, "DSR", "cursor")

    let events = d.retainedEvents()
    check events.len == 2
    check events[0].kind == vekModeQuery
    check events[1].kind == vekReportSent
    check events[1].count == 3

  test "snapshot summarizes retained event types":
    let d = newVtDiagnostics(4)
    d.record(vekUnknownOsc, "OSC", "999")
    d.record(vekUnknownDcs, "DCS", "x")
    d.record(vekModeQuery, "DECRQM", "?25")
    d.record(vekStateQuery, "DECRQSS", "m")

    let snap = d.snapshot()
    check snap.capacity == 4
    check snap.totalRecorded == 4
    check snap.retained == 4
    check snap.unknownCount == 2
    check snap.queryCount == 2

  test "clear resets retained state":
    let d = newVtDiagnostics(4)
    d.record(vekUnknownEsc, "ESC", "(")
    check d.len == 1
    d.clear()
    check d.len == 0
    check d.snapshot().totalRecorded == 0

  test "zero capacity records nothing":
    let d = newVtDiagnostics(0)
    d.record(vekUnknownCsi, "CSI", "x")
    check d.len == 0
    check d.snapshot().retained == 0
