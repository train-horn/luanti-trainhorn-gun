-- In-engine checks for trainhorn_gun. Prints THTEST PASS / THTEST FAIL.
local failures = {}
local function check(cond, msg)
	if not cond then failures[#failures + 1] = msg end
end

minetest.register_entity("thtest_check:dummy", {
	initial_properties = {
		physical = false, collisionbox = {-0.4, 0, -0.4, 0.4, 1, 0.4},
		visual = "sprite", textures = {"blank.png"}, static_save = false,
	},
})

-- A stand-in "user" for blast(): real engine objects are the targets.
local fake_user = {
	get_pos = function() return {x = 0, y = 10, z = 0} end,
	get_properties = function() return {eye_height = 1.5} end,
	get_look_dir = function() return {x = 0, y = 0, z = 1} end,
	is_player = function() return true end,
	get_player_name = function() return "thtest" end,
}

local function finish()
	if #failures == 0 then
		minetest.log("action", "THTEST PASS")
	else
		minetest.log("error", "THTEST FAIL: " .. table.concat(failures, "; "))
	end
	minetest.request_shutdown("tests done", false, 0)
end

local function run()
	check(minetest.registered_tools["trainhorn_gun:horn_gun"], "tool not registered")
	local r = minetest.get_craft_recipe("trainhorn_gun:horn_gun")
	check(r and r.items, "craft recipe missing")
	check(minetest.registered_chatcommands.victoryhorn, "/victoryhorn missing")
	check(trainhorn_gun and trainhorn_gun.config.range == 8, "config not loaded")
	check(math.abs(trainhorn_gun.falloff.attenuation_db(2, 1) - 6.0206) < 1e-3, "falloff")

	local near = minetest.add_entity({x = 0, y = 10.5, z = 3}, "thtest_check:dummy")
	local behind = minetest.add_entity({x = 0, y = 10.5, z = -3}, "thtest_check:dummy")
	check(near and behind, "could not spawn test entities")
	if not (near and behind) then return finish() end
	near:set_velocity({x = 2, y = 0, z = 0})

	local hit = trainhorn_gun.blast(fake_user)
	check(#hit == 1 and hit[1] == near, "blast should hit exactly the entity in front, got "
		.. #hit)
	check(trainhorn_gun.is_stunned(near), "front entity not stunned")
	check(not trainhorn_gun.is_stunned(behind), "entity behind was stunned")

	minetest.after(0.5, function()
		local v = near:get_velocity()
		check(v and v.x < 1.0, "stunned entity not slowed: vx=" .. tostring(v and v.x))
		minetest.after(3.0, function()
			check(not trainhorn_gun.is_stunned(near), "stun did not expire")
			check(trainhorn_gun._entities[near] == nil, "stun state not cleared")
			finish()
		end)
	end)
end

minetest.after(1, function()
	local p = {x = 0, y = 10, z = 0}
	minetest.emerge_area(vector.subtract(p, 16), vector.add(p, 16), function(_, _, remaining)
		if remaining == 0 then
			minetest.forceload_block(p, true)
			minetest.after(0.5, run)
		end
	end)
end)
