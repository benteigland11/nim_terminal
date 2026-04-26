## Example usage of Resource Ledger.

import resource_ledger_lib

var ledger = newResourceLedger()
ledger.recordCreate("cache-entry", "users:active", 4096, "active users cache")
ledger.recordUpdate("cache-entry", "users:active", 6144, "active users cache")
ledger.recordDelete("cache-entry", "users:active")

let snap = ledger.snapshot()
doAssert snap.live.len == 0
doAssert snap.anomalies.len == 0
doAssert snap.stats[0].peakBytes == 6144
