## The open world's mesh cache (TownBuilder.mesh_cache_dir): a warm build of every cached step (terrain, streets, railway,
## buildings, trees, fences) gives the same meshes and instances as the cold build that stored them; each step's stamp
## covers what that step reads and nothing else (editing the lamps leaves the buildings valid, editing the map's roads or
## _wall() does not); the map snapshot reads back equal; and the loading cover's car figures are about right.
extends RefCounted

const CODE_HASH := preload("res://scripts/world/code_hash.gd")
const BUILDER := "res://scripts/world/town_builder.gd"
const MAP := "res://scripts/world/town_map.gd"

var completed := false
## (one folder per process: suites running at the same time, other agents' or a parallel CI job's, share user://)
var DIR := "user://test_open_world_cache_%d" % OS.get_process_id()
const STEPS := ["build_terrain", "build_roads", "build_rail", "build_buildings", "build_trees", "build_fences"]
const TAGS := ["terrain", "streets", "rail", "buildings", "trees", "fences"]
const GROUPS := ["Terrain", "Streets", "Railway", "Buildings", "Trees", "Garden Fences"]

func run() -> Array:
	var errors: Array[String] = []
	_cover_figures(errors)
	_code_hash(errors)
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	_clean()
	var cold := _build(map)
	for tag in TAGS:
		if not FileAccess.file_exists((cold.builder as TownBuilder)._cache_path(tag)):
			errors.append("the cold build stored no %s cache" % tag)
	if (cold.builder as TownBuilder).cache_log != ["terrain miss", "streets miss", "rail miss", "buildings miss", "trees miss", "fences miss"]:
		errors.append("a cold build logs %s" % [(cold.builder as TownBuilder).cache_log])
	var warm := _build(map)
	if (warm.builder as TownBuilder).cache_log != ["terrain hit", "streets hit", "rail hit", "buildings hit", "trees hit", "fences hit"]:
		errors.append("a warm build logs %s" % [(warm.builder as TownBuilder).cache_log])
	for group in GROUPS:
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
	var cold_materials: int = (cold.builder as TownBuilder).wet_materials.size()
	if (warm.builder as TownBuilder).wet_materials.size() != cold_materials or (warm.builder as TownBuilder).night_materials.size() != (cold.builder as TownBuilder).night_materials.size():
		errors.append("a warm build registers %d wet and %d night materials, a cold one %d and %d" % [
			(warm.builder as TownBuilder).wet_materials.size(), (warm.builder as TownBuilder).night_materials.size(), cold_materials, (cold.builder as TownBuilder).night_materials.size()])
	if (warm.builder as TownBuilder).crossing_points != (cold.builder as TownBuilder).crossing_points:
		errors.append("a warm build finds %d level crossings, a cold one %d" % [(warm.builder as TownBuilder).crossing_points.size(), (cold.builder as TownBuilder).crossing_points.size()])
	_stamps(map, cold.builder, errors)
	# a different stamp (here the wall plan off) must not pick up these files
	var other := TownBuilder.new(map, Node3D.new())
	other.mesh_cache_dir = DIR
	other.wall_plan_enabled = false
	if other._cache_path("buildings") == (cold.builder as TownBuilder)._cache_path("buildings"):
		errors.append("the cache stamp ignores the wall plan")
	if other._cache_path("terrain") != (cold.builder as TownBuilder)._cache_path("terrain"):
		errors.append("the terrain's stamp depends on the wall plan")
	if not other._cached_meshes("buildings").is_empty():
		errors.append("a builder with another stamp read the cached buildings")
	other.root.free()
	for w in [cold, warm]:
		(w.world as Node3D).free()
	_snapshot(map, errors)
	_clean()
	DirAccess.remove_absolute(DIR)
	completed = true
	return errors

func _clean() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))

func _build(map: TownMap) -> Dictionary:
	var world := Node3D.new()
	var builder := TownBuilder.new(map, world)
	builder.mesh_cache_dir = DIR
	for step in STEPS:
		builder.call(step)
	var summary := {}
	for group in GROUPS:
		var rows: Array = []
		var g := world.get_node_or_null(group)
		if g:
			for n in g.get_children():
				rows.append(_describe(n))
		summary[group] = rows
	return {"world": world, "builder": builder, "summary": summary}

