## The open world's mesh cache (TownBuilder.mesh_cache_dir): a warm build of terrain, buildings and trees from the cache
## gives the same meshes and tree instances as the cold build that stored them; another stamp misses; and the
## loading cover's car figures are about right.
extends RefCounted

var completed := false
const DIR := "user://test_open_world_cache"
const STEPS := ["build_terrain", "build_buildings", "build_trees"]

func run() -> Array:
	var errors: Array[String] = []
	_cover_figures(errors)
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
	var cold := _build(map)
	for tag in ["terrain", "buildings", "trees"]:
		if not FileAccess.file_exists((cold.builder as TownBuilder)._cache_path(tag)):
			errors.append("the cold build stored no %s cache" % tag)
	var warm := _build(map)
	for group in ["Terrain", "Buildings", "Trees"]:
		var a: Array = cold.summary[group]
		var b: Array = warm.summary[group]
		if a.is_empty():
			errors.append("the cold build made no %s" % group)
		elif a != b:
			errors.append("%s from the cache differ: %d nodes cold, %d warm (first difference at %d)" % [group, a.size(), b.size(), _first_diff(a, b)])
	if (cold.builder as TownBuilder)._ranged.size() != (warm.builder as TownBuilder)._ranged.size():
		errors.append("a warm build registers %d distance-ranged instances, a cold one %d" % [
			(warm.builder as TownBuilder)._ranged.size(), (cold.builder as TownBuilder)._ranged.size()])
	if (warm.builder as TownBuilder)._impostor_mat == null:
		errors.append("a warm build leaves the tree impostor material unset")
	# a different stamp (here the wall plan off) must not pick up these files
	var other := TownBuilder.new(map, Node3D.new())
	other.mesh_cache_dir = DIR
	other.wall_plan_enabled = false
	if other._cache_path("buildings") == (cold.builder as TownBuilder)._cache_path("buildings"):
		errors.append("the cache stamp ignores the wall plan")
	if not other._cached_meshes("buildings").is_empty():
		errors.append("a builder with another stamp read the cached buildings")
	other.root.free()
	for w in [cold, warm]:
		(w.world as Node3D).free()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	completed = true
	return errors

func _build(map: TownMap) -> Dictionary:
	var world := Node3D.new()
	var builder := TownBuilder.new(map, world)
	builder.mesh_cache_dir = DIR
	for step in STEPS:
		builder.call(step)
	var summary := {}
	for group in ["Terrain", "Buildings", "Trees"]:
		var rows: Array = []
		var g := world.get_node_or_null(group)
		if g:
			for n in g.get_children():
				rows.append(_describe(n))
		summary[group] = rows
	return {"world": world, "builder": builder, "summary": summary}

## What must match between a cold and a warm build: vertex counts and bounds, the material, ranges and shadows,
## and for a MultiMesh its mesh and instance count.
static func _describe(n: Node) -> Array:
	if n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		return ["mm", mmi.multimesh.mesh.get_rid() != RID(), mmi.multimesh.instance_count, mmi.multimesh.use_colors,
			mmi.material_override != null, mmi.visibility_range_end, mmi.cast_shadow]
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := mi.mesh as ArrayMesh
		var counts: Array = []
		for s in m.get_surface_count():
			counts.append(m.surface_get_array_len(s))
			counts.append(m.surface_get_array_index_len(s))
		return ["mesh", counts, m.get_aabb().position.snapped(Vector3.ONE * 0.01), m.get_aabb().size.snapped(Vector3.ONE * 0.01),
			mi.material_override != null, mi.cast_shadow]
	return ["node", n.get_class()]

static func _first_diff(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return mini(a.size(), b.size())

func _cover_figures(errors: Array[String]) -> void:
	var stock := OpenWorldCover.car_stats(load("res://data/seicento.tres"))
	if stock.top_kmh < 130.0 or stock.top_kmh > 155.0:
		errors.append("the stock Seicento's top speed reads %.0f km/h (about 140 expected)" % stock.top_kmh)
	if stock.hp < 36.0 or stock.hp > 44.0:
		errors.append("the stock Seicento's power reads %.0f hp (39-40 expected)" % stock.hp)
	if absf(stock.kg - 815.0) > 1.0:
		errors.append("the stock Seicento weighs %.0f kg with the driver (815 expected)" % stock.kg)
	var hyper := OpenWorldCover.car_stats(Hypercar.spec())
	if hyper.top_kmh < 310.0 or hyper.top_kmh > 370.0:
		errors.append("the Hypercar Seicento's top speed reads %.0f km/h (about 345 measured)" % hyper.top_kmh)
	if OpenWorldCover.perf_class(stock)[0] != "D" or OpenWorldCover.perf_class(hyper)[0] != "X":
		errors.append("cover classes: stock %s, hypercar %s (D and X expected)" % [OpenWorldCover.perf_class(stock)[0], OpenWorldCover.perf_class(hyper)[0]])
