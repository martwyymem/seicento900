## Probe (headless): builds the race world for a track and reports where a mesh blocks the space over the road, a
## segment from each centreline sample to the next at 0.8 m and 2.5 m over the road (cars and the chase camera live there). MultiMesh props are
## not checked (headless reads their transforms as identity).
##   TRACK=s1_sprint godot --headless --path godot -s tests/_road_clear_probe.gd
extends SceneTree

const CELL := 8.0

func _initialize() -> void:
	await process_frame
	var key := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "s1_sprint"
	var tr: Track = Race.get_track(key)
	var world = load("res://scripts/ui/race_world.gd").new()
	root.add_child(world)
	world.set_track(tr)
	var grid := {} # cell -> [[a, b, c, name], ...]
	var count := 0
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var nm := String(m.name)
		if nm in ["RacingLine"]:
			continue
		var xf := m.global_transform
		var faces := m.mesh.get_faces()
		for f in range(0, faces.size(), 3):
			var a := xf * faces[f]
			var b := xf * faces[f + 1]
			var c := xf * faces[f + 2]
			var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
			var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
			if (hi - lo).length() > 400.0:
				continue
			for gx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for gz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var k := Vector2i(gx, gz)
					if not grid.has(k):
						grid[k] = []
					grid[k].append([a, b, c, nm])
			count += 1
	print("%s: %d faces indexed, %d samples, step %.1f m" % [key, count, tr.n, tr.step])
	var hits := {} # mesh name -> [first s, last s, samples]
	var runs: Array = []
	var in_run := false
	for i in tr.n:
		var s := i * tr.step
		var p: Array = tr.pos(s, 0.0)
		var x: float = p[0] - world.world_center.x
		var z: float = p[1] - world.world_center.y
		var y: float = world._road_y(s)
		var q: Array = tr.pos(s + tr.step, 0.0)
		var x2: float = q[0] - world.world_center.x
		var z2: float = q[1] - world.world_center.y
		var y2: float = world._road_y(s + tr.step)
		var hit_name := ""
		for hgt in (OS.get_environment("HEIGHTS").split_floats(",") if OS.get_environment("HEIGHTS") != "" else PackedFloat64Array([0.8, 2.5])): # through a car's body, and where the chase camera rides
			var from := Vector3(x, y + hgt, z)
			var to := Vector3(x2, y2 + hgt, z2)
			for t in grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), []):
				if Geometry3D.segment_intersects_triangle(from, to, t[0], t[1], t[2]) != null:
					hit_name = "%s@%.1fm" % [t[3], hgt]
					break
			if hit_name != "":
				break
		if hit_name != "":
			if not hits.has(hit_name):
				hits[hit_name] = [s, s, 0]
			hits[hit_name][1] = s
			hits[hit_name][2] += 1
			if not in_run:
				runs.append([s, s, hit_name])
				in_run = true
			runs[-1][1] = s
		else:
			in_run = false
	print("blocked samples by mesh: ", hits)
	print("blocked stretches (s from-to m, mesh): ", runs.slice(0, 20))
	quit()