## What must match between a cold and a warm build: vertex counts and bounds, the material, ranges and shadows,
## and for a MultiMesh its mesh and instance count and data.
static func _describe(n: Node) -> Array:
	if n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		return ["mm", mmi.multimesh.mesh.get_rid() != RID(), mmi.multimesh.instance_count, mmi.multimesh.use_colors,
			mmi.material_override != null, mmi.visibility_range_end, mmi.cast_shadow, mmi.multimesh.buffer.size(), _md5(mmi.multimesh.buffer.to_byte_array()), String(mmi.name) if not String(mmi.name).begins_with("@") else ""]
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := mi.mesh as ArrayMesh
		var counts: Array = []
		for s in m.get_surface_count():
			counts.append(m.surface_get_array_len(s))
			counts.append(m.surface_get_array_index_len(s))
		return ["mesh", counts, m.get_aabb().position.snapped(Vector3.ONE * 0.01), m.get_aabb().size.snapped(Vector3.ONE * 0.01),
			mi.material_override != null, mi.cast_shadow, mi.visibility_range_end]
	return ["node", n.get_class()]

static func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

static func _first_diff(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return mini(a.size(), b.size())

## Each step's stamp moves with the map sections it reads and with nothing else: a copy of the map with one section
## changed gives the other steps the stamps they had.
func _stamps(map: TownMap, builder: TownBuilder, errors: Array[String]) -> void:
	var covered := {}
	for tag in TAGS:
		for section in TownBuilder.cache_spec(tag).data:
			covered[section] = true
	for section in TownBuilder.UNCACHED_SECTIONS:
		covered[section] = true
	for section in map.raw:
		if not covered.has(section):
			errors.append("the baked map's section '%s' is in neither TownBuilder.cache_spec nor UNCACHED_SECTIONS: say which cached steps read it" % section)
	for section in TownBuilder.UNCACHED_SECTIONS:
		for tag in TAGS:
			if section in TownBuilder.cache_spec(tag).data:
				errors.append("section '%s' is listed as read by no cached step, but %s reads it" % [section, tag])
	# a map with only the raw data (the stamps read nothing else of it) and one section altered
	var base := {}
	for tag in TAGS:
		base[tag] = builder._stamp(tag)
	for section in map.raw:
		var copy := TownMap.new()
		copy.key = map.key
		copy.raw = map.raw.duplicate() # (shallow: the altered section is replaced, not edited)
		copy.raw[section] = [section, "changed"]
		var b := TownBuilder.new(copy, Node3D.new())
		b.mesh_cache_dir = DIR
		for tag in TAGS:
			var reads: bool = section in TownBuilder.cache_spec(tag).data
			var moved: bool = b._stamp(tag) != base[tag]
			if reads and not moved:
				errors.append("changing the map's '%s' leaves the %s stamp as it was" % [section, tag])
			elif moved and not reads:
				errors.append("changing the map's '%s' moves the %s stamp, which does not read it" % [section, tag])
		b.root.free()

## CodeHash: a step's fingerprint covers the members it reaches and no others.
func _code_hash(errors: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var write := func(name: String, text: String) -> String:
		var path := "%s/%s.gd" % [DIR, name]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		return path
	var src := "extends RefCounted\nconst K := 3 # three\nvar v := 1\nfunc root(a: int) -> int:\n\tvar steps := 2 # a local named like a member\n\treturn helper(a) + K + steps\nfunc helper(a: int) -> int:\n\treturn a * 2\nfunc other() -> String:\n\treturn \"#not a comment\"\nfunc steps() -> int:\n\treturn v\n"
	var base_path: String = write.call("a", src)
	var h0 := CODE_HASH.closure(base_path, ["root"], base_path)
	if h0 == "":
		errors.append("CodeHash found no source for a script it just wrote")
		return
	var got := CODE_HASH.reached(base_path, ["root"], base_path)
	if got.own != ["K", "helper", "root"]:
		errors.append("CodeHash reaches %s from root (K, helper, root expected: a local named like a member hides it)" % [got.own])
	var cases := {
		"a comment edit": [src.replace("# three", "# four").replace("\nvar v", "\n\n\nvar v"), true],
		"a change to an unrelated function": [src.replace("\"#not a comment\"", "\"#changed\""), true],
		"a change to the member variable only the other function reads": [src.replace("var v := 1", "var v := 2"), true],
		"a change to a function the root calls": [src.replace("a * 2", "a * 3"), false],
		"a change to a constant the root names": [src.replace("K := 3", "K := 4"), false],
		"a change to the root": [src.replace("+ steps", "+ steps + 1"), false]}
	var n := 0
	for what in cases:
		n += 1
		var path: String = write.call("b%d" % n, cases[what][0])
		var same: bool = CODE_HASH.closure(path, ["root"], path) == h0
		if same != cases[what][1]:
			errors.append("CodeHash: %s %s the fingerprint" % [what, "changed" if not same else "left"])
	# the real thing: what each step's fingerprint covers
	var mesh_roots := {"terrain": "_terrain_meshes", "streets": "_street_meshes", "rail": "_rail_meshes", "buildings": "_building_meshes", "trees": "_tree_records", "fences": "_fence_records"}
	var reached := {}
	for tag in mesh_roots:
		reached[tag] = CODE_HASH.reached(BUILDER, [mesh_roots[tag]], MAP, ["_load"])
		if (reached[tag].own as Array).is_empty() or not "_load" in reached[tag].map:
			errors.append("CodeHash reaches nothing for the %s step" % tag)
	var must := {"buildings": ["_wall", "_wall_plan", "_add_lod2_roof", "_open_runs", "_palette", "hash2", "KIND_CODE", "shaft_towers"],
		"trees": ["KIND_SPECIES", "_tree_dims", "_species_colour"], "streets": ["_build_pavements", "_style", "BRIDGE_GIRDER_DEPTH"],
		"rail": ["_bank_quad", "_clip_half"], "terrain": ["TERRAIN_STEP", "POND_DEPTH"], "fences": ["_doubled_fences", "_chunk_cells"]}
	var must_not := ["_build_lamps", "build_props", "build_vegetation", "_build_signals", "update_signals", "lamps_near", "_group", "_add_mesh",
		"_surface_material", "build_buildings", "build_trees", "build_roads", "steps"]
	for tag in must:
		for name in must[tag]:
			if not name in reached[tag].own:
				errors.append("the %s step's fingerprint misses %s" % [tag, name])
	for tag in reached:
		for name in must_not:
			if name in reached[tag].own:
				errors.append("the %s step's fingerprint covers %s, which it does not use" % [tag, name])
	if "_wall" in reached.trees.own or "_tree_records" in reached.buildings.own:
		errors.append("the tree and building fingerprints overlap where they should not")
	for name in ["ground", "road_lift", "kerb_at"]:
		if not name in reached.streets.map and name != "ground":
			errors.append("the streets' fingerprint misses TownMap.%s" % name)
	if "signal_heads" in reached.buildings.map or "rail_bank" in reached.buildings.map:
		errors.append("the buildings' fingerprint covers TownMap members it does not use")
	DirAccess.remove_absolute(DIR + "/a.gd")
	for i in n:
		DirAccess.remove_absolute("%s/b%d.gd" % [DIR, i + 1])

## The map snapshot reads back equal to the map it was made from, member by member.
func _snapshot(map: TownMap, errors: Array[String]) -> void:
	var dir := DIR + "/snap"
	map._save_snapshot(dir)
	var path := map._snapshot_path(map.key, dir)
	if path == "" or not FileAccess.file_exists(path):
		errors.append("TownMap stored no snapshot")
		return
	var back := TownMap.new()
	if not back._load_snapshot(map.key, dir):
		errors.append("TownMap could not read its snapshot back")
	else:
		for n in map._snapshot_vars():
			if typeof(map.get(n)) != typeof(back.get(n)) or var_to_bytes(map.get(n)) != var_to_bytes(back.get(n)):
				errors.append("snapshot member %s reads back different" % n)
		if back.section_hash("roads") != map.section_hash("roads"):
			errors.append("the snapshot lost the section hashes")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)

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
