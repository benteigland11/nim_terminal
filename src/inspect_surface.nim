## Widget inspect session: directory tree, preview text, and scroll state.

import std/os
import ../cg/data_directory_tree_nim/src/directory_tree_lib as directory_tree
import ../cg/frontend_scroll_tree_nim/src/scroll_tree_lib as scroll_tree
import ../cg/data_source_lexer_nim/src/source_lexer_lib as source_lexer
import ../cg/frontend_syntax_viewport_nim/src/syntax_viewport_lib as syntax_viewport
import ../cg/frontend_overlay_stack_nim/src/overlay_stack_lib as overlay_lib

type
  TokenSpan* = syntax_viewport.SourceTokenSpan

  InspectSession* = ref object
    tree*: directory_tree.DirectoryTree
    treeScrollRow*: int
    codeScrollRow*: int
    previewPath*: string
    previewText*: string
    previewSpans*: seq[TokenSpan]
    dirty*: bool

func newInspectSession*(): InspectSession =
  InspectSession(
    tree: directory_tree.newDirectoryTree(""),
    dirty: true,
  )

proc markInspectDirty*(session: InspectSession) =
  if session != nil:
    session.dirty = true

proc clearInspectDirty*(session: InspectSession) =
  if session != nil:
    session.dirty = false

proc inspectNeedsRedraw*(session: InspectSession): bool =
  session != nil and session.dirty

proc closeInspectSession*(session: InspectSession) =
  if session == nil:
    return
  session.tree = directory_tree.newDirectoryTree("")
  session.treeScrollRow = 0
  session.codeScrollRow = 0
  session.previewPath = ""
  session.previewText = ""
  session.previewSpans.setLen(0)
  session.dirty = true

func mapLexerKind(kind: source_lexer.SourceTokenKind): syntax_viewport.SourceTokenKind =
  case kind
  of source_lexer.stkComment: syntax_viewport.tvComment
  of source_lexer.stkString: syntax_viewport.tvString
  of source_lexer.stkNumber: syntax_viewport.tvNumber
  of source_lexer.stkKeyword: syntax_viewport.tvKeyword
  of source_lexer.stkType: syntax_viewport.tvType
  of source_lexer.stkOperator: syntax_viewport.tvOperator
  else: syntax_viewport.tvPlain

proc refreshInspectPreview*(session: InspectSession) =
  if session == nil:
    return
  let node = directory_tree.selectedDirectoryNode(session.tree)
  if node.kind == directory_tree.dnkDirectory:
    session.previewPath = ""
    session.previewText = ""
    session.previewSpans.setLen(0)
    session.codeScrollRow = 0
    return
  let path = directory_tree.selectedDirectoryPath(session.tree)
  if path.len == 0 or not fileExists(path):
    session.previewPath = ""
    session.previewText = ""
    session.previewSpans.setLen(0)
    session.codeScrollRow = 0
    return
  if path == session.previewPath and session.previewText.len > 0:
    return
  session.previewPath = path
  session.previewText = directory_tree.readBoundedTextFile(path)
  session.codeScrollRow = 0
  let language = source_lexer.inferSourceLanguage(path)
  let tokens = source_lexer.lexSource(session.previewText, language)
  session.previewSpans.setLen(0)
  for token in tokens:
    session.previewSpans.add (
      token.start,
      token.endEx,
      mapLexerKind(token.kind),
    )

proc openInspectSession*(session: InspectSession; rootPath, title: string) =
  if session == nil:
    return
  session.tree = directory_tree.newDirectoryTree(rootPath)
  directory_tree.loadDirectoryTree(session.tree)
  session.treeScrollRow = 0
  session.codeScrollRow = 0
  refreshInspectPreview(session)
  session.dirty = true

func inspectTreeRows*(session: InspectSession): seq[scroll_tree.TreeRowView] =
  if session == nil:
    return @[]
  for row in directory_tree.flattenDirectoryTree(session.tree):
    result.add scroll_tree.TreeRowView(
      depth: row.depth,
      label: row.label,
      rowId: row.nodeIndex,
      isBranch: row.isBranch,
      expanded: row.expanded,
    )

