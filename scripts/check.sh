#!/usr/bin/env bash
# Full local verification: Rojo build, strict type-check (luau-lsp), lint (selene),
# formatting (stylua) and unit tests (lune). Run from the repository root.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEFS="globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	echo "Downloading Roblox type definitions for luau-lsp..."
	curl -sSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

status=0
step() { echo; echo "== $1"; }

step "wally install"
[ -d ServerPackages ] || wally install || status=1

step "rojo build"
mkdir -p build
rojo build default.project.json -o build/FactoryEmpire.rbxl || status=1

step "rojo sourcemap"
rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts || status=1

step "luau-lsp analyze (strict)"
luau-lsp analyze \
	--definitions="$DEFS" \
	--sourcemap=sourcemap.json \
	--ignore="ServerPackages/**" \
	--ignore="Packages/**" \
	--flag:LuauSolverV2=false \
	src || status=1

step "selene"
selene src || status=1

step "stylua --check"
stylua --check src tests tools || status=1

step "lune tests"
lune run tests/run || status=1

echo
if [ "$status" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "CHECKS FAILED"; fi
exit "$status"
