#!/bin/sh
# Runs every test: unit + mocked integration (LuaJIT and any other Lua found),
# luacheck if installed, and the headless Luanti server test if Luanti is installed.
set -eu
cd "$(dirname "$0")"
for L in luajit lua5.1 lua; do
	if command -v "$L" >/dev/null 2>&1; then
		echo "== $L"
		"$L" tests/test_math.lua
		"$L" tests/test_integration.lua
	fi
done
if command -v luacheck >/dev/null 2>&1; then
	echo "== luacheck"
	luacheck --no-color trainhorn_gun tests
fi
if command -v luantiserver >/dev/null 2>&1 || command -v luanti >/dev/null 2>&1 \
	|| [ -x /Applications/luanti.app/Contents/MacOS/luanti ]; then
	echo "== headless Luanti server"
	tests/engine/run_server_test.sh
fi
echo "ALL TESTS PASSED"