func inspectTreeLayout*(session: InspectSession; pane: overlay_lib.OverlayRect; cellW, cellH: int): scroll_tree.ScrollTreeLayout =
  let rows = inspectTreeRows(session)
  scroll_tree.computeScrollTreeLayout(
    scroll_tree.TreePanelRect(x: pane.x, y: pane.y, w: pane.w, h: pane.h),
    cellH,
    cellW,
    pad = 8,
    if session == nil: 0 else: session.treeScrollRow,
    rows.len,
  )

func inspectCodeViewport*(
  session: InspectSession;
  pane: overlay_lib.OverlayRect;
  cellW, cellH: int,
): syntax_viewport.SourceViewport =
  if session == nil or pane.w <= 0 or pane.h <= 0:
    return
  let cols = max(1, (pane.w - 16) div max(1, cellW))
  let maxRows = max(1, (pane.h - 16) div max(1, cellH))
  var spans: seq[syntax_viewport.SourceTokenSpan] = @[]
  for item in session.previewSpans:
    spans.add item
  syntax_viewport.buildSourceViewport(
    session.previewText,
    spans,
    cols,
    maxRows,
    session.codeScrollRow,
  )

proc handleInspectTreePointer*(session: InspectSession; layout: scroll_tree.ScrollTreeLayout; x, y: int; cellW: int): bool =
  if session == nil:
    return false
  let rows = inspectTreeRows(session)
  let hit = scroll_tree.treeRowHitTest(layout, rows, x, y, cellW)
  case hit.kind
  of scroll_tree.trhBranchToggle:
    directory_tree.toggleDirectoryNode(session.tree, hit.rowId)
    refreshInspectPreview(session)
    session.dirty = true
    true
  of scroll_tree.trhRow:
    directory_tree.selectDirectoryNode(session.tree, hit.rowId)
    refreshInspectPreview(session)
    session.dirty = true
    true
  else:
    false

proc handleInspectTreeWheel*(session: InspectSession; layout: scroll_tree.ScrollTreeLayout; yoffset: float): bool =
  if session == nil or abs(yoffset) < 0.01 or not layout.scrollable:
    return false
  let rows = inspectTreeRows(session)
  let maxScroll = max(0, rows.len - layout.visibleRows)
  let steps = max(1, int(abs(yoffset)))
  if yoffset > 0:
    session.treeScrollRow = max(0, session.treeScrollRow - steps)
  else:
    session.treeScrollRow = min(maxScroll, session.treeScrollRow + steps)
  session.dirty = true
  true

proc handleInspectCodeWheel*(session: InspectSession; pane: overlay_lib.OverlayRect; cellW, cellH: int; yoffset: float): bool =
  if session == nil or abs(yoffset) < 0.01:
    return false
  let viewport = inspectCodeViewport(session, pane, cellW, cellH)
  if viewport.totalLines <= viewport.lines.len:
    return false
  let maxScroll = max(0, viewport.totalLines - viewport.lines.len)
  let steps = max(1, int(abs(yoffset)))
  if yoffset > 0:
    session.codeScrollRow = max(0, session.codeScrollRow - steps)
  else:
    session.codeScrollRow = min(maxScroll, session.codeScrollRow + steps)
  session.dirty = true
  true

proc handleInspectExplorerPointer*(
  session: InspectSession;
  layout: overlay_lib.ExplorerChromeLayout;
  x, y: int;
  down: bool;
  cellW, cellH: int,
): bool =
  if session == nil or not down:
    return session != nil and overlay_lib.pointInOverlayRect(layout.panel, x, y)
  if overlay_lib.pointInOverlayRect(layout.treePane, x, y):
    let treeLayout = inspectTreeLayout(session, layout.treePane, cellW, cellH)
    if handleInspectTreePointer(session, treeLayout, x, y, cellW):
      return true
    return true
  if overlay_lib.pointInOverlayRect(layout.codePane, x, y):
    return true
  overlay_lib.pointInOverlayRect(layout.panel, x, y)
