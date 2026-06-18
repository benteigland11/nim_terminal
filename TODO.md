# TODO

These are personal notes for possible future Waymark work, not a release roadmap.

## Later

- Investigate a full Nim/Nimble dependency pinning or lock strategy.
- Package Waymark so users can run `nimble install waymark`.
- [x] Add OSC 0/1/2 title handling for tab names. (Done: tab labels resolve through `universal-title-resolver-nim` using OSC title, foreground program, then CWD.)
- [x] Add foreground-command fallback tab titles. (Done: `processName` feeds the title resolver when no OSC title wins.)
- Make `Ctrl+Shift+W` close the active tab when that tab has only one pane.
- Expand Windows packaging and testing.
- Finish VT validation beyond the v0.1.2 stability baseline:
  - [x] Add a vttest-style corpus for cursor movement, scrolling, erase, insert/delete, SGR, alternate screen, OSC, DCS, and parser cancellation. (Done: Fully ported esctest coverage for core VT behaviors)
  - [ ] Add legacy 8-bit C1 profile coverage to the compliance suite. (Parser support exists behind `utf8Mode = false`; this still needs vector-level coverage separate from the default UTF-8 profile.)
  - [x] Add mouse reporting vectors, not just mode toggling. (Done: `data-input-vt-encoding-nim` covers disabled, X11, SGR, wheel, drag, modifiers, and coordinate clamping; Waymark compliance covers `1000`, `1002`, `1003`, and `1006` mode state.)
  - [ ] Add resize/reflow validation cases for normal screen, alternate screen, and pane-sized terminals.
  - [x] Add more wide-character and combining-mark edge cases around `DCH`, `ICH`, `ECH`, wrapping, and selection. (Done: Fixed emoji tearing in data-screen-buffer-nim widget)
  - [x] Add malformed/split OSC, CSI, and DCS fuzz-style cases with expected recovery behavior. (Done: Parser correctly swallows/recovers out of the box)
  - [ ] Track remaining xterm/vttest gaps explicitly as unsupported, partial, or passing.
