## Headless: splits the Buildings step into the wall plan and the rest.
extends SceneTree
func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var world := Node3D.new()
	root.add_child(world)
	var tb := TownBuilder.new(map, world)
	var shafts := tb.shaft_towers()
	var not_drawn := {}
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		var extra: Dictionary = b[6] if b.size() > 6 and b[6] is Dictionary else {}
		if (extra.has("lm") and tb.has_model(String(extra.lm))) or shafts.hidden.has(bi):
			not_drawn[bi] = true
	var t2 := Time.get_ticks_usec()
	var plan := tb._wall_plan(not_drawn)
	print("wall plan %.0f ms" % [(Time.get_ticks_usec() - t2) / 1000.0])
	var t3 := Time.get_ticks_usec()
	tb.build_buildings()
	print("build_buildings (incl. plan) %.0f ms" % [(Time.get_ticks_usec() - t3) / 1000.0])
	quit()
