for _, n in ipairs({"steel_ingot", "copper_ingot", "mese_crystal_fragment", "stick"}) do
	minetest.register_craftitem("default:" .. n, {description = n})
end
