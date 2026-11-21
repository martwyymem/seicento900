## Headless probe: measures the woods canopy outer rim height above terrain on every circuit with woods.
## Run: godot --headless --path godot -s tests/_canopy_rim_probe.gd
## Optional env: TRACKS=pszczyna,gp  QUALITY=2
extends SceneTree

const RACE_WORLD := preload("res://scripts/ui/race_world.gd")
const SURROUNDINGS := preload("res://scripts/ui/surroundings.gd")
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const RUN_TESTS := preload("res://tests/run_tests.gd")

func _initialize() -> void:
	await process_frame
	var keys := _all_track_keys()
	var filter := OS.get_environment("TRACKS")
	if filter != "":
		keys = PackedStringArray()
		for k in filter.split(","):
			var t := k.strip_edges()
			if t != "":
				keys.append(t)
	var quality := int(OS.get_environment("QUALITY")) if OS.get_environment("QUALITY") != "" else 2
	print("=== Canopy Rim Probe (quality=%d, circuits=%d) ===" % [quality, keys.size()])
	print("%-20s %6s %7s %7s %8s %8s %8s %8s %8s %8s" % [
		"circuit", "chunks", "tris", "rim_v", "min_m", "med_m", "p95_m", "max_m", "mid_max", ">0.5m"])
	var with_woods := 0
	var no_woods: PackedStringArray = []
	var overall_worst := -INF
	var overall_mid_worst := -INF
	var total_tris := 0
	var total_rim := 0
	var total_over := 0
	for key in keys:
		var res := _measure(key, quality)
		if res.get("tris", 0) == 0:
			no_woods.append(key)
			continue
		with_woods += 1
		total_tris += int(res.tris)
		total_rim += int(res.rim_verts)
		total_over += int(res.over_half)
		overall_worst = maxf(overall_worst, float(res.max_gap))
		overall_mid_worst = maxf(overall_mid_worst, float(res.mid_max))
		print("%-20s %6d %7d %7d %8.2f %8.2f %8.2f %8.2f %8.2f %8d" % [
			key, res.chunks, res.tris, res.rim_verts, res.min_gap, res.med_gap, res.p95_gap, res.max_gap, res.mid_max, res.over_half])
	print("-----------------------------------------------------------------------------------------------")
	print("Circuits with canopy: %d | total tris: %d | total rim verts: %d | >0.5m: %d | worst rim: %.2f m | worst edge mid: %.2f m" % [
		with_woods, total_tris, total_rim, total_over, overall_worst, overall_mid_worst])
	if not no_woods.is_empty():
		print("No canopy mesh: %s" % ", ".join(no_woods))
	await RUN_TESTS.release(self)
	quit(0)

static func _all_track_keys() -> PackedStringArray:
	var out: Array[String] = []
	var dir := DirAccess.open("res://data/tracks")
	if dir:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with("_env.json"):
				var key := fn.substr(0, fn.length() - "_env.json".length())
				if ResourceLoader.exists("res://data/tracks/%s.tres" % key):
					out.append(key)
			fn = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return PackedStringArray(out)

static func _measure(key: String, quality: int) -> Dictionary:
	var def := Track.load_def(key)
	var tr := Track.new(def)
	var world: Node3D = RACE_WORLD.new()
	world.assets = WORLD_ASSETS.new()
	world.quality = quality
	world.track = tr
	world.track_root = Node3D.new()
	world.add_child(world.track_root)
	var b := tr.bounds
	world.world_center = Vector2((b[0] + b[2]) * 0.5, (b[1] + b[3]) * 0.5)
	world.elevation_base = tr.h_min
	var sur = SURROUNDINGS.new()
	if not sur.setup(world):
		world.free()
		return {}
	world.surroundings = sur
	var ground := MeshInstance3D.new()
	world.track_root.add_child(ground)
	world._build_terrain(ground)
	var sur_root := Node3D.new()
	sur_root.name = "Surroundings"
	world.track_root.add_child(sur_root)
	sur._build_banking(sur_root)
	var inner: float = sur._clear_distance() + SURROUNDINGS.TREE_BAND[quality] - 25.0
	sur._build_canopy(sur_root, inner)
	var canopy: Node = sur_root.find_child("Canopy", false, false)
	var out := measure_canopy(canopy, sur, world.world_center)
	world.free()
	return out

## Measures open-boundary (rim) vertices and boundary-edge midpoints of a built Canopy node against ground_height.
static func measure_canopy(canopy: Node, sur: RefCounted, world_center: Vector2) -> Dictionary:
	if canopy == null:
		return {"chunks": 0, "tris": 0, "rim_verts": 0, "min_gap": 0.0, "med_gap": 0.0, "p95_gap": 0.0, "max_gap": 0.0, "mid_max": 0.0, "over_half": 0}
	var chunks := 0
	var tris := 0
	var vid_by_key := {} # Vector3i -> int
	var verts: Array[Vector3] = []
	var edge_count := {} # Vector2i(min_id, max_id) -> int
	for child in canopy.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		chunks += 1
		var arr: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0, arr.size() - 2, 3):
			tris += 1
			var ids := PackedInt32Array([0, 0, 0])
			for j in 3:
				var v := arr[i + j]
				var qk := Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))
				var id: int = vid_by_key.get(qk, -1)
				if id < 0:
					id = verts.size()
					vid_by_key[qk] = id
					verts.append(v)
				ids[j] = id
			for e in [[ids[0], ids[1]], [ids[1], ids[2]], [ids[2], ids[0]]]:
				var a: int = mini(e[0], e[1])
				var b: int = maxi(e[0], e[1])
				if a == b:
					continue
				var ek := Vector2i(a, b)
				edge_count[ek] = int(edge_count.get(ek, 0)) + 1
	var rim_ids := {}
	var mid_max := -INF
	for ek in edge_count:
		if int(edge_count[ek]) == 1:
			var a: int = ek.x
			var b: int = ek.y
			rim_ids[a] = true
			rim_ids[b] = true
			var m := (verts[a] + verts[b]) * 0.5
			var mg: float = sur.ground_height(m.x + world_center.x, m.z + world_center.y)
			mid_max = maxf(mid_max, m.y - mg)
	var gaps: Array[float] = []
	gaps.resize(rim_ids.size())
	var idx := 0
	var over_half := 0
	for id in rim_ids:
		var v := verts[id]
		var g: float = sur.ground_height(v.x + world_center.x, v.z + world_center.y)
		var gap := v.y - g
		gaps[idx] = gap
		idx += 1
		if gap > 0.5:
			over_half += 1
	if gaps.is_empty():
		return {"chunks": chunks, "tris": tris, "rim_verts": 0, "min_gap": 0.0, "med_gap": 0.0, "p95_gap": 0.0, "max_gap": 0.0, "mid_max": 0.0, "over_half": 0}
	gaps.sort()
	var n := gaps.size()
	return {
		"chunks": chunks,
		"tris": tris,
		"rim_verts": n,
		"min_gap": gaps[0],
		"med_gap": gaps[n / 2],
		"p95_gap": gaps[mini(n - 1, int(floor(n * 0.95)))],
		"max_gap": gaps[n - 1],
		"mid_max": mid_max,
		"over_half": over_half,
	}
