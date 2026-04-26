#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

binary="$repo_root/nim_terminal"
icon="$repo_root/logo.svg"
desktop_dir="$HOME/.local/share/applications"
desktop_file="$desktop_dir/waymark.desktop"

if [[ ! -x "$binary" ]]; then
  echo "Waymark binary is missing or not executable: $binary" >&2
  echo "Build it first with: ./scripts/build-linux.sh" >&2
  exit 1
fi

if [[ ! -f "$icon" ]]; then
  echo "Waymark icon is missing: $icon" >&2
  exit 1
fi

mkdir -p "$desktop_dir"

cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Waymark
GenericName=Terminal Emulator
Comment=Waymark terminal emulator built with Nim
Exec=$binary
Path=$repo_root
Icon=$icon
Terminal=false
Categories=System;TerminalEmulator;
Keywords=terminal;shell;nim;waymark;
StartupNotify=true
EOF

chmod 0644 "$desktop_file"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
fi

echo "Installed Waymark desktop launcher:"
echo "  $desktop_file"
echo
echo "Open it from your app launcher by searching for Waymark."
if command -v gtk-launch >/dev/null 2>&1; then
  echo "You can also run: gtk-launch waymark"
fi
