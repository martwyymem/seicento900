extends SceneTree
const CodeHash := preload("res://scripts/world/code_hash.gd")
func _initialize() -> void:
	var B := "res://scripts/world/town_builder.gd"
	var M := "res://scripts/world/town_map.gd"
	var t := Time.get_ticks_usec()
	var mem := CodeHash.members(B)
	print("members ", mem.size(), " in ", (Time.get_ticks_usec() - t) / 1000.0, " ms; map ", CodeHash.members(M).size())
	print(mem.has("build_buildings"), mem.has("hash2"), mem.has("KIND_CODE"), mem.has("models"), mem.has("_add_mesh"))
	for root in ["build_terrain", "build_roads", "build_rail", "build_buildings", "build_trees", "build_fences", "build_props"]:
		var a := Time.get_ticks_usec()
		var h := CodeHash.closure(B, [root], M, ["_load"])
		print("%-16s %s %.0f ms" % [root, h, (Time.get_ticks_usec() - a) / 1000.0])
	print(mem["hash2"])
	quit()
