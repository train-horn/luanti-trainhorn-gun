-- Unit tests for falloff.lua and cone.lua
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local H = dofile(here .. "harness.lua")
local falloff = dofile(H.modpath .. "/falloff.lua")
local cone = dofile(H.modpath .. "/cone.lua")
local test, eq, near, truthy, falsy, raises = H.test, H.eq, H.near, H.truthy, H.falsy, H.raises

print("falloff.lua")

test("6.02 dB per doubling constant", function()
	near(falloff.DB_PER_DOUBLING, 6.0206, 1e-4)
end)

test("attenuation: 0 at reference, 6.02 dB at 2x, 20 dB at 10x", function()
	near(falloff.attenuation_db(1, 1), 0)
	near(falloff.attenuation_db(2, 1), 6.0206, 1e-4)
	near(falloff.attenuation_db(10, 1), 20, 1e-9)
	near(falloff.attenuation_db(100, 1), 40, 1e-9)
	near(falloff.attenuation_db(30, 3), 20, 1e-9)
end)

test("every doubling adds the same drop", function()
	local a = falloff.attenuation_db(4, 1) - falloff.attenuation_db(2, 1)
	local b = falloff.attenuation_db(16, 1) - falloff.attenuation_db(8, 1)
	near(a, b, 1e-9)
	near(a, falloff.DB_PER_DOUBLING, 1e-9)
end)

test("near field is clamped (no amplification inside ref distance)", function()
	near(falloff.attenuation_db(0, 1), 0)
	near(falloff.attenuation_db(0.5, 1), 0)
end)

test("level_at matches the decibel-distance model (130 dB @ 1 m -> 100 dB @ ~31.6 m)", function()
	near(falloff.level_at(130, 1), 130)
	near(falloff.level_at(130, 2), 130 - 6.0206, 1e-4)
	near(falloff.level_at(130, math.sqrt(1000)), 100, 1e-9)
end)

test("distance_for_level inverts level_at", function()
	for _, d in ipairs({1.5, 2, 7, 33, 500}) do
		local l = falloff.level_at(120, d, 1)
		near(falloff.distance_for_level(120, l, 1), d, 1e-9)
	end
	eq(falloff.distance_for_level(120, 125, 1), 1, "target above source clamps to ref")
end)

test("intensity ratio is inverse-square", function()
	near(falloff.intensity_ratio(2, 1), 0.25, 1e-12)
	near(falloff.intensity_ratio(8, 1), 1 / 64, 1e-12)
	near(falloff.intensity_ratio(0.2, 1), 1, 1e-12)
end)

test("stun_strength: 1 at point blank, min at range, 0 beyond", function()
	eq(falloff.stun_strength(0, 8), 1)
	eq(falloff.stun_strength(1, 8), 1)
	near(falloff.stun_strength(8, 8), 0.15, 1e-12)
	eq(falloff.stun_strength(8.01, 8), 0)
	near(falloff.stun_strength(8, 8, {min_strength = 0}), 0, 1e-12)
end)

test("stun_strength is linear in dB: each doubling removes 1/3 of the span at range 8", function()
	local o = {min_strength = 0}
	near(falloff.stun_strength(2, 8, o), 2 / 3, 1e-12)
	near(falloff.stun_strength(4, 8, o), 1 / 3, 1e-12)
end)

test("stun_strength is monotonic non-increasing", function()
	local prev = 2
	for i = 0, 100 do
		local s = falloff.stun_strength(i * 0.1, 8)
		truthy(s <= prev + 1e-12, "not monotonic at " .. i * 0.1)
		truthy(s >= 0 and s <= 1, "out of [0,1]")
		prev = s
	end
end)

test("stun_strength with range <= ref distance is full inside range", function()
	eq(falloff.stun_strength(0.5, 1), 1)
	eq(falloff.stun_strength(1.5, 1), 0)
end)

