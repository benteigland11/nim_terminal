## Transient toast / status message queue.
##
## Pure logic — no timers, no rendering. The host passes the current time into
## every call (usually monotonic seconds), so the queue is fully deterministic
## and testable. Toasts expire after a per-message time-to-live and fade out
## over a configurable window; the host renders `visibleToasts` and asks
## `toastAlpha` for the opacity of each.

type
  Toast* = object
    id*: int
    text*: string
    createdAt*: float
    ttl*: float          ## Seconds the toast stays fully live before fading.
    fade*: float         ## Seconds of fade-out after the ttl elapses.

  ToastQueue* = object
    items*: seq[Toast]
    nextId*: int
    maxVisible*: int     ## Cap on simultaneously shown toasts (newest win).

const
  DefaultToastTtl* = 2.5
  DefaultToastFade* = 0.4
  DefaultMaxVisible* = 3

func newToastQueue*(maxVisible = DefaultMaxVisible): ToastQueue =
  ToastQueue(items: @[], nextId: 1, maxVisible: max(1, maxVisible))

func toastExpiry(t: Toast): float =
  t.createdAt + t.ttl + t.fade

func expired*(t: Toast; now: float): bool =
  now >= toastExpiry(t)

proc prune*(queue: var ToastQueue; now: float) =
  ## Drop toasts whose ttl + fade window has fully elapsed.
  var kept: seq[Toast] = @[]
  for t in queue.items:
    if not expired(t, now):
      kept.add t
  queue.items = kept

proc push*(
    queue: var ToastQueue; text: string; now: float;
    ttl = DefaultToastTtl; fade = DefaultToastFade): int {.discardable.} =
  ## Enqueue a message, returning its id. Prunes expired entries first.
  prune(queue, now)
  result = queue.nextId
  inc queue.nextId
  queue.items.add Toast(id: result, text: text, createdAt: now, ttl: ttl, fade: fade)

func hasActive*(queue: ToastQueue; now: float): bool =
  ## True while any toast is still within its live-or-fading window. Drives
  ## whether the host needs to keep redrawing for animation/expiry.
  for t in queue.items:
    if not expired(t, now):
      return true
  false

func visibleToasts*(queue: ToastQueue; now: float): seq[Toast] =
  ## Newest non-expired toasts, capped at `maxVisible`, newest first.
  for i in countdown(queue.items.high, 0):
    let t = queue.items[i]
    if not expired(t, now):
      result.add t
      if result.len >= queue.maxVisible:
        break

func toastAlpha*(t: Toast; now: float): float =
  ## Opacity in 0.0 .. 1.0: full while live, linearly fading over `fade`.
  if now <= t.createdAt + t.ttl:
    1.0
  elif t.fade <= 0.0:
    0.0
  else:
    let into = now - (t.createdAt + t.ttl)
    max(0.0, min(1.0, 1.0 - into / t.fade))
