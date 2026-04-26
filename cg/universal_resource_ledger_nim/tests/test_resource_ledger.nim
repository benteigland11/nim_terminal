import std/unittest
import ../src/resource_ledger_lib

suite "Resource Ledger":
  test "create update delete returns to zero live resources":
    var ledger = newResourceLedger()
    ledger.recordCreate("texture", "7", 128, "atlas")
    ledger.recordUpdate("texture", "7", 256, "atlas grown")
    ledger.recordDelete("texture", "7")

    let snap = ledger.snapshot()
    check snap.live.len == 0
    check snap.totalLiveBytes == 0
    check snap.stats[0].creates == 1
    check snap.stats[0].updates == 1
    check snap.stats[0].deletes == 1
    check snap.stats[0].peakBytes == 256
    check snap.anomalies.len == 0

  test "duplicate create is recorded without corrupting live totals":
    var ledger = newResourceLedger()
    ledger.recordCreate("buffer", "3", 64)
    ledger.recordCreate("buffer", "3", 96)

    let snap = ledger.snapshot()
    check snap.live.len == 1
    check snap.totalLiveBytes == 96
    check snap.anomalies.len == 1
    check snap.anomalies[0].kind == lakDuplicateCreate

  test "missing delete is recorded as an anomaly":
    var ledger = newResourceLedger()
    ledger.recordDelete("texture", "missing")

    let snap = ledger.snapshot()
    check snap.live.len == 0
    check snap.stats[0].deletes == 0
    check snap.anomalies.len == 1
    check snap.anomalies[0].kind == lakMissingDelete

  test "upsert creates then updates the same resource":
    var ledger = newResourceLedger()
    ledger.recordUpsert("texture", "1", 4, "white pixel")
    ledger.recordUpsert("texture", "1", 8, "white pixel rewritten")

    let snap = ledger.snapshot()
    check snap.live.len == 1
    check snap.totalLiveBytes == 8
    check snap.stats[0].creates == 1
    check snap.stats[0].updates == 1

  test "negative sizes are clamped and surfaced":
    var ledger = newResourceLedger()
    ledger.recordCreate("texture", "bad", -4)

    let snap = ledger.snapshot()
    check snap.totalLiveBytes == 0
    check snap.anomalies.len == 1
    check snap.anomalies[0].kind == lakNegativeBytes
