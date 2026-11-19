std = "luajit"
max_line_length = 100
globals = {"trainhorn_gun"}
read_globals = {"minetest", "core", "vector"}
files["tests/"] = {
	std = "max",
	globals = {"minetest", "trainhorn_gun"},
	read_globals = {"unpack"},
	unused_args = false, -- mock methods keep the engine signatures (self, ...)
}
