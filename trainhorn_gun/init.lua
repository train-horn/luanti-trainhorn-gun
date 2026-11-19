-- Portable Train Horn Gun (trainhorn_gun) for Luanti (formerly Minetest)
-- Code: MIT. Media: CC BY 4.0. See LICENSE and README.md.
-- By Train Horn, https://train-horn.com/

local modname = minetest.get_current_modname() or "trainhorn_gun"
local modpath = minetest.get_modpath(modname)
local S = minetest.get_translator and minetest.get_translator(modname)
	or function(s) return s end

local falloff = dofile(modpath .. "/falloff.lua")
local cone = dofile(modpath .. "/cone.lua")

trainhorn_gun = {
	falloff = falloff,
	cone = cone,
}
local api = trainhorn_gun

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

local settings = minetest.settings

local function num(name, default, lo, hi)
	local v = tonumber(settings:get("trainhorn_gun_" .. name))
	if v == nil or v ~= v then v = default end
	if lo and v < lo then v = lo end
	if hi and v > hi then v = hi end
	return v
end

local function bool(name, default)
	local v = settings:get_bool("trainhorn_gun_" .. name)
	if v == nil then return default end
	return v
end

api.config = {
	range = num("range", 8, 1, 32),
	cone_angle = num("cone_angle", 30, 1, 89),
	stun_duration = num("stun_duration", 3, 0.1, 30),
	stun_speed = num("stun_speed", 0.3, 0, 1),
	damage = math.floor(num("damage", 0, 0, 20)),
	knockback = num("knockback", 3, 0, 20),
	cooldown = num("cooldown", 2, 0, 60),
	uses = math.floor(num("uses", 200, 0, 65535)),
	affect_players = bool("affect_players", true),
	require_los = bool("require_los", true),
	min_strength = num("min_strength", 0.15, 0, 1),
	victory_cooldown = num("victory_cooldown", 30, 0, 3600),
	victory_on_kill = bool("victory_on_kill", false),
}
local cfg = api.config

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function now()
	return minetest.get_us_time() / 1e6
end

local function vadd(a, b)
	return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
end

-- Aim points of an object: body centre and head (top of the collision box).
local function aim_points_of(obj)
	local pos = obj:get_pos()
	if not pos then return nil end
	local props = obj:get_properties() or {}
	local cb = props.collisionbox
	if not cb then
		local dy = obj:is_player() and 1.0 or 0
		return {vadd(pos, {x = 0, y = dy, z = 0})}
	end
	local y1, y2 = cb[2] or 0, cb[5] or 0
	return {
		vadd(pos, {x = 0, y = (y1 + y2) / 2, z = 0}),
		vadd(pos, {x = 0, y = y1 + (y2 - y1) * 0.9, z = 0}),
	}
end

local function eye_of(player)
	local pos = player:get_pos()
	local props = player:get_properties() or {}
	local eh = props.eye_height or 1.625
	return vadd(pos, {x = 0, y = eh, z = 0})
end

-- Can this object be stunned at all?
local function stunnable(obj, user)
	if obj == user then return false end
	if obj:is_player() then
		if not cfg.affect_players then return false end
		if not settings:get_bool("enable_pvp", true) then return false end
		return true
	end
	local ent = obj:get_luaentity()
	if not ent or not ent.name then return false end
	if ent.name:sub(1, 10) == "__builtin:" then return false end
	local ag = obj:get_armor_groups() or {}
	if ag.immortal and ag.immortal ~= 0 then return false end
	return true
end

------------------------------------------------------------------------
-- Stun state and restore
------------------------------------------------------------------------

-- players[name] = {until_t, saved_speed, factor, token}
-- entities[obj]  = {until_t, factor}
local players = {}
local entities = {}
local token_seq = 0
api._players = players
api._entities = entities

