-- Minimal test harness (no dependencies). Works on LuaJIT and Lua 5.1-5.5.
local H = {passed = 0, failed = 0, current = ""}

function H.test(name, fn)
	H.current = name
	local ok, err = pcall(fn)
	if ok then
		H.passed = H.passed + 1
		print("  ok   " .. name)
	else
		H.failed = H.failed + 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

function H.eq(a, b, msg)
	if a ~= b then
		error((msg or "values differ") .. ": expected " .. tostring(b)
			.. ", got " .. tostring(a), 2)
	end
end

function H.near(a, b, tol, msg)
	tol = tol or 1e-9
	if type(a) ~= "number" or math.abs(a - b) > tol then
		error((msg or "not near") .. ": expected " .. tostring(b) .. " +/- "
			.. tostring(tol) .. ", got " .. tostring(a), 2)
	end
end

function H.truthy(v, msg)
	if not v then error(msg or "expected truthy", 2) end
end

function H.falsy(v, msg)
	if v then error(msg or "expected falsy", 2) end
end

function H.raises(fn, msg)
	local ok = pcall(fn)
	if ok then error(msg or "expected an error", 2) end
end

function H.finish(suite)
	print(string.format("%s: %d passed, %d failed", suite, H.passed, H.failed))
	if H.failed > 0 then os.exit(1) end
end

-- Path of the mod folder, relative to this file.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
H.modpath = here .. "../trainhorn_gun"

return H
