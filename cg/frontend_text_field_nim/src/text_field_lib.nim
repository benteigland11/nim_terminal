## Single-line editable text field state.
##
## Pure model for a text input: holds the buffer, a caret, and an optional
## selection, and exposes editing operations plus a viewport helper for
## horizontal scrolling. No rendering, no I/O — the host draws the returned
## view and feeds it key/rune events.
##
## The caret and selection are measured in runes (not bytes) so multibyte
## input behaves correctly.

import std/unicode

type
  TextField* = object
    runes: seq[Rune]
    caret*: int          ## Caret position as a rune index in 0 .. len.
    anchor*: int         ## Selection anchor rune index, or -1 when no selection.
    scrollCol*: int      ## First visible rune column (horizontal scroll).

  TextFieldView* = object
    text*: string        ## Visible slice of the field.
    caretCol*: int       ## Caret column within the visible slice.
    selStart*, selEnd*: int  ## Selection span within visible slice, or -1/-1.

proc deleteRange(runes: var seq[Rune]; lo, hi: int) =
  ## Remove runes in the half-open range [lo, hi).
  if hi <= lo:
    return
  let count = hi - lo
  for i in lo ..< runes.len - count:
    runes[i] = runes[i + count]
  runes.setLen(runes.len - count)

func newTextField*(initial = ""): TextField =
  let runes = initial.toRunes
  TextField(runes: runes, caret: runes.len, anchor: -1, scrollCol: 0)

func len*(field: TextField): int =
  field.runes.len

func text*(field: TextField): string =
  $field.runes

func isEmpty*(field: TextField): bool =
  field.runes.len == 0

func hasSelection*(field: TextField): bool =
  field.anchor >= 0 and field.anchor != field.caret

func selectionBounds*(field: TextField): (int, int) =
  if not field.hasSelection():
    (field.caret, field.caret)
  elif field.anchor < field.caret:
    (field.anchor, field.caret)
  else:
    (field.caret, field.anchor)

proc clearSelection*(field: var TextField) =
  field.anchor = -1

proc setText*(field: var TextField; value: string) =
  field.runes = value.toRunes
  field.caret = field.runes.len
  field.anchor = -1
  field.scrollCol = 0

proc clear*(field: var TextField) =
  field.setText("")

proc deleteSelection(field: var TextField): bool =
  if not field.hasSelection():
    return false
  let (lo, hi) = field.selectionBounds()
  deleteRange(field.runes, lo, hi)
  field.caret = lo
  field.anchor = -1
  true

proc insertRune*(field: var TextField; rune: Rune) =
  discard field.deleteSelection()
  field.runes.insert(rune, field.caret)
  inc field.caret

proc insertText*(field: var TextField; value: string) =
  discard field.deleteSelection()
  for rune in value.runes:
    field.runes.insert(rune, field.caret)
    inc field.caret

proc backspace*(field: var TextField): bool =
  if field.deleteSelection():
    return true
  if field.caret <= 0:
    return false
  deleteRange(field.runes, field.caret - 1, field.caret)
  dec field.caret
  true

proc deleteForward*(field: var TextField): bool =
  if field.deleteSelection():
    return true
  if field.caret >= field.runes.len:
    return false
  deleteRange(field.runes, field.caret, field.caret + 1)
  true

proc moveCaret(field: var TextField; target: int; extend: bool) =
  let clamped = max(0, min(target, field.runes.len))
  if extend:
    if field.anchor < 0:
      field.anchor = field.caret
  else:
    field.anchor = -1
  field.caret = clamped

proc moveLeft*(field: var TextField; extend = false) =
  field.moveCaret(field.caret - 1, extend)

proc moveRight*(field: var TextField; extend = false) =
  field.moveCaret(field.caret + 1, extend)

proc moveHome*(field: var TextField; extend = false) =
  field.moveCaret(0, extend)

proc moveEnd*(field: var TextField; extend = false) =
  field.moveCaret(field.runes.len, extend)

proc selectAll*(field: var TextField) =
  field.anchor = 0
  field.caret = field.runes.len

proc viewport*(field: var TextField; visibleCols: int): TextFieldView =
  ## Compute the visible slice and caret column for a field `visibleCols` wide,
  ## adjusting the horizontal scroll so the caret stays in view.
  if visibleCols <= 0:
    return TextFieldView(text: "", caretCol: 0, selStart: -1, selEnd: -1)
  if field.caret < field.scrollCol:
    field.scrollCol = field.caret
  elif field.caret >= field.scrollCol + visibleCols:
    field.scrollCol = field.caret - visibleCols + 1
  if field.scrollCol < 0:
    field.scrollCol = 0
  let first = field.scrollCol
  let last = min(field.runes.len, first + visibleCols)
  var slice = ""
  for i in first ..< last:
    slice.add $field.runes[i]
  result.text = slice
  result.caretCol = field.caret - first
  result.selStart = -1
  result.selEnd = -1
  if field.hasSelection():
    let (lo, hi) = field.selectionBounds()
    let visLo = max(lo, first)
    let visHi = min(hi, last)
    if visHi > visLo:
      result.selStart = visLo - first
      result.selEnd = visHi - first
