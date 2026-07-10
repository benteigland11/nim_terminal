## Desktop-notification OSC payload parsing for terminal hosts.
##
## Covers the practical subset used by modern CLIs:
##   * OSC 9  — iTerm2-style message body (excluding ConEmu progress `4;…`)
##   * OSC 99 — Kitty-style `metadata ; payload` (title/body chunks)
##   * OSC 777 — urxvt/VTE `notify ; title ; body`
##
## Pure logic: no I/O, no OS notification API. Hosts map results to toasts or
## system notifications.

import std/[base64, strutils, tables]

type
  DesktopNotification* = object
    title*: string
    body*: string
    source*: string   ## "osc9", "osc99", "osc777"

  NotificationDraft = object
    title*: string
    body*: string

  NotificationAssembler* = object
    ## Accumulates multi-chunk OSC 99 notifications keyed by id (`i=`).
    drafts*: Table[string, NotificationDraft]

func newNotificationAssembler*(): NotificationAssembler =
  NotificationAssembler(drafts: initTable[string, NotificationDraft]())

func isBlank*(n: DesktopNotification): bool =
  n.title.strip().len == 0 and n.body.strip().len == 0

func toastText*(n: DesktopNotification): string =
  ## Single-line host toast string: "title — body" or whichever part exists.
  let t = n.title.strip()
  let b = n.body.strip()
  if t.len > 0 and b.len > 0:
    t & " — " & b
  elif t.len > 0:
    t
  else:
    b

func decodeMaybeBase64(payload: string, encoded: bool): string =
  if not encoded:
    return payload
  try:
    result = decode(payload)
  except CatchableError:
    result = payload

func parseOsc9Notification*(body: string): tuple[ok: bool, note: DesktopNotification] =
  ## iTerm2 OSC 9: body is the message. Progress form `4;…` is not a notification.
  result.ok = false
  let text = body.strip()
  if text.len == 0:
    return
  if text.startsWith("4;") or text == "4":
    return
  result.ok = true
  result.note = DesktopNotification(title: "", body: text, source: "osc9")

func parseOsc777Notification*(body: string): tuple[ok: bool, note: DesktopNotification] =
  ## urxvt/VTE: `notify ; title ; body` or `notify ; message`.
  result.ok = false
  let parts = body.split(';')
  if parts.len < 2:
    return
  if parts[0].strip().toLowerAscii() != "notify":
    return
  if parts.len >= 3:
    result.note = DesktopNotification(
      title: parts[1].strip(),
      body: parts[2 .. ^1].join(";").strip(),
      source: "osc777",
    )
  else:
    result.note = DesktopNotification(
      title: "",
      body: parts[1].strip(),
      source: "osc777",
    )
  result.ok = not result.note.isBlank

func parseMetadataMap(meta: string): Table[string, string] =
  result = initTable[string, string]()
  if meta.len == 0:
    return
  for chunk in meta.split(':'):
    let eq = chunk.find('=')
    if eq <= 0:
      continue
    let key = chunk[0 ..< eq].strip()
    let val = chunk[eq + 1 .. ^1].strip()
    if key.len == 1:
      ## Last value wins for repeated single-letter keys except we only need one.
      result[key] = val

func feedOsc99*(
    a: var NotificationAssembler;
    body: string,
): tuple[ok: bool, note: DesktopNotification] =
  ## Consume one OSC 99 `metadata ; payload` body. Emits a notification when
  ## the chunk is complete (`d` missing or non-zero) and has title and/or body.
  result.ok = false
  let sep = body.find(';')
  let meta =
    if sep < 0: body
    else: body[0 ..< sep]
  let payload =
    if sep < 0: ""
    else: body[sep + 1 .. ^1]

  let kv = parseMetadataMap(meta)
  let id = kv.getOrDefault("i", "")
  let key = if id.len > 0: id else: ""
  var p = kv.getOrDefault("p", "title")
  if p.len == 0:
    p = "title"
  ## Control payloads we do not surface as toasts.
  if p in ["close", "?", "alive", "icon", "buttons"]:
    return
  let encoded = kv.getOrDefault("e", "0") == "1"
  let done =
    if "d" notin kv: true
    else: kv["d"] != "0"
  let text = decodeMaybeBase64(payload, encoded).strip()

  var draft =
    if key.len > 0 and key in a.drafts: a.drafts[key]
    else: NotificationDraft()

  case p
  of "body":
    if text.len > 0:
      if draft.body.len > 0: draft.body.add text
      else: draft.body = text
  else:
    ## Default / title
    if text.len > 0:
      if draft.title.len > 0: draft.title.add text
      else: draft.title = text

  if not done:
    if key.len > 0:
      a.drafts[key] = draft
    return

  if key.len > 0:
    a.drafts.del key

  result.note = DesktopNotification(
    title: draft.title,
    body: draft.body,
    source: "osc99",
  )
  ## Kitty allows body-only: body becomes the title for display purposes.
  if result.note.title.len == 0 and result.note.body.len > 0:
    result.note.title = result.note.body
    result.note.body = ""
  result.ok = not result.note.isBlank
