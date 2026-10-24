## Headless probe: builds the open world's buildings and landmarks and prints the time and triangle count.
##   godot --headless --path godot -s tests/_town_stats.gd
extends SceneTree

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var root3 := Node3D.new()
	var builder := TownBuilder.new(map, root3)
	for step in builder.steps():
		var t0 := Time.get_ticks_usec()
		(step[1] as Callable).call()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var tris := 0
		var g: Node = root3.get_child(root3.get_child_count() - 1)
		for mi in g.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m:
				for s in m.get_surface_count():
					var arr := m.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		print("%-20s %8.0f ms %9d tris (%s)" % [step[0], ms, tris, g.name])
	root3.free()
	quit()
