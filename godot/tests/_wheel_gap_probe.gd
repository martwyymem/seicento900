## Probe (headless): where the car's tyres meet the road in the open world. Builds the town's terrain, streets and
## pavements, then at points along many roads, in the middle of a lane and at a pavement, compares the height the car
## physics rides at (FreeCar.support) with the height of the drawn surface (the highest mesh triangle under the point
## at or below the car), and the tyre-bottom gap of the four wheels of a car parked there (negative = sunk in).
##   godot --headless --path godot -s tests/_wheel_gap_probe.gd [-- samples-per-road-class]
extends SceneTree

const CELL := 8.0
const CarVisual := preload("res://scripts/ui/race_car_visual.gd")
var grid := {}

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var world := Node3D.new()
	root.add_child(world)
	var b := TownBuilder.new(map, world)
	b.build_terrain()
	b.build_roads()
	await process_frame
	var n_faces := 0
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var faces := m.mesh.get_faces()
		for f in range(0, faces.size(), 3):
			var a: Vector3 = faces[f]
			var bb: Vector3 = faces[f + 1]
			var c: Vector3 = faces[f + 2]
			var lo := Vector2(minf(a.x, minf(bb.x, c.x)), minf(a.z, minf(bb.z, c.z)))
			var hi := Vector2(maxf(a.x, maxf(bb.x, c.x)), maxf(a.z, maxf(bb.z, c.z)))
			if (hi - lo).length() > 300.0:
				continue
			for gx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				for gz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
					var k := Vector2i(gx, gz)
					if not grid.has(k):
						grid[k] = []
					grid[k].append([a, bb, c])
			n_faces += 1
	print("faces indexed ", n_faces)
	var args := OS.get_cmdline_user_args()
	var per := int(args[0]) if args.size() > 0 else 400
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var drive := FreeCar.new(map)
	var tyre_r := CarVisual.WHEEL_RADIUS
	var classes := {}
	var kerb_stats := []
	var checked := 0
	var order := range(map.road_pts.size())
	var step := maxi(1, order.size() / per)
	for ri in range(0, map.road_pts.size(), step):
		var pts := map.road_pts[ri]
		if pts.size() < 2 or map.road_bridge[ri] != 0 or not map.road_z[ri].is_empty():
			continue
		var i := rng.randi_range(0, pts.size() - 2)
		var a := pts[i]
		var d := pts[i + 1] - a
		if d.length() < 4.0:
			continue
		var t := rng.randf_range(0.2, 0.8)
		var p := a + d * t
		var heading := atan2(d.y, d.x)
		var lane := Vector2(-d.y, d.x).normalized() * map.road_w[ri] * 0.22
		p += lane
		drive.place(p, heading)
		for k in 150:
			drive.step(1.0 / 120.0, 0.0, 0.0, 0.0)
		var kind: String = map.road_kind[ri]
		var gaps := _wheel_gaps(drive, tyre_r)
		if not classes.has(kind):
			classes[kind] = []
		classes[kind].append(gaps)
		if OS.get_environment("VERBOSE") != "" and gaps.size() == 4 and (absf(gaps[0]) > 0.02 or absf(gaps[3]) > 0.02):
			var bs := drive.tilt * Basis(Vector3.UP, -heading - PI / 2.0)
			for sp in CarVisual.WHEEL_SPOTS:
				var w3: Vector3 = Vector3(drive.car.x, drive.z, drive.car.y) + bs * Vector3(sp.x, sp.y - tyre_r, sp.z)
				print("     wheel ", sp, " at ", w3, " tyre y ", snappedf(w3.y, 0.001), " mesh y ", snappedf(_mesh_y(w3.x, w3.z, w3.y), 0.001), " support ", snappedf(drive.support(w3.x, w3.z), 0.001), " ground ", snappedf(map.ground(w3.x, w3.z), 0.001), " lane dist ", snappedf(float(map.road_at(w3.x, w3.z).get("dist", 99.0)), 0.01))
			print("  ", kind, " ", p, " heading ", snappedf(heading, 0.01), " gaps FL FR RL RR ", gaps.map(func(g): return snappedf(g, 0.001)),
				" tilt n ", snappedf(drive.tilt.y.x, 0.001), snappedf(drive.tilt.y.z, 0.001), " centre gap ", snappedf(drive.z - _mesh_y(drive.car.x, drive.car.y, drive.z), 0.001))
		checked += 1
	for kind in classes:
		var all := []
		for g in classes[kind]:
			all.append_array(g)
		all.sort()
		print("road %-12s cars %3d  tyre-bottom gap to drawn surface (m): min %.3f p5 %.3f median %.3f p95 %.3f max %.3f" % [kind, classes[kind].size(), all[0], all[all.size() / 20], all[all.size() / 2], all[all.size() * 19 / 20], all[-1]])
	# pavements: a car parked half on the kerb
	var pave_gaps := []
	var tried := 0
	for pid in range(0, map.pave_polys.size(), maxi(1, map.pave_polys.size() / 200)):
		var poly: PackedVector2Array = map.pave_polys[pid]
		var c := Vector2.ZERO
		for q in poly:
			c += q / poly.size()
		if not Geometry2D.is_point_in_polygon(c, poly):
			continue
		drive.place(c, 0.0)
		drive.z = drive.support(c.x, c.y)
		for k in 150:
			drive.step(1.0 / 120.0, 0.0, 0.0, 0.0)
		var gp := _wheel_gaps(drive, tyre_r, true)
		if gp.size() < 4:
			continue # a car straddling the kerb: the car's one-point support can't touch with both heights
		pave_gaps.append_array(gp)
		tried += 1
		if OS.get_environment("VERBOSE") != "":
			print("   pavement car at ", c, " gaps ", gp.map(func(g): return snappedf(g, 0.001)), " centre on pavement ", map.pave_top_at(c.x, c.y) > 0.0, " tilt n ", drive.tilt.y)
	pave_gaps.sort()
	if not pave_gaps.is_empty():
		print("pavements cars %3d wheels %3d  tyre-bottom gap (m): min %.3f p5 %.3f median %.3f p95 %.3f max %.3f" % [tried, pave_gaps.size(), pave_gaps[0], pave_gaps[pave_gaps.size() / 20], pave_gaps[pave_gaps.size() / 2], pave_gaps[pave_gaps.size() * 19 / 20], pave_gaps[-1]])
	print("DONE")
	quit()

