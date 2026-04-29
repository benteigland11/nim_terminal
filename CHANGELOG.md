# Changelog

## Unreleased

- Added a reusable VT compliance suite widget and an 88-vector Waymark adapter test.
- Preserved the visible top row when output arrives while the user is scrolled back.
- Added DECOM origin-mode handling and hardened VT report / scroll-region semantics.

## v0.1.1

- Fixed PTY lifecycle cleanup so child processes are shut down more reliably.
- Improved modern TUI compatibility by preserving scrollback from top-anchored scroll regions.
- Added terminal scroll policy coverage for normal-screen and alternate-screen wheel routing.
- Improved viewport/history handling for Codex, Gemini CLI, JAX-style TUIs, and split panes.

## v0.1.0

- Initial Waymark release.
