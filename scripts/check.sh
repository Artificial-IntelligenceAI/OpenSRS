#!/usr/bin/env bash
# Runs every code check CI runs: formatting, linting and strict type checking.
set -euo pipefail
cd "$(dirname "$0")/.."

defs=".cache/globalTypes.d.luau"
if [ ! -f "$defs" ]; then
	mkdir -p .cache
	curl -fsSL -o "$defs" \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.69.0/scripts/globalTypes.d.luau
fi

stylua --check src
lune run scripts/generate-settings --check
selene src
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox="$defs" src
echo "All checks passed."
