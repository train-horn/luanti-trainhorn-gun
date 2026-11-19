-- cone.lua: pure Lua cone-targeting math (no engine API).
-- Vectors are plain tables {x=, y=, z=}.

local M = {}

local EPS = 1e-9

local function sub(a, b)
	return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
end

local function len(v)
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

local function dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function M.normalize(v)
	local l = len(v)
	if l < EPS then
		return nil
	end
	return {x = v.x / l, y = v.y / l, z = v.z / l}
end

M.length = len
M.dot = dot

--- Angle in degrees between direction `dir` and the vector origin->target.
-- Returns nil when target coincides with origin or dir is zero.
function M.angle_deg(origin, dir, target)
	local n = M.normalize(dir)
	local to = M.normalize(sub(target, origin))
	if not n or not to then
		return nil
	end
	local c = dot(n, to)
	if c > 1 then c = 1 elseif c < -1 then c = -1 end
	return math.deg(math.acos(c))
end

--- Is `target` inside the cone (apex origin, axis dir, half-angle in degrees,
-- length range)? Returns inside(bool), distance(number).
-- A target exactly at the apex counts as inside (distance 0).
function M.in_cone(origin, dir, target, range, half_angle_deg)
	local d = len(sub(target, origin))
	if d > range then
		return false, d
	end
	if d < EPS then
		return true, 0
	end
	local n = M.normalize(dir)
	if not n then
		return false, d
	end
	local cos_limit = math.cos(math.rad(half_angle_deg))
	local c = dot(n, sub(target, origin)) / d
	-- small tolerance so a target exactly on the edge counts as inside
	return c >= cos_limit - 1e-12, d
end

--- Filter and sort candidates.
-- candidates: array of {pos = {x,y,z}, ...}; extra fields are kept.
-- Returns an array of {item = candidate, distance = d}, nearest first.
function M.select(origin, dir, candidates, range, half_angle_deg)
	local out = {}
	for _, cand in ipairs(candidates) do
		local ok, d = M.in_cone(origin, dir, cand.pos, range, half_angle_deg)
		if ok then
			out[#out + 1] = {item = cand, distance = d}
		end
	end
	table.sort(out, function(a, b) return a.distance < b.distance end)
	return out
end

return M
