-- Integration smoke test: loads init.lua against a mocked `minetest` API,
-- registers the tool, fires it at fake objects and checks stun + restore.
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local H = dofile(here .. "harness.lua")
local test, eq, truthy, falsy = H.test, H.eq, H.truthy, H.falsy

------------------------------------------------------------------------
-- Mock engine
------------------------------------------------------------------------

local function new_world(setting_overrides)
	local W = {
		time = 1000, tools = {}, crafts = {}, commands = {}, sounds = {},
		timers = {}, objects = {}, online = {}, walls = {},
		cb = {leave = {}, die = {}, respawn = {}, shutdown = {}, globalstep = {}},
		settings = setting_overrides or {}, modpaths = {trainhorn_gun = H.modpath},
	}
	local settings = {}
	function settings:get(k) local v = W.settings[k]; return v ~= nil and tostring(v) or nil end
	function settings:get_bool(k, def)
		local v = W.settings[k]
		if v == nil then return def end
		return v == true or v == "true"
	end
	local mt = {settings = settings}
	function mt.get_current_modname() return "trainhorn_gun" end
	function mt.get_modpath(n) return W.modpaths[n] end
	function mt.get_translator()
		return function(s, ...)
			local args = {...}
			return (s:gsub("@(%d)", function(i) return args[tonumber(i)] end))
		end
	end
	function mt.get_us_time() return math.floor(W.time * 1e6) end
	function mt.register_tool(n, def) W.tools[n] = def end
	function mt.register_craft(c) W.crafts[#W.crafts + 1] = c end
	function mt.register_chatcommand(n, def) W.commands[n] = def end
	function mt.register_globalstep(f) table.insert(W.cb.globalstep, f) end
	function mt.register_on_leaveplayer(f) table.insert(W.cb.leave, f) end
	function mt.register_on_dieplayer(f) table.insert(W.cb.die, f) end
	function mt.register_on_respawnplayer(f) table.insert(W.cb.respawn, f) end
	function mt.register_on_shutdown(f) table.insert(W.cb.shutdown, f) end
	function mt.sound_play(name, params, ephemeral)
		W.sounds[#W.sounds + 1] = {name = name, params = params, ephemeral = ephemeral}
	end
	function mt.after(delay, fn, ...)
		W.timers[#W.timers + 1] = {at = W.time + delay, fn = fn, args = {...}}
	end
	function mt.get_player_by_name(n) return W.online[n] end
	function mt.get_objects_inside_radius(p, r)
		local out = {}
		for _, o in ipairs(W.objects) do
			local q = o:get_pos()
			if q then
				local dx, dy, dz = q.x - p.x, q.y - p.y, q.z - p.z
				if math.sqrt(dx * dx + dy * dy + dz * dz) <= r then out[#out + 1] = o end
			end
		end
		return out
	end
	function mt.line_of_sight(a, b)
		for _, wz in ipairs(W.walls) do
			if (a.z - wz) * (b.z - wz) < 0 then return false end
		end
		return true
	end
	function mt.is_creative_enabled(n) return W.settings.creative_names
		and W.settings.creative_names[n] or false end
	W.mt = mt

	function W.advance(dt)
		W.time = W.time + dt
		local due = true
		while due do
			due = false
			table.sort(W.timers, function(x, y) return x.at < y.at end)
			local t = W.timers[1]
			if t and t.at <= W.time then
				table.remove(W.timers, 1)
				t.fn((unpack or table.unpack)(t.args))
				due = true
			end
		end
		for _, f in ipairs(W.cb.globalstep) do f(dt) end
	end
	function W.fire(list, ...) for _, f in ipairs(W.cb[list]) do f(...) end end
	function W.sounds_named(n)
		local c = 0
		for _, s in ipairs(W.sounds) do if s.name == n then c = c + 1 end end
		return c
	end
	return W
end

local function copy(v) return {x = v.x, y = v.y, z = v.z} end

local function fake_player(W, name, pos, look)
	local p = {name = name, pos = copy(pos), look = look or {x = 0, y = 0, z = 1},
		physics = {speed = 1, jump = 1, gravity = 1}, vel_added = {}, punched = 0}
	function p:is_player() return true end
	function p:get_player_name() return self.name end
	function p:get_pos() return self.removed and nil or copy(self.pos) end
	function p:get_look_dir() return self.look end
	function p:get_properties()
		return {eye_height = 1.5, collisionbox = {-0.3, 0, -0.3, 0.3, 1.7, 0.3}}
	end
	function p:get_physics_override() return {speed = self.physics.speed} end
	function p:set_physics_override(t) for k, v in pairs(t) do self.physics[k] = v end end
	function p:add_velocity(v) self.vel_added[#self.vel_added + 1] = v end
	function p:punch(_, _, caps) self.punched = self.punched + caps.damage_groups.fleshy end
	function p:get_luaentity() return nil end
	function p:get_armor_groups() return {fleshy = 100} end
	W.objects[#W.objects + 1] = p
	W.online[name] = p
	return p
end

local function fake_mob(W, entname, pos, armor)
	local m = {pos = copy(pos), vel = {x = 2, y = 0, z = 2}, ent = {name = entname},
		armor = armor or {fleshy = 100}, vel_added = {}, punched = 0}
	function m:is_player() return false end
	function m:get_pos() return self.removed and nil or copy(self.pos) end
	function m:get_properties() return {collisionbox = {-0.4, 0, -0.4, 0.4, 1, 0.4}} end
	function m:get_luaentity() return (not self.removed) and self.ent or nil end
	function m:get_armor_groups() return self.armor end
	function m:get_velocity() return copy(self.vel) end
	function m:set_velocity(v) self.vel = copy(v) end
	function m:add_velocity(v) self.vel_added[#self.vel_added + 1] = v end
	function m:punch(_, _, caps) self.punched = self.punched + caps.damage_groups.fleshy end
	W.objects[#W.objects + 1] = m
	return m
end

local function fake_stack()
	local s = {wear = 0}
	function s:add_wear(w) self.wear = self.wear + w end
	return s
end

local function load_mod(W)
	_G.minetest = W.mt
	_G.trainhorn_gun = nil
	dofile(H.modpath .. "/init.lua")
	return _G.trainhorn_gun
end

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

print("integration (mocked minetest API)")

test("registers tool, chat command; no craft without default", function()
	local W = new_world()
	local api = load_mod(W)
	local def = W.tools["trainhorn_gun:horn_gun"]
	truthy(def, "tool registered")
	eq(def.inventory_image, "trainhorn_gun_horn_gun.png")
	eq(type(def.on_use), "function")
	truthy(W.commands.victoryhorn, "chat command registered")
	eq(#W.crafts, 0, "no recipe without default")
	eq(api.config.range, 8); eq(api.config.cone_angle, 30); eq(api.config.damage, 0)
end)

test("craft recipe registered when default is present", function()
	local W = new_world()
	W.modpaths.default = "/fake/default"
	load_mod(W)
	eq(#W.crafts, 1)
	eq(W.crafts[1].output, "trainhorn_gun:horn_gun")
end)

test("settings are read and clamped", function()
	local W = new_world({trainhorn_gun_range = 12, trainhorn_gun_cone_angle = 200,
		trainhorn_gun_damage = 2, trainhorn_gun_cooldown = "junk"})
	local api = load_mod(W)
	eq(api.config.range, 12); eq(api.config.cone_angle, 89)
	eq(api.config.damage, 2); eq(api.config.cooldown, 2)
end)

test("blast stuns only targets in the cone, restores after the stun", function()
	local W = new_world()
	local api = load_mod(W)
	local user = fake_player(W, "alice", {x = 0, y = 0, z = 0})
	local near_p = fake_player(W, "bob", {x = 0, y = 0, z = 2})
	local far_p = fake_player(W, "carol", {x = 0.5, y = 0, z = 7})
	local behind = fake_player(W, "dave", {x = 0, y = 0, z = -3})
	local side = fake_player(W, "erin", {x = 5, y = 0, z = 1})
	local mob = fake_mob(W, "mobs_animal:cow", {x = -0.5, y = 0.5, z = 4})
	local item = fake_mob(W, "__builtin:item", {x = 0, y = 0.5, z = 3})
	local npc = fake_mob(W, "my:immortal_npc", {x = 0, y = 0.5, z = 5}, {immortal = 1})

	local stack = fake_stack()
	W.tools["trainhorn_gun:horn_gun"].on_use(stack, user, {type = "nothing"})

	eq(W.sounds_named("trainhorn_gun_blast"), 1)
	truthy(api.is_stunned(near_p), "bob stunned")
	truthy(api.is_stunned(far_p), "carol stunned")
	truthy(api.is_stunned(mob), "cow stunned")
	falsy(api.is_stunned(user), "user not stunned")
	falsy(api.is_stunned(behind), "dave (behind) not stunned")
	falsy(api.is_stunned(side), "erin (side) not stunned")
	falsy(api.is_stunned(item), "dropped item ignored")
	falsy(api.is_stunned(npc), "immortal entity ignored")
	eq(W.sounds_named("trainhorn_gun_stun"), 3)

	-- slowdown: near target slower than far target, near close to 0.3
	truthy(near_p.physics.speed < far_p.physics.speed, "falloff: near slower")
	truthy(near_p.physics.speed >= 0.3 and near_p.physics.speed < 0.6, "near ~0.3-0.6")
	eq(user.physics.speed, 1)
	-- default damage 0 => no punches; knockback applied
	eq(near_p.punched, 0); eq(mob.punched, 0)
	eq(#near_p.vel_added, 1)
	truthy(stack.wear > 0, "wear applied")

	-- mobs are slowed by the globalstep
	W.advance(0.1)
	truthy(mob.vel.x < 2, "mob velocity damped")

	-- after the max duration everybody is restored
	W.advance(3.1)
	eq(near_p.physics.speed, 1, "bob restored")
	eq(far_p.physics.speed, 1, "carol restored")
	falsy(api.is_stunned(near_p)); falsy(api.is_stunned(mob))
	eq(mob.ent._trainhorn_stun_until, nil)
end)

test("far targets recover sooner than near ones", function()
	local W = new_world({trainhorn_gun_knockback = 0})
	local api = load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local near_p = fake_player(W, "n", {x = 0, y = 0, z = 1})
	local far_p = fake_player(W, "f", {x = 0, y = 0, z = 7.5})
	api.blast(user)
	eq(#near_p.vel_added, 0, "knockback disabled")
	W.advance(1.0)
	falsy(api.is_stunned(far_p), "far stun short")
	truthy(api.is_stunned(near_p), "near stun still active")
	W.advance(2.1)
	falsy(api.is_stunned(near_p))
end)

test("cooldown blocks a second blast within 2 s", function()
	local W = new_world()
	load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local on_use = W.tools["trainhorn_gun:horn_gun"].on_use
	local stack = fake_stack()
	on_use(stack, user, {}); on_use(stack, user, {})
	eq(W.sounds_named("trainhorn_gun_blast"), 1)
	W.advance(2.05)
	on_use(stack, user, {})
	eq(W.sounds_named("trainhorn_gun_blast"), 2)
end)

test("no wear in creative", function()
	local W = new_world({creative_names = {a = true}})
	load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local stack = fake_stack()
	W.tools["trainhorn_gun:horn_gun"].on_use(stack, user, {})
	eq(stack.wear, 0)
end)

test("restore on leave and on death; stale timer does not clobber", function()
	local W = new_world()
	local api = load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local v1 = fake_player(W, "v1", {x = 0, y = 0, z = 2})
	local v2 = fake_player(W, "v2", {x = 0.3, y = 0, z = 2})
	v2.physics.speed = 1.5 -- e.g. a sprint mod
	api.blast(user)
	truthy(v1.physics.speed < 1)
	W.fire("leave", v1)
	eq(v1.physics.speed, 1, "restored on leave")
	falsy(api.is_stunned(v1))
	W.fire("die", v2, {type = "fall"})
	eq(v2.physics.speed, 1.5, "restored to the saved speed on death")
	-- player rejoins and gets a fresh override; the old timer must not touch it
	v1.physics.speed = 1.2
	W.advance(5)
	eq(v1.physics.speed, 1.2)
end)

test("re-stun extends and keeps the original saved speed", function()
	local W = new_world({trainhorn_gun_cooldown = 0})
	local api = load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local v = fake_player(W, "v", {x = 0, y = 0, z = 2})
	api.blast(user)
	W.advance(2)
	api.blast(user)
	W.advance(2)
	truthy(api.is_stunned(v), "still stunned after the first timer")
	W.advance(1.5)
	eq(v.physics.speed, 1, "restored to original 1, not to a stunned value")
end)

test("players are not affected when pvp is off or setting disabled", function()
	for _, s in ipairs({{enable_pvp = false}, {trainhorn_gun_affect_players = false}}) do
		local W = new_world(s)
		local api = load_mod(W)
		local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
		local v = fake_player(W, "v", {x = 0, y = 0, z = 2})
		local mob = fake_mob(W, "x:mob", {x = 0, y = 0, z = 3})
		api.blast(user)
		falsy(api.is_stunned(v)); truthy(api.is_stunned(mob))
	end
end)

test("walls block the blast when line of sight is required", function()
	local W = new_world()
	local api = load_mod(W)
	W.walls = {3}
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local v1 = fake_player(W, "v1", {x = 0, y = 0, z = 2})
	local v2 = fake_player(W, "v2", {x = 0, y = 0, z = 5})
	api.blast(user)
	truthy(api.is_stunned(v1)); falsy(api.is_stunned(v2))
end)

test("configurable damage scales with distance (min 1)", function()
	local W = new_world({trainhorn_gun_damage = 4})
	local api = load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local n = fake_player(W, "n", {x = 0, y = 0, z = 1})
	local f = fake_player(W, "f", {x = 0, y = 0, z = 7.8})
	api.blast(user)
	eq(n.punched, 4); eq(f.punched, 1)
end)

test("removed entity is dropped from the stun table", function()
	local W = new_world()
	local api = load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local mob = fake_mob(W, "x:mob", {x = 0, y = 0, z = 3})
	api.blast(user)
	mob.removed = true
	W.advance(0.1)
	eq(api._entities[mob], nil)
end)

test("/victoryhorn plays and is rate limited", function()
	local W = new_world()
	load_mod(W)
	fake_player(W, "a", {x = 0, y = 0, z = 0})
	local cmd = W.commands.victoryhorn
	eq(cmd.privs.interact, true)
	local ok, msg = cmd.func("a", "")
	truthy(ok, msg)
	eq(W.sounds_named("trainhorn_gun_victory"), 1)
	local ok2, msg2 = cmd.func("a", "")
	falsy(ok2); truthy(msg2:find("30"), msg2)
	eq(W.sounds_named("trainhorn_gun_victory"), 1)
	W.advance(30.5)
	truthy(cmd.func("a", ""))
	eq(W.sounds_named("trainhorn_gun_victory"), 2)
	local ok3 = cmd.func("ghost", "")
	falsy(ok3, "offline player refused")
end)

test("optional victory on kill hook", function()
	local W = new_world({trainhorn_gun_victory_on_kill = true})
	load_mod(W)
	local k = fake_player(W, "k", {x = 0, y = 0, z = 0})
	local v = fake_player(W, "v", {x = 0, y = 0, z = 2})
	W.fire("die", v, {type = "punch", object = k})
	eq(W.sounds_named("trainhorn_gun_victory"), 1)
	W.fire("die", v, {type = "fall"})
	eq(W.sounds_named("trainhorn_gun_victory"), 1)
end)

test("shutdown restores everyone", function()
	local W = new_world()
	local api = load_mod(W)
	local user = fake_player(W, "a", {x = 0, y = 0, z = 0})
	local v = fake_player(W, "v", {x = 0, y = 0, z = 2})
	api.blast(user)
	W.fire("shutdown")
	eq(v.physics.speed, 1)
end)

H.finish("integration tests")
