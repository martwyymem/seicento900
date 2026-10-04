## Scenery-in-the-way check (dev tool): for each TRACKS circuit, builds the world and lists the scenery (landmarks,
## buildings, trees, furniture, structures) with geometry on the road or its run-off at car height, i.e. that a car
## drives through. TRACKS=indy,monaco godot --path godot -s tests/_obstacle_probe.gd
## Not --headless: the dummy renderer keeps no MultiMesh transforms (every instance reads back as identity), so
## the trees, furniture and grandstand parts would all be tested at their node's origin.
extends SceneTree

## Ground-like surfaces a car is meant to drive on or over, and things that are not scenery.
const SKIP := ["Asphalt", "Runoff", "EdgeLines", "Kerbs", "StartLine", "RacingLine", "DetailedTerrain", "TerrainDEM",
	"FarLand", "Sea", "Water", "Pools", "Skidmarks", "SkidmarkRing", "PitLane", "Rain", "Cars", "RoadSupports"]
const LOW := 0.25 ## metres above the road where a car's body starts...
const HIGH := 1.45 ## ...and its roof
const STEP := 0.7 ## metres between the test points on a triangle
const CELL := 16.0 ## metres: hash cells of centreline samples
const NEAR := 4.0 ## metres: cells of the band round the circuit worth testing

var tr: Track
var world
var base := 0.0
var center := Vector2.ZERO
var reach := 0.0
var samples := {} ## Vector2i -> [sample index]
var near := {} ## Vector2i NEAR cells within reach of the road
var hits := {} ## node path -> {n, road, min_d, s: [], h}
var detail := OS.get_environment("DETAIL") == "1"

func _initialize() -> void:
	Brain.use_disk = false
	var keys: PackedStringArray = (OS.get_environment("TRACKS") if OS.get_environment("TRACKS") != "" else
			"indy,monaco").split(",")
	for key in keys:
		world = load("res://ui/race_world.tscn").instantiate()
		root.add_child(world)
		await process_frame
		var rs := RaceSettings.new()
		rs.track = key
		var t0 := Time.get_ticks_msec()
		world.set_race(Race.new(rs))
		var built := Time.get_ticks_msec() - t0
		tr = world.track
		base = world.elevation_base
		center = world.world_center
		reach = tr.half + tr.cfg.runoff
		_index()
		hits = {}
		t0 = Time.get_ticks_msec()
		_scan(world.track_root, "")
		print("OBSTACLES ", key, " (half ", snappedf(tr.half, 0.1), " m, run-off ", tr.cfg.runoff, " m; built ",
				built, " ms, scanned ", Time.get_ticks_msec() - t0, " ms): ", hits.size(), " nodes in the way")
		var rows := hits.keys()
		rows.sort_custom(func(a, b): return hits[a].road > hits[b].road or (hits[a].road == hits[b].road and hits[a].n > hits[b].n))
		for path in rows:
			var h: Dictionary = hits[path]
			var ss: Array = h.s
			ss.sort()
			print("  ", path, "  points ", h.n, " (", h.road, " on the road)  nearest ", snappedf(h.min_d, 0.1),
					" m from centre  S ", int(ss[0]), "..", int(ss[ss.size() - 1]), "  up to ", snappedf(h.h, 0.1), " m")
		world.queue_free()
		await process_frame
	quit()

func _index() -> void:
	samples = {}
	near = {}
	for i in tr.n:
		var c := Vector2i(floori(tr.X[i] / CELL), floori(tr.Y[i] / CELL))
		if not samples.has(c):
			samples[c] = []
		samples[c].append(i)
		var p := Vector2(tr.X[i], tr.Y[i])
		var nrm := Vector2(tr.NX[i], tr.NY[i])
		var tan := Vector2(-nrm.y, nrm.x)
		var d := -reach - NEAR
		while d <= reach + NEAR:
			for a in [-0.5, 0.0, 0.5]:
				var q: Vector2 = p + nrm * d + tan * (a * tr.step)
				near[Vector2i(floori(q.x / NEAR), floori(q.y / NEAR))] = true
			d += NEAR * 0.5

func _scan(node: Node, path: String) -> void:
	if node.name in SKIP:
		return
	var here := path + "/" + node.name
	if node is Node3D and not (node as Node3D).visible:
		return
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		_mesh((node as MeshInstance3D).mesh, (node as MeshInstance3D).global_transform, here)
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh:
		var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if mm.mesh:
			var box := mm.mesh.get_aabb()
			var g := (node as MultiMeshInstance3D).global_transform
			for k in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
				var xf := g * mm.get_instance_transform(k)
				if _box_near(xf * box):
					# DETAIL=1: each instance on its own line, with where it stands
					var at := Vector2(xf.origin.x + center.x, xf.origin.z + center.y)
					_mesh(mm.mesh, xf, here + ("#%d (%.1f, %.1f)" % [k, at.x, at.y] if detail else ""))
	for ch in node.get_children():
		_scan(ch, here)

## Whether a world box reaches the band round the road.
func _box_near(b: AABB) -> bool:
	var x0 := floori((b.position.x + center.x) / NEAR)
	var x1 := floori((b.end.x + center.x) / NEAR)
	var z0 := floori((b.position.z + center.y) / NEAR)
	var z1 := floori((b.end.z + center.y) / NEAR)
	if (x1 - x0 + 1) * (z1 - z0 + 1) > 4000:
		return true
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			if near.has(Vector2i(cx, cz)):
				return true
	return false

func _mesh(mesh: Mesh, xf: Transform3D, path: String) -> void:
	if not _box_near(xf * mesh.get_aabb()):
		return
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if idx.size() > 0 else verts.size()
		var w := PackedVector3Array()
		w.resize(verts.size())
		for v in verts.size():
			w[v] = xf * verts[v]
		for t in range(0, count - 2, 3):
			var a := w[idx[t] if idx.size() > 0 else t]
			var b := w[idx[t + 1] if idx.size() > 0 else t + 1]
			var c := w[idx[t + 2] if idx.size() > 0 else t + 2]
			var lo := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
			var hi := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
			if not _box_near(AABB(lo, hi - lo)):
				continue
			var edge := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
			var n := clampi(ceili(edge / STEP), 1, 300)
			for i in n + 1:
				for j in n + 1 - i:
					_point(a + (b - a) * (float(i) / n) + (c - a) * (float(j) / n), path)

func _point(p: Vector3, path: String) -> void:
	var x := p.x + center.x
	var z := p.z + center.y
	if not near.has(Vector2i(floori(x / NEAR), floori(z / NEAR))):
		return
	var cc := Vector2i(floori(x / CELL), floori(z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for k in samples.get(cc + Vector2i(dx, dz), []):
				var vx: float = x - tr.X[k]
				var vz: float = z - tr.Y[k]
				var along: float = -vx * tr.NY[k] + vz * tr.NX[k]
				if absf(along) > tr.step * 0.6:
					continue
				var lat: float = vx * tr.NX[k] + vz * tr.NY[k]
				if absf(lat) > reach:
					continue
				var road: float = tr.H[k] - base + 0.09 + tr.bank_rise(k * tr.step, lat)
				var h := p.y - road
				if h < LOW or h > HIGH:
					continue
				if not hits.has(path):
					hits[path] = {"n": 0, "road": 0, "min_d": INF, "s": [], "h": 0.0}
				var e: Dictionary = hits[path]
				e.n += 1
				if absf(lat) <= tr.half:
					e.road += 1
				e.min_d = minf(e.min_d, absf(lat))
				e.h = maxf(e.h, h)
				if e.s.size() < 400:
					e.s.append(k * tr.step)
				return
