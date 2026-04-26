## Bounded diagnostics for terminal control-sequence traffic.
##
## Stores a caller-owned ring of recent protocol events. It is useful for
## debug panels and compatibility reports without making the parser or screen
## buffer retain unbounded history.

type
  VtEventKind* = enum
    vekUnknownCsi
    vekUnknownEsc
    vekUnknownOsc
    vekUnknownDcs
    vekModeSet
    vekModeReset
    vekModeQuery
    vekStateQuery
    vekReportSent

  VtDiagnosticEvent* = object
    kind*: VtEventKind
    name*: string
    detail*: string
    count*: int

  VtDiagnostics* = ref object
    capacity*: int
    nextCount: int
    events: seq[VtDiagnosticEvent]
    start: int

  VtDiagnosticsSnapshot* = object
    capacity*: int
    totalRecorded*: int
    retained*: int
    unknownCount*: int
    queryCount*: int
    events*: seq[VtDiagnosticEvent]

func newVtDiagnosticEvent*(kind: VtEventKind, name, detail: string, count: int): VtDiagnosticEvent =
  VtDiagnosticEvent(kind: kind, name: name, detail: detail, count: count)

func newVtDiagnostics*(capacity: int = 128): VtDiagnostics =
  VtDiagnostics(capacity: max(0, capacity), events: @[], start: 0, nextCount: 0)

func isUnknown*(kind: VtEventKind): bool =
  kind in {vekUnknownCsi, vekUnknownEsc, vekUnknownOsc, vekUnknownDcs}

func isQuery*(kind: VtEventKind): bool =
  kind in {vekModeQuery, vekStateQuery}

proc clear*(d: VtDiagnostics) =
  if d == nil: return
  d.events.setLen(0)
  d.start = 0
  d.nextCount = 0

proc record*(d: VtDiagnostics, kind: VtEventKind, name, detail: string) =
  ## Add an event, dropping the oldest retained event when capacity is full.
  if d == nil or d.capacity <= 0: return
  inc d.nextCount
  let event = newVtDiagnosticEvent(kind, name, detail, d.nextCount)
  if d.events.len < d.capacity:
    d.events.add event
  else:
    d.events[d.start] = event
    d.start = (d.start + 1) mod d.capacity

func len*(d: VtDiagnostics): int =
  if d == nil: 0 else: d.events.len

func retainedEvents*(d: VtDiagnostics): seq[VtDiagnosticEvent] =
  if d == nil or d.events.len == 0:
    return @[]
  result = newSeqOfCap[VtDiagnosticEvent](d.events.len)
  for i in 0 ..< d.events.len:
    result.add d.events[(d.start + i) mod d.events.len]

func snapshot*(d: VtDiagnostics): VtDiagnosticsSnapshot =
  if d == nil:
    return VtDiagnosticsSnapshot()
  let events = d.retainedEvents()
  result = VtDiagnosticsSnapshot(
    capacity: d.capacity,
    totalRecorded: d.nextCount,
    retained: events.len,
    unknownCount: 0,
    queryCount: 0,
    events: events,
  )
  for event in events:
    if event.kind.isUnknown:
      inc result.unknownCount
    if event.kind.isQuery:
      inc result.queryCount

func latest*(d: VtDiagnostics): VtDiagnosticEvent =
  if d == nil or d.events.len == 0:
    return VtDiagnosticEvent()
  d.retainedEvents()[^1]
