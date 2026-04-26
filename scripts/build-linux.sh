#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

nimble install -y --depsOnly
nim c -d:release -o:nim_terminal src/nim_terminal.nim

echo "Built ./nim_terminal"