function api.restore_player(player_or_name)
	local name = type(player_or_name) == "string" and player_or_name
		or player_or_name:get_player_name()
	local st = players[name]
	if not st then return false end
	players[name] = nil
	local player = type(player_or_name) ~= "string" and player_or_name
		or minetest.get_player_by_name(name)
	if player then
		player:set_physics_override({speed = st.saved_speed})
	end
	return true
end

local function expire_player(name, token)
	local st = players[name]
	if st and st.token == token then
		api.restore_player(name)
	end
end

function api.is_stunned(obj)
	if obj:is_player() then
		return players[obj:get_player_name()] ~= nil
	end
	local st = entities[obj]
	return st ~= nil and st.until_t > now()
end

--- Stun an object. strength in [0,1] scales slowdown, duration, knockback.
-- dir (optional) is the knockback direction.
function api.stun(obj, strength, dir, source)
	if strength <= 0 then return false end
	local duration = cfg.stun_duration * strength
	local factor = falloff.lerp_effect(cfg.stun_speed, 1, strength)
	local t_end = now() + duration

	if obj:is_player() then
		local name = obj:get_player_name()
		local st = players[name]
		if not st then
			local phys = obj:get_physics_override() or {}
			st = {saved_speed = phys.speed or 1, factor = 1}
			players[name] = st
		end
		token_seq = token_seq + 1
		st.token = token_seq
		if not st.until_t or t_end > st.until_t then st.until_t = t_end end
		if factor < st.factor then st.factor = factor end
		obj:set_physics_override({speed = st.saved_speed * st.factor})
		minetest.after(st.until_t - now(), expire_player, name, st.token)
		minetest.sound_play("trainhorn_gun_stun",
			{to_player = name, gain = 0.4 + 0.6 * strength}, true)
	else
		local st = entities[obj]
		if not st then
			st = {until_t = 0, factor = 1}
			entities[obj] = st
		end
		if t_end > st.until_t then st.until_t = t_end end
		if factor < st.factor then st.factor = factor end
		local ent = obj:get_luaentity()
		if ent then ent._trainhorn_stun_until = st.until_t end
		minetest.sound_play("trainhorn_gun_stun",
			{object = obj, gain = 0.3 + 0.5 * strength, max_hear_distance = 16},
			true)
	end

	if cfg.knockback > 0 and dir then
		local k = cfg.knockback * strength
		obj:add_velocity({x = dir.x * k, y = 1 + k * 0.25, z = dir.z * k})
	end
	if cfg.damage > 0 then
		local dmg = math.max(1, math.floor(cfg.damage * strength + 0.5))
		obj:punch(source or obj, 1.0, {
			full_punch_interval = 1.0,
			damage_groups = {fleshy = dmg},
		}, dir)
	end
	return true
end

-- Entities have no physics override: damp their horizontal speed every step.
minetest.register_globalstep(function()
	local t = now()
	for obj, st in pairs(entities) do
		local ent = obj:get_luaentity()
		if not obj:get_pos() or not ent then
			entities[obj] = nil
		elseif st.until_t <= t then
			entities[obj] = nil
			ent._trainhorn_stun_until = nil
		else
			local v = obj:get_velocity()
			if v then
				obj:set_velocity({x = v.x * st.factor, y = v.y, z = v.z * st.factor})
			end
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	api.restore_player(player)
end)
minetest.register_on_dieplayer(function(player)
	api.restore_player(player)
end)
minetest.register_on_respawnplayer(function(player)
	api.restore_player(player)
end)
minetest.register_on_shutdown(function()
	for name in pairs(players) do
		api.restore_player(name)
	end
end)

------------------------------------------------------------------------
-- The tool
------------------------------------------------------------------------

local last_use = {}
api._last_use = last_use

