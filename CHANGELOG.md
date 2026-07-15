# Changelog

## v0.1.6

Agent-harness readability and host stability pass for Waymark:

- Stopped Codex-style prompt highlights from matching bare ASCII `>` so
  Antigravity / Gemini CLI slash-command chrome is not painted as full-width
  gray bands.
- Soft-archive skips agent slash-command / sticky chrome (`> /…`, accept-edits
  footers, `↓ N more`) so EL/ED redraws do not stack ghost prompt rows.
- Applied bold-as-bright, mild bold brighten, softer dim, and dark-theme
  near-gray lift so markdown body copy is no longer muddy mid-gray.
- Faux-bold glyph stamp + nearest atlas filtering for crisper text.
- Configurable theme foreground (`theme.foreground`, default `#f5f6f8`).
- Non-blocking PTY wait with SIGKILL escalate so hung children cannot freeze
  window close.
- Synchronized-update bracket timeout so stuck DEC 2026 cannot freeze present.
- Bounded DCS payload, semantic-history block cap, throttled tab CWD labels.
- Resize policy: skip no-ops, hold last-good size under min floor, rate-limit
  SIGWINCH (including undersized multi-pane layouts).

Widgets touched: `frontend-cursor-row-highlight-nim`, `data-screen-buffer-nim`,
`data-terminal-render-attrs-nim`, `data-terminal-theme-nim`,
`data-terminal-sync-update-nim`, `data-semantic-history-nim`,
`data-terminal-resize-policy-nim`.

## v0.1.5

Modern TUI / agent-CLI compatibility pass for Waymark:

- Fixed soft-archive scrollback dedup so Codex-style redraws no longer stack
  duplicated conversation history (frame suffix + recent-window row dedup).
- Refused pane splits that would leave TUI-unusable cell grids; collapse
  padding on tiny panes.
- Added OSC 9;4 ConEmu/Windows Terminal progress bar (Claude Code compact, etc.)
  with a title-chrome progress strip.
- Wired OSC 52 clipboard set/query to system clipboard providers; timed out
  hung `wl-paste` so paste no longer freezes the UI.
- Implemented OSC 8 hyperlinks (cell link stamping, hover, click, underlines).
- Drew SGR underline styles: single, double, curly, dotted, dashed.
- Added OSC 9 / 99 / 777 desktop notifications as in-app toasts (including
  primary terminal surface).
- Kept host text paste on Ctrl+Shift+V and Shift+Insert; left Ctrl+V for the
  child so Claude Code image paste keeps working.
- Fixed alt-screen wheel routing defaults so passive scrollback does not steal
  wheel from full-screen TUIs; profile defaults prefer app-owned wheel on alt
  screen.

New / updated widgets published under `@benteigland11` include
`data-screen-buffer-nim`, `data-terminal-progress-nim`,
`data-terminal-notification-nim`, `data-vt-commands-nim`,
`frontend-underline-decoration-nim`, `frontend-cursor-row-highlight-nim`,
`backend-system-clipboard-nim`, `universal-split-pane-tree-nim`, and
`universal-shortcut-map-nim`.

## v0.1.3

- Fixed numpad Enter so it sends carriage return even when application keypad mode is active.
- Rebuilt the Linux release binary after the input encoding fix.

## v0.1.2

- Added a reusable VT compliance suite widget and a 136-vector Waymark adapter test.
- Preserved the visible top row when output arrives while the user is scrolled back.
- Added DECOM origin-mode handling and hardened VT report / scroll-region semantics.

## v0.1.1

- Fixed PTY lifecycle cleanup so child processes are shut down more reliably.
- Improved modern TUI compatibility by preserving scrollback from top-anchored scroll regions.
- Added terminal scroll policy coverage for normal-screen and alternate-screen wheel routing.
- Improved viewport/history handling for Codex, Gemini CLI, JAX-style TUIs, and split panes.

## v0.1.0

- Initial Waymark release.
