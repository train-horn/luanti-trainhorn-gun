#!/bin/sh
# Loads trainhorn_gun in a real headless Luanti server and runs the in-engine checks.
# Usage: tests/engine/run_server_test.sh [path-to-luanti-binary]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
MOD=$(cd "$HERE/../../trainhorn_gun" && pwd)
BIN=${1:-$(command -v luantiserver || command -v luanti || echo /Applications/luanti.app/Contents/MacOS/luanti)}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -R "$HERE/games" "$WORK/games"
cp -R "$MOD" "$WORK/games/thtest/mods/trainhorn_gun"
mkdir -p "$WORK/world"
printf 'gameid = thtest\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$WORK/world/world.mt"
printf 'mg_name = singlenode\nenable_pvp = true\n' > "$WORK/server.conf"
cd "$WORK"
MINETEST_GAME_PATH="$WORK/games" LUANTI_GAME_PATH="$WORK/games" \
	"$BIN" --server --world "$WORK/world" --gameid thtest --config "$WORK/server.conf" \
	--logfile "$WORK/debug.txt" --port 30777 >/dev/null 2>&1 || true
cat "$WORK/debug.txt" | grep -E "ERROR|WARNING|THTEST|trainhorn" || true
if grep -q "ERROR" "$WORK/debug.txt"; then echo "server log has errors"; exit 1; fi
grep -q "THTEST PASS" "$WORK/debug.txt" || { echo "in-engine checks did not pass"; exit 1; }
echo "engine test passed"
