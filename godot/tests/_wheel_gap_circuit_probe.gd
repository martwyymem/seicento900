## Probe (headless): the car's tyre-bottom gap to the drawn road on race circuits. For each track in TRACKS (comma
## list, default a spread of circuits), a car at lateral offsets across the road every ~STEP metres, placed and tilted
## the way RaceWorld places its visuals; gap = tyre bottom minus the highest drawn triangle under it within 0.3 m
## above (positive = floating, negative = sunk in). MultiMesh props aren't checked (headless reads them as identity).
##   TRACKS=gp,monza godot --headless --path godot -s tests/_wheel_gap_circuit_probe.gd
extends SceneTree

const CELL := 8.0
const CarVisual := preload("res://scripts/ui/race_car_visual.gd")
const STEP := 40.0

func _initialize() -> void:
	await process_frame
	var keys := (OS.get_environment("TRACKS") if OS.get_environment("TRACKS") != "" else "gp,monaco,monza,nordschleife,s1_sprint,tokyo").split(",")
	for key in keys:
		await _probe(key)
	print("DONE")
	quit()

func _probe(key: String) -> void:
	var tr: Track = Race.get_track(key)
	var world = load("res://scripts/ui/race_world.gd").new()
	root.add_child(world)
	world.set_track(tr)
	await process_frame
	var grid := {}
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not m.is_visible_in_tree() or String(m.name) in ["RacingLine"]:
			continue
		var xf := m.global_transform
		var faces := m.mesh.get_faces()
		for f in range(0, faces.size(), 3):
			var a := xf * faces[f]
			var b := xf * faces[f + 1]
			var c := xf * faces[f + 2]
			var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
			var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
			if (hi - lo).length() > 300.0:
				continue
			for gx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for gz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var k := Vector2i(gx, gz)
					if not grid.has(k):
						grid[k] = []
					grid[k].append([a, b, c, String(m.name)])
	var gaps := []
	var inner := [] # car centre well inside the asphalt
	var by_mesh := {}
	var s := 0.0
	while s < tr.L:
		for d in [-1.15, -0.7, 0.0, 0.7, 1.15]:
			var dd: float = d * tr.half * 0.8
			var pos: Array = tr.pos(s, dd)
			var p: Vector3 = world._car_pos(pos[0], pos[1], s, dd)
			var heading: float = tr.heading(s)
			var grade := atan(tr.sample(tr.GRADE, s) * world.ALTITUDE_SCALE)
			var basis: Basis = world._surface_tilt(s, dd) * Basis(Vector3.UP, -heading - PI / 2.0) * Basis(Vector3.RIGHT, grade)
			for spot in CarVisual.WHEEL_SPOTS:
				var bottom: Vector3 = p + basis * (Vector3(spot.x, spot.y - CarVisual.WHEEL_RADIUS, spot.z))
				var best := -INF
				var best_name := ""
				for t in grid.get(Vector2i(floori(bottom.x / CELL), floori(bottom.z / CELL)), []):
					var y := _tri_y(t[0], t[1], t[2], bottom.x, bottom.z)
					if is_nan(y) or y > bottom.y + 0.3:
						continue
					if y > best:
						best = y
						best_name = t[3]
				if best > -INF:
					gaps.append(bottom.y - best)
					if absf(d) < 1.0:
						inner.append(bottom.y - best)
					by_mesh[best_name] = int(by_mesh.get(best_name, 0)) + 1
		s += STEP
	gaps.sort()
	inner.sort()
	print("  on the asphalt (|d| <= 0.7 of the half-width): wheels %d min %.3f p5 %.3f median %.3f p95 %.3f max %.3f" % [inner.size(), inner[0], inner[inner.size() / 20], inner[inner.size() / 2], inner[inner.size() * 19 / 20], inner[-1]])
	print("%-12s wheels %4d gap to drawn surface (m): min %.3f p5 %.3f median %.3f p95 %.3f max %.3f   under the tyre: %s" % [key, gaps.size(), gaps[0], gaps[gaps.size() / 20], gaps[gaps.size() / 2], gaps[gaps.size() * 19 / 20], gaps[-1], by_mesh])
	world.queue_free()
	await process_frame

func _tri_y(a: Vector3, b: Vector3, c: Vector3, x: float, z: float) -> float:
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 1e-9:
		return NAN
	var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
	var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
	var l3 := 1.0 - l1 - l2
	if l1 < -1e-6 or l2 < -1e-6 or l3 < -1e-6:
		return NAN
	return l1 * a.y + l2 * b.y + l3 * c.y