test("input validation", function()
	raises(function() falloff.attenuation_db(-1, 1) end)
	raises(function() falloff.attenuation_db(1, 0) end)
	raises(function() falloff.stun_strength(1, 0) end)
	raises(function() falloff.stun_strength(0 / 0, 8) end)
	raises(function() falloff.level_at("loud", 2) end)
end)

test("lerp_effect clamps strength", function()
	near(falloff.lerp_effect(0.3, 1, 1), 0.3, 1e-12)
	near(falloff.lerp_effect(0.3, 1, 0), 1, 1e-12)
	near(falloff.lerp_effect(0.3, 1, 0.5), 0.65, 1e-12)
	near(falloff.lerp_effect(0.3, 1, 7), 0.3, 1e-12)
	near(falloff.lerp_effect(0.3, 1, -3), 1, 1e-12)
end)

print("cone.lua")

local O = {x = 0, y = 0, z = 0}
local FWD = {x = 0, y = 0, z = 1}

test("straight ahead is inside", function()
	local ok, d = cone.in_cone(O, FWD, {x = 0, y = 0, z = 5}, 8, 30)
	truthy(ok); near(d, 5)
end)

test("behind is outside", function()
	falsy(cone.in_cone(O, FWD, {x = 0, y = 0, z = -3}, 8, 30))
end)

test("beyond range is outside", function()
	local ok, d = cone.in_cone(O, FWD, {x = 0, y = 0, z = 8.5}, 8, 30)
	falsy(ok); near(d, 8.5)
end)

test("edge of the cone: 29 deg in, 31 deg out", function()
	local function at(deg)
		local r = math.rad(deg)
		return {x = 5 * math.sin(r), y = 0, z = 5 * math.cos(r)}
	end
	truthy(cone.in_cone(O, FWD, at(29), 8, 30))
	falsy(cone.in_cone(O, FWD, at(31), 8, 30))
	truthy(cone.in_cone(O, FWD, at(30), 8, 30), "exactly on the edge counts")
end)

test("vertical aim works (cone is 3D)", function()
	local up = {x = 0, y = 1, z = 0}
	truthy(cone.in_cone(O, up, {x = 0.5, y = 4, z = 0}, 8, 30))
	falsy(cone.in_cone(O, FWD, {x = 0, y = 4, z = 0.5}, 8, 30))
end)

test("non-unit direction is normalised", function()
	truthy(cone.in_cone(O, {x = 0, y = 0, z = 42}, {x = 1, y = 0, z = 4}, 8, 30))
end)

test("zero direction never hits (except at apex)", function()
	falsy(cone.in_cone(O, {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 1}, 8, 30))
	truthy(cone.in_cone(O, {x = 0, y = 0, z = 0}, O, 8, 30))
end)

test("angle_deg", function()
	near(cone.angle_deg(O, FWD, {x = 1, y = 0, z = 1}), 45, 1e-9)
	near(cone.angle_deg(O, FWD, {x = 0, y = 0, z = -1}), 180, 1e-9)
	eq(cone.angle_deg(O, FWD, O), nil)
end)

test("select filters and sorts nearest first", function()
	local list = {
		{pos = {x = 0, y = 0, z = 6}, id = "far"},
		{pos = {x = 0, y = 0, z = -2}, id = "behind"},
		{pos = {x = 0.5, y = 0, z = 2}, id = "near"},
		{pos = {x = 6, y = 0, z = 1}, id = "side"},
		{pos = {x = 0, y = 0, z = 20}, id = "out"},
	}
	local r = cone.select(O, FWD, list, 8, 30)
	eq(#r, 2)
	eq(r[1].item.id, "near")
	eq(r[2].item.id, "far")
	near(r[2].distance, 6)
end)

test("offset origin", function()
	local o = {x = 100, y = 10, z = -50}
	truthy(cone.in_cone(o, {x = 1, y = 0, z = 0}, {x = 105, y = 10.5, z = -50}, 8, 30))
	falsy(cone.in_cone(o, {x = 1, y = 0, z = 0}, {x = 95, y = 10, z = -50}, 8, 30))
end)

H.finish("unit tests")