--- Fire the horn from `user`. Returns the list of stunned objects.
function api.blast(user)
	local origin = eye_of(user)
	local dir = user:get_look_dir()
	minetest.sound_play("trainhorn_gun_blast",
		{pos = origin, gain = 1.0, max_hear_distance = 48}, true)

	local candidates = {}
	for _, obj in ipairs(minetest.get_objects_inside_radius(origin, cfg.range + 2)) do
		if stunnable(obj, user) then
			-- the object counts if its body centre or its head is in the cone
			local best
			for _, p in ipairs(aim_points_of(obj) or {}) do
				local ok, d = cone.in_cone(origin, dir, p, cfg.range, cfg.cone_angle)
				if ok and (not best or d < best.d) then
					best = {pos = p, d = d}
				end
			end
			if best then
				candidates[#candidates + 1] = {pos = best.pos, obj = obj}
			end
		end
	end

	local hit = {}
	for _, h in ipairs(cone.select(origin, dir, candidates, cfg.range, cfg.cone_angle)) do
		local obj = h.item.obj
		if not cfg.require_los or minetest.line_of_sight(origin, h.item.pos) then
			local strength = falloff.stun_strength(h.distance, cfg.range,
				{min_strength = cfg.min_strength})
			if api.stun(obj, strength, dir, user) then
				hit[#hit + 1] = obj
			end
		end
	end
	return hit
end

local function on_use(itemstack, user)
	if not user or not user:is_player() then return itemstack end
	local name = user:get_player_name()
	local t = now()
	if last_use[name] and t - last_use[name] < cfg.cooldown then
		return itemstack
	end
	last_use[name] = t
	api.blast(user)
	local creative = minetest.is_creative_enabled
		and minetest.is_creative_enabled(name)
	if cfg.uses > 0 and not creative then
		itemstack:add_wear(math.ceil(65535 / cfg.uses))
	end
	return itemstack
end

minetest.register_tool(modname .. ":horn_gun", {
	description = S("Portable Train Horn Gun") .. "\n"
		.. S("Left-click: horn blast that stuns (slows) mobs and players in front of you"),
	short_description = S("Portable Train Horn Gun"),
	inventory_image = "trainhorn_gun_horn_gun.png",
	wield_scale = {x = 1.5, y = 1.5, z = 1},
	stack_max = 1,
	range = 4,
	groups = {tool = 1},
	on_use = on_use,
	sound = {breaks = "default_tool_breaks"},
})
api._on_use = on_use

minetest.register_on_leaveplayer(function(player)
	last_use[player:get_player_name()] = nil
end)

------------------------------------------------------------------------
-- Crafting (only with Minetest Game / any game providing `default`)
------------------------------------------------------------------------

if minetest.get_modpath("default") then
	minetest.register_craft({
		output = modname .. ":horn_gun",
		recipe = {
			{"", "default:steel_ingot", "default:steel_ingot"},
			{"default:mese_crystal_fragment", "default:copper_ingot", "default:steel_ingot"},
			{"default:stick", "", ""},
		},
	})
end

------------------------------------------------------------------------
-- /victoryhorn and the optional kill hook
------------------------------------------------------------------------

local last_victory = {}
api._last_victory = last_victory

--- Play the victory horn at a player's position, rate-limited per player.
-- Returns ok, message.
function api.victory(player)
	local name = player:get_player_name()
	local t = now()
	local last = last_victory[name]
	if last and t - last < cfg.victory_cooldown then
		return false, S("The victory horn needs @1 more seconds.",
			tostring(math.ceil(cfg.victory_cooldown - (t - last))))
	end
	last_victory[name] = t
	minetest.sound_play("trainhorn_gun_victory",
		{pos = player:get_pos(), gain = 1.0, max_hear_distance = 64}, true)
	return true, S("GOAL! Victory horn!")
end

minetest.register_chatcommand("victoryhorn", {
	description = S("Sound the stadium victory horn (rate limited)"),
	privs = {interact = true},
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, S("You must be online to use the victory horn.")
		end
		return api.victory(player)
	end,
})

if cfg.victory_on_kill then
	minetest.register_on_dieplayer(function(victim, reason)
		local killer = reason and reason.object
		if killer and killer:is_player() and killer ~= victim then
			api.victory(killer)
		end
	end)
end
