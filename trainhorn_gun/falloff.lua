-- falloff.lua: pure Lua sound-falloff math (no engine API).
--
-- Free-field point source, inverse-square law:
--   intensity ratio  I(d)/I(ref) = (ref/d)^2
--   level drop       dL = 20 * log10(d/ref) dB  (about 6.02 dB per doubling)
-- This is the same model as https://train-horn.com/tools/decibel-distance/.
-- It is a physics approximation: real horns are directional, and ground,
-- air absorption and obstacles change the result.
--
-- Works on LuaJIT / Lua 5.1 (Luanti) and Lua 5.2+ (no math.log10 needed).

local M = {}

local LN10 = math.log(10)

local function log10(x)
	return math.log(x) / LN10
end

--- dB lost per doubling of distance: 20*log10(2) ~= 6.0206.
M.DB_PER_DOUBLING = 20 * log10(2)

local function check_positive(v, name)
	if type(v) ~= "number" or v ~= v or v <= 0 then
		error(name .. " must be a positive number", 3)
	end
end

--- Attenuation in dB from ref_distance to distance (>= 0 for d >= ref).
-- Distances closer than ref_distance are clamped to ref_distance
-- (the near field is not modelled, so we never amplify).
function M.attenuation_db(distance, ref_distance)
	ref_distance = ref_distance or 1
	check_positive(ref_distance, "ref_distance")
	if type(distance) ~= "number" or distance ~= distance or distance < 0 then
		error("distance must be a non-negative number", 2)
	end
	if distance <= ref_distance then
		return 0
	end
	return 20 * log10(distance / ref_distance)
end

--- Sound level at distance, given the level ref_db measured at ref_distance.
function M.level_at(ref_db, distance, ref_distance)
	if type(ref_db) ~= "number" then
		error("ref_db must be a number", 2)
	end
	return ref_db - M.attenuation_db(distance, ref_distance)
end

--- Distance at which the level falls to target_db (inverse of level_at).
function M.distance_for_level(ref_db, target_db, ref_distance)
	ref_distance = ref_distance or 1
	check_positive(ref_distance, "ref_distance")
	if target_db >= ref_db then
		return ref_distance
	end
	return ref_distance * 10 ^ ((ref_db - target_db) / 20)
end

--- Intensity ratio I(d)/I(ref) in (0, 1].
function M.intensity_ratio(distance, ref_distance)
	return 10 ^ (-M.attenuation_db(distance, ref_distance) / 10)
end

--- Stun strength in [0, 1] for a target at `distance`.
--
-- The strength is linear in decibels between the reference distance
-- (strength 1) and the maximum range (strength min_strength), and 0
-- beyond range. Because it follows the dB scale, every doubling of
-- distance removes the same share of strength (6 dB worth), which is how
-- a horn "feels" quieter far away, instead of the raw intensity ratio
-- (which would already be 1/64 at 8 nodes).
--
-- opts: ref_distance (default 1), min_strength (default 0.15)
function M.stun_strength(distance, range, opts)
	opts = opts or {}
	local ref = opts.ref_distance or 1
	local min_strength = opts.min_strength or 0.15
	check_positive(range, "range")
	check_positive(ref, "ref_distance")
	if type(distance) ~= "number" or distance ~= distance or distance < 0 then
		error("distance must be a non-negative number", 2)
	end
	if distance > range then
		return 0
	end
	if range <= ref or distance <= ref then
		return 1
	end
	local span = M.attenuation_db(range, ref)
	local att = M.attenuation_db(distance, ref)
	local s = 1 - (1 - min_strength) * (att / span)
	if s < min_strength then s = min_strength end
	if s > 1 then s = 1 end
	return s
end

--- Linear interpolation helper: value at full strength -> value at zero.
-- e.g. lerp_effect(0.3, 1.0, s) gives the walking-speed multiplier.
function M.lerp_effect(full_value, none_value, strength)
	if strength < 0 then strength = 0 end
	if strength > 1 then strength = 1 end
	return none_value + (full_value - none_value) * strength
end

return M
