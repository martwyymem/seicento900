## Headless probe: plants the vegetation around a few spots of the open world and prints instance counts and times.
##   godot --headless --path godot -s tests/_vegetation_probe.gd
extends SceneTree

const SPOTS := {"wheat_a": Vector2(-1640, -60), "wheat_b": Vector2(-1720, 2080), "corn_a": Vector2(-200, -3740), "corn_b": Vector2(680, -4580), "town": Vector2(0, 0)}

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var veg: Node3D = preload("res://scripts/world/vegetation.gd").new()
	var ok: bool = veg.setup(map)
	print("setup ", ok, " land ", veg.land_w, "x", veg.land_h, " meshes ", veg.meshes.keys())
	if not ok:
		quit(1)
		return
	root.add_child(veg)
	for name in SPOTS:
		var p: Vector2 = SPOTS[name]
		var t0 := Time.get_ticks_usec()
		veg.update_around(p)
		var cells_n: int = veg.queue.size() / veg.LAYERS
		veg.plant_all()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("%-9s %4d cells %7.0f ms (%.1f ms/cell) %s" % [name, cells_n, ms, ms / maxf(1.0, cells_n), veg.counts])
		var tris := 0
		for kind in veg.counts:
			var m: Mesh = veg.meshes[kind]
			var arr := m.surface_get_arrays(0)
			var sum := 0
			for sf in m.get_surface_count():
				sum += (m.surface_get_arrays(sf)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			tris += sum * int(veg.counts[kind])
		print("          ~%d k triangles planted so far, %d cells alive" % [tris / 1000, veg.cells.size()])
	veg.free()
	quit()
