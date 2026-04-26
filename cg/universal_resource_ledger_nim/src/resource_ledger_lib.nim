## Generic resource lifetime ledger.
##
## Records create/update/delete events for resources that need leak-style
## accounting without coupling callers to a specific backend such as OpenGL.

import std/[algorithm, tables]

type
  LedgerAnomalyKind* = enum
    lakDuplicateCreate,
    lakMissingDelete,
    lakNegativeBytes

  ResourceRecord* = object
    kind*: string
    id*: string
    label*: string
    bytes*: int64

  ResourceStats* = object
    kind*: string
    liveCount*: int
    peakCount*: int
    liveBytes*: int64
    peakBytes*: int64
    creates*: int
    deletes*: int
    updates*: int

  LedgerAnomaly* = object
    kind*: LedgerAnomalyKind
    resourceKind*: string
    id*: string
    label*: string
    detail*: string

  ResourceSnapshot* = object
    live*: seq[ResourceRecord]
    stats*: seq[ResourceStats]
    anomalies*: seq[LedgerAnomaly]
    totalLiveBytes*: int64
    totalPeakBytes*: int64

  ResourceLedger* = object
    live: Table[string, ResourceRecord]
    stats: Table[string, ResourceStats]
    anomalies: seq[LedgerAnomaly]

func resourceKey(kind, id: string): string =
  kind & "\x1f" & id

func cleanBytes(bytes: int64): int64 =
  if bytes < 0: 0'i64 else: bytes

proc ensureStats(l: var ResourceLedger; kind: string): ptr ResourceStats =
  if kind notin l.stats:
    l.stats[kind] = ResourceStats(kind: kind)
  result = addr l.stats[kind]

proc noteAnomaly(l: var ResourceLedger; anomalyKind: LedgerAnomalyKind;
                 resourceKind, id, label, detail: string) =
  l.anomalies.add LedgerAnomaly(
    kind: anomalyKind,
    resourceKind: resourceKind,
    id: id,
    label: label,
    detail: detail,
  )

proc updatePeaks(stats: ptr ResourceStats) =
  if stats.liveCount > stats.peakCount:
    stats.peakCount = stats.liveCount
  if stats.liveBytes > stats.peakBytes:
    stats.peakBytes = stats.liveBytes

func newResourceLedger*(): ResourceLedger =
  ResourceLedger(
    live: initTable[string, ResourceRecord](),
    stats: initTable[string, ResourceStats](),
    anomalies: @[],
  )

func len*(l: ResourceLedger): int =
  l.live.len

func anomalyCount*(l: ResourceLedger): int =
  l.anomalies.len

func contains*(l: ResourceLedger; kind, id: string): bool =
  resourceKey(kind, id) in l.live

proc recordCreate*(l: var ResourceLedger; kind, id: string; bytes: int64 = 0;
                   label: string = "") =
  ## Record a new live resource. Duplicate creates are flagged and treated as
  ## an update so the ledger remains usable after the anomaly.
  let key = resourceKey(kind, id)
  let safeBytes = cleanBytes(bytes)
  if bytes < 0:
    l.noteAnomaly(lakNegativeBytes, kind, id, label, "create bytes were negative")
  let stats = l.ensureStats(kind)
  if key in l.live:
    l.noteAnomaly(lakDuplicateCreate, kind, id, label, "resource already live")
    let oldBytes = l.live[key].bytes
    l.live[key] = ResourceRecord(kind: kind, id: id, label: label, bytes: safeBytes)
    stats.liveBytes += safeBytes - oldBytes
    inc stats.updates
    updatePeaks(stats)
    return

  l.live[key] = ResourceRecord(kind: kind, id: id, label: label, bytes: safeBytes)
  inc stats.liveCount
  inc stats.creates
  stats.liveBytes += safeBytes
  updatePeaks(stats)

proc recordUpdate*(l: var ResourceLedger; kind, id: string; bytes: int64;
                   label: string = "") =
  ## Update a live resource's size/label. Missing resources are created so a
  ## late instrumentation hook can still converge to a truthful snapshot.
  let key = resourceKey(kind, id)
  let safeBytes = cleanBytes(bytes)
  if bytes < 0:
    l.noteAnomaly(lakNegativeBytes, kind, id, label, "update bytes were negative")
  if key notin l.live:
    l.recordCreate(kind, id, safeBytes, label)
    return

  let stats = l.ensureStats(kind)
  let oldBytes = l.live[key].bytes
  l.live[key] = ResourceRecord(kind: kind, id: id, label: label, bytes: safeBytes)
  stats.liveBytes += safeBytes - oldBytes
  inc stats.updates
  updatePeaks(stats)

proc recordUpsert*(l: var ResourceLedger; kind, id: string; bytes: int64 = 0;
                   label: string = "") =
  if l.contains(kind, id):
    l.recordUpdate(kind, id, bytes, label)
  else:
    l.recordCreate(kind, id, bytes, label)

proc recordDelete*(l: var ResourceLedger; kind, id: string) =
  let key = resourceKey(kind, id)
  let stats = l.ensureStats(kind)
  if key notin l.live:
    l.noteAnomaly(lakMissingDelete, kind, id, "", "delete for non-live resource")
    return

  let old = l.live[key]
  l.live.del(key)
  dec stats.liveCount
  inc stats.deletes
  stats.liveBytes -= old.bytes
  if stats.liveBytes < 0:
    stats.liveBytes = 0

func liveRecords*(l: ResourceLedger): seq[ResourceRecord] =
  for _, rec in l.live:
    result.add rec
  result.sort(proc(a, b: ResourceRecord): int =
    result = cmp(a.kind, b.kind)
    if result == 0:
      result = cmp(a.id, b.id)
  )

func statsRows*(l: ResourceLedger): seq[ResourceStats] =
  for _, row in l.stats:
    result.add row
  result.sort(proc(a, b: ResourceStats): int = cmp(a.kind, b.kind))

func anomalies*(l: ResourceLedger): seq[LedgerAnomaly] =
  l.anomalies

func snapshot*(l: ResourceLedger): ResourceSnapshot =
  result.live = l.liveRecords()
  result.stats = l.statsRows()
  result.anomalies = l.anomalies
  for row in result.stats:
    result.totalLiveBytes += row.liveBytes
    result.totalPeakBytes += row.peakBytes

func hasLeaks*(s: ResourceSnapshot): bool =
  s.live.len > 0 or s.anomalies.len > 0

func leakCount*(s: ResourceSnapshot): int =
  s.live.len