## The drawn surface height at (x, z): the highest triangle under the point that is not above ref + 1.5 m.
func _mesh_y(x: float, z: float, ref: float) -> float:
	var best := -INF
	for t in grid.get(Vector2i(floori(x / CELL), floori(z / CELL)), []):
		var y := _tri_y(t[0], t[1], t[2], x, z)
		if is_nan(y) or y > ref + 1.5:
			continue
		best = maxf(best, y)
	return best

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

## For each wheel: the tyre bottom's height over the drawn surface under it.
func _wheel_gaps(drive: FreeCar, tyre_r: float, pavement_only := false) -> Array:
	var h := drive.car.heading
	var basis := drive.tilt * Basis(Vector3.UP, -h - PI / 2.0)
	var origin := Vector3(drive.car.x, drive.z, drive.car.y)
	var out := []
	for spot in CarVisual.WHEEL_SPOTS:
		var bottom: Vector3 = origin + basis * (Vector3(spot.x, spot.y - tyre_r, spot.z))
		if pavement_only and (drive.map.pave_top_at(bottom.x, bottom.z) <= 0.0 or not drive.map.road_at(bottom.x, bottom.z).is_empty()):
			continue # only wheels that really stand on a pavement
		var sy := _mesh_y(bottom.x, bottom.z, bottom.y)
		if sy > -INF:
			out.append(bottom.y - sy)
			if pavement_only and absf(bottom.y - sy) > 0.08 and OS.get_environment("VERBOSE") != "":
				var mp := Vector2(bottom.x, bottom.z)
				print("   pave wheel at ", mp, " tyre y ", snappedf(bottom.y, 0.001), " mesh y ", snappedf(sy, 0.001), " ground ", snappedf(drive.map.ground(mp.x, mp.y), 0.001), " support ", snappedf(drive.support(mp.x, mp.y), 0.001), " centre support ", snappedf(drive.z, 0.001), " tilt n ", drive.tilt.y)
	return out
