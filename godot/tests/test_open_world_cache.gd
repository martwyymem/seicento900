## The open world's mesh cache (TownBuilder.mesh_cache_dir): a warm build of every cached step (terrain, water, streets, railway,
## buildings, trees, fences, and the street furniture's placements) gives the same meshes and instances as the cold build that stored them; each step's stamp
## covers what that step reads and nothing else (editing the lamps leaves the buildings valid, editing the map's roads or
## _wall() does not); the map snapshot reads back equal; and the loading cover's car figures are about right.
extends RefCounted

const CODE_HASH := preload("res://scripts/world/code_hash.gd")
const BUILDER := "res://scripts/world/town_builder.gd"
const MAP := "res://scripts/world/town_map.gd"

var completed := false
## (one folder per process: suites running at the same time, other agents' or a parallel CI job's, share user://)
var DIR := "user://test_open_world_cache_%d" % OS.get_process_id()
const STEPS := ["build_terrain", "build_water", "build_roads", "build_rail", "build_buildings", "build_trees", "build_fences"]
const TAGS := ["terrain", "water", "streets", "rail", "buildings", "trees", "fences", "props", "festival"]
const GROUPS := ["Terrain", "Water", "Streets", "Railway", "Buildings", "Trees", "Garden Fences"]

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
		if not tag in ["props", "festival"] and not FileAccess.file_exists((cold.builder as TownBuilder)._cache_path(tag)):
			errors.append("the cold build stored no %s cache" % tag)
	if (cold.builder as TownBuilder).cache_log != ["terrain miss", "water miss", "streets miss", "rail miss", "buildings miss", "trees miss", "fences miss"]:
		errors.append("a cold build logs %s" % [(cold.builder as TownBuilder).cache_log])
	# the meshes are stored as the arrays MeshBatch made them of (no read-back from the GPU), and dropped from the meshes
	var stored_file := FileAccess.open((cold.builder as TownBuilder)._cache_path("terrain"), FileAccess.READ)
	var stored: Variant = null
	if stored_file and stored_file.get_buffer(TownBuilder.MESH_CACHE_MAGIC.length()) == TownBuilder.MESH_CACHE_MAGIC.to_ascii_buffer():
		stored = stored_file.get_var(false)
	if not stored is Array or (stored as Array).is_empty() or not (stored as Array)[0] is Dictionary:
		errors.append("the cache stores the terrain's meshes as ArrayMeshes (read back from the GPU), not as their arrays")
	if MeshBatch.keeps_arrays(true):
		errors.append("MeshBatch still keeps its arrays after the build")
	for n in (cold.world as Node3D).get_node("Terrain").get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).mesh.has_meta(MeshBatch.KEEP_META):
			errors.append("a built terrain mesh still holds its arrays")
			break
	var warm := _build(map)
	if (warm.builder as TownBuilder).cache_log != ["terrain hit", "water hit", "streets hit", "rail hit", "buildings hit", "trees hit", "fences hit"]:
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
	_props(errors)
	_festival(errors)
	_stamps(map, cold.builder, errors)
	# a different stamp (here the wall plan off) must not pick up these files
	var other := TownBuilder.new(map, Node3D.new())
	other.mesh_cache_dir = DIR
	other.wall_plan_enabled = false
	if other._cache_path("buildings") == (cold.builder as TownBuilder)._cache_path("buildings"):
		errors.append("the cache stamp ignores the wall plan")
	if other._cache_path("festival") == (cold.builder as TownBuilder)._cache_path("festival"):
		errors.append("the festival stamp ignores the wall plan")
	if other._cache_path("terrain") != (cold.builder as TownBuilder)._cache_path("terrain"):
		errors.append("the terrain's stamp depends on the wall plan")
	if not other._cached_meshes("buildings").is_empty():
		errors.append("a builder with another stamp read the cached buildings")
	if MeshBatch.keeps_arrays(true):
		errors.append("a cache miss in _cached_meshes left MeshBatch keeping its arrays")
	other.root.free()
	_crafted_files(map, errors)
	for w in [cold, warm]:
		(w.world as Node3D).free()
	_snapshot(map, errors)
	_clean()
	DirAccess.remove_absolute(DIR)
	completed = true
	return errors

const PWNED := "test_open_world_cache_pwned"
const CRAFTED_TRES := """[gd_resource type="Resource" load_steps=2 format=3]

[sub_resource type="GDScript" id="1"]
script/source = "extends Resource
func _init():
	Engine.set_meta(\\"%s\\", true)
"

[resource]
script = SubResource("1")
""" % PWNED

## A crafted file at a cache path (a .tres with a script, or an encoded object) is a miss and runs nothing: the cache
## is never read through ResourceLoader or with objects allowed. The payload is checked to run when it is loaded as a
## resource, so the test cannot pass on a payload that does nothing.
func _crafted_files(map: TownMap, errors: Array[String]) -> void:
	var dir := DIR + "/crafted"
	DirAccess.make_dir_recursive_absolute(dir)
	var b := TownBuilder.new(map, Node3D.new())
	b.mesh_cache_dir = dir
	Engine.remove_meta(PWNED)
	var f := FileAccess.open(b._cache_path("terrain"), FileAccess.WRITE)
	f.store_string(CRAFTED_TRES)
	f.close()
	# (an encoded object behind the right header is refused by get_var(false) too, but the engine prints an error for
	# it, which the suite runner counts: checked by hand, not here)
	if not b._cached_meshes("terrain").is_empty():
		errors.append("a crafted file at a cache path was read as a hit")
	if Engine.has_meta(PWNED):
		errors.append("a crafted file at a cache path ran its script")
	# (the same .tres loaded as a resource does run: the check above means something)
	var tres := dir + "/crafted.tres"
	f = FileAccess.open(tres, FileAccess.WRITE)
	f.store_string(CRAFTED_TRES)
	f.close()
	ResourceLoader.load(tres, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not Engine.has_meta(PWNED):
		errors.append("the crafted .tres did not run its script when loaded as a resource (the test proves nothing)")
	Engine.remove_meta(PWNED)
	for n in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)
	b.root.free()

## The street furniture (lamps, parked cars, shelters, signals): built on two maps of their own (it stands posts in the map,
## which the shared one must not get) after every other step, a warm build gives the same instances, lamp heads, lamp grid and
## collision posts as the cold one that stored them.
func _props(errors: Array[String]) -> void:
	var steps := STEPS + ["build_props"]
	var maps: Array[TownMap] = []
	var builds := []
	for i in 2:
		var m := TownMap.new()
		if not m._load("brzeszcze"):
			errors.append("the street furniture check could not load a map")
			return
		maps.append(m)
		var world := Node3D.new()
		var builder := TownBuilder.new(m, world)
		builder.mesh_cache_dir = DIR
		for step in steps:
			builder.call(step)
		builder.wait_for_stores()
		var rows: Array = []
		for n in world.get_node("Props").get_children():
			rows.append(_describe(n))
		builds.append({"world": world, "builder": builder, "rows": rows})
	var cold: TownBuilder = builds[0].builder
	var warm: TownBuilder = builds[1].builder
	if cold.cache_log.slice(-1) != ["props miss"] or warm.cache_log.slice(-1) != ["props hit"]:
		errors.append("the street furniture's cache logs %s then %s (props miss, then props hit expected)" % [cold.cache_log.slice(-1), warm.cache_log.slice(-1)])
	if (builds[0].rows as Array).size() < 10:
		errors.append("the cold build made %d street furniture nodes" % (builds[0].rows as Array).size())
	elif builds[0].rows != builds[1].rows:
		errors.append("the street furniture from the cache differs from the cold build's (%d nodes cold, %d warm, first difference at %d)" % [
			(builds[0].rows as Array).size(), (builds[1].rows as Array).size(), _first_diff(builds[0].rows, builds[1].rows)])
	if cold.lamp_spots.is_empty() or warm.lamp_spots != cold.lamp_spots or warm.lamp_dirs != cold.lamp_dirs or warm._lamp_cells != cold._lamp_cells:
		errors.append("a warm build's lamps (%d heads) differ from the cold build's (%d)" % [warm.lamp_spots.size(), cold.lamp_spots.size()])
	if warm.map._post_cells != cold.map._post_cells:
		errors.append("a warm build's collision posts differ from the cold build's")
	if warm._ranged.size() != cold._ranged.size():
		errors.append("a warm build registers %d distance-ranged instances, a cold one %d" % [warm._ranged.size(), cold._ranged.size()])
	# the placements are read from what the earlier steps built: the buildings' walls and the roads change them
	var reached := CODE_HASH.reached(BUILDER, TownBuilder.cache_spec("props").code, MAP, ["_load"])
	for name in ["_lamp_placements", "_parked_placements", "lamp_head", "_parked_clear", "_pavement_nudge", "_add_parked", "build_buildings", "build_roads", "_chunk_cells"]:
		if not name in reached.own:
			errors.append("the street furniture's fingerprint misses %s" % name)
	if "build_vegetation" in reached.own or "build_closures" in reached.own:
		errors.append("the street furniture's fingerprint covers steps it does not read")
	for b in builds:
		(b.world as Node3D).free()

## The festival dressing (main roads, busy corners, event gates): built on two maps of their own (it adds collision
## walls and posts to the map) after the earlier steps, a warm build gives the same instances, bunting/string-light
## meshes, stats, crowd zones, and collision walls/posts as the cold build that stored them.
func _festival(errors: Array[String]) -> void:
	var steps := STEPS + ["build_props", "build_landmarks"]
	var maps: Array[TownMap] = []
	var builds := []
	for i in 2:
		var m := TownMap.new()
		if not m._load("brzeszcze"):
			errors.append("the festival check could not load a map")
			return
		maps.append(m)
		var world := Node3D.new()
		var builder := TownBuilder.new(m, world)
		builder.mesh_cache_dir = DIR
		for step in steps:
			builder.call(step)
		builder.wait_for_stores()
		var rows: Array = []
		var fest := world.get_node_or_null("Landmarks/FestivalDressing")
		if fest:
			for n in fest.get_children():
				rows.append(_describe(n))
		builds.append({"world": world, "builder": builder, "rows": rows})
	var cold: TownBuilder = builds[0].builder
	var warm: TownBuilder = builds[1].builder
	if cold.cache_log.slice(-1) != ["festival miss"] or warm.cache_log.slice(-1) != ["festival hit"]:
		errors.append("the festival's cache logs %s then %s (festival miss, then festival hit expected)" % [cold.cache_log.slice(-1), warm.cache_log.slice(-1)])
	if (builds[0].rows as Array).size() < 20:
		errors.append("the cold build made %d festival nodes" % (builds[0].rows as Array).size())
	elif builds[0].rows != builds[1].rows:
		errors.append("the festival from the cache differs from the cold build's (%d nodes cold, %d warm, first difference at %d)" % [
			(builds[0].rows as Array).size(), (builds[1].rows as Array).size(), _first_diff(builds[0].rows, builds[1].rows)])
	var cf: FestivalDressing = cold.festival
	var wf: FestivalDressing = warm.festival
	if cf == null or wf == null:
		errors.append("the festival dressing was not created")
	else:
		if cf.stats.get("spectators", 0) < 1000 or cf.stats.get("barriers", 0) < 100:
			errors.append("the cold festival placed unexpectedly few props: %s" % [cf.stats])
		# every campaign mission start (two missions can share one) gets a long crowd and the organisers' trailer with its six
		# executives (suit-mode spectator shader: a second material that the night/proximity driver also updates)
		var trailers: int = cf.stats.get("mission_trailers", 0)
		if trailers < 6 or cf.stats.get("trailers", 0) != trailers or cf.stats.get("executives", 0) != trailers * FestivalDressing.EXEC_SPOTS.size():
			errors.append("the mission starts got %s trailers and %s executives: %s" % [trailers, cf.stats.get("executives", 0), cf.stats])
		if cf.stats.get("mission_crowd_people", 0) < 1500 or cf.stats.get("mission_crowd_people", 0) > FestivalDressing.START_CROWD_CAP * 1.4 * cf.stats.get("mission_starts", 0):
			errors.append("the mission start crowds hold %s spectators over %s starts" % [cf.stats.get("mission_crowd_people", 0), cf.stats.get("mission_starts", 0)])
		if cf.exec_mat == null or not is_equal_approx(float(cf.exec_mat.get_shader_parameter("suit")), 1.0) or cf.spectator_mat.get_shader_parameter("suit") != null:
			errors.append("the executives' suit material is not set up beside the spectators'")
		if wf.stats != cf.stats:
			errors.append("a warm festival's stats differ from the cold build's: %s vs %s" % [wf.stats, cf.stats])
		if wf.crowd_zones != cf.crowd_zones:
			errors.append("a warm festival's crowd_zones (%d) differ from the cold build's (%d)" % [wf.crowd_zones.size(), cf.crowd_zones.size()])
		if wf._placed_zones != cf._placed_zones or wf._placed_arches != cf._placed_arches:
			errors.append("a warm festival's placement guards differ from the cold build's")
		if wf.festival_pos != cf.festival_pos or wf.festival_face != cf.festival_face:
			errors.append("a warm festival's hub pose differs from the cold build's")
	if warm.map._post_cells != cold.map._post_cells or warm.map._post_cells.keys() != cold.map._post_cells.keys():
		errors.append("a warm festival build's collision posts differ from the cold build's")
	if warm.map._wall_cells != cold.map._wall_cells or warm.map._wall_cells.keys() != cold.map._wall_cells.keys():
		errors.append("a warm festival build's collision walls differ from the cold build's")
	if warm._ranged.size() != cold._ranged.size():
		errors.append("a warm festival build registers %d distance-ranged instances, a cold one %d" % [warm._ranged.size(), cold._ranged.size()])
	if warm.night_materials.size() != cold.night_materials.size():
		errors.append("a warm festival build registers %d night materials, a cold one %d" % [warm.night_materials.size(), cold.night_materials.size()])
	var spec := TownBuilder.cache_spec("festival")
	var map_roots: Array = ["_load"]
	map_roots.append_array(spec.get("map_code", []))
	var reached := CODE_HASH.reached(BUILDER, spec.code, MAP, map_roots)
	for name in ["build_landmarks", "_build_festival", "build_props", "build_buildings", "build_roads"]:
		if not name in reached.own:
			errors.append("the festival's fingerprint misses %s" % name)
	for name in ["in_play", "in_town", "walls_near", "posts_near", "add_wall", "add_post"]:
		if not name in reached.map:
			errors.append("the festival's fingerprint misses TownMap.%s" % name)
	if "build_vegetation" in reached.own or "build_closures" in reached.own or "build_horizon" in reached.own:
		errors.append("the festival's fingerprint covers steps it does not read")
	for b in builds:
		(b.world as Node3D).free()

func _clean() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))

func _build(map: TownMap) -> Dictionary:
	var world := Node3D.new()
	var builder := TownBuilder.new(map, world)
	builder.mesh_cache_dir = DIR
	builder.start_ahead() # (as the open world does: a cold build makes the buildings on another thread)
	for step in STEPS:
		builder.call(step)
	builder.wait_for_stores()
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
		return ["mm", mmi.multimesh.mesh.get_rid() != RID(), mmi.multimesh.instance_count, mmi.multimesh.use_colors, mmi.multimesh.use_custom_data,
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
	if bytes.is_empty():
		return ""
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
	var mesh_roots := {"terrain": "_terrain_meshes", "water": "_water_meshes", "streets": "_street_meshes", "rail": "_rail_meshes", "buildings": "_building_meshes", "trees": "_tree_records", "fences": "_fence_records"}
	var reached := {}
	for tag in mesh_roots:
		reached[tag] = CODE_HASH.reached(BUILDER, [mesh_roots[tag]], MAP, ["_load"])
		if (reached[tag].own as Array).is_empty() or not "_load" in reached[tag].map:
			errors.append("CodeHash reaches nothing for the %s step" % tag)
	var must := {"buildings": ["_wall", "_wall_plan", "_add_lod2_roof", "_open_runs", "_palette", "hash2", "KIND_CODE", "shaft_towers"],
		"trees": ["KIND_SPECIES", "_tree_dims", "_species_colour"], "streets": ["_build_pavements", "_style", "BRIDGE_GIRDER_DEPTH"],
		"rail": ["_bank_quad", "_clip_half"], "terrain": ["TERRAIN_STEP"], "water": ["WATER_TESS", "_chunk_of"], "fences": ["_doubled_fences", "_chunk_cells"]}
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
	# the terrain sinks the pond beds through TownMap.bed_vertex (its depth, bank and road-hold constants are TownMap's)
	for name in ["bed_vertex", "_build_bed_mask", "POND_DEPTH", "WATER_DROP", "BANK_SLOPE", "BANK_HOLD"]:
		if not name in reached.terrain.map:
			errors.append("the terrain's fingerprint misses TownMap.%s" % name)
	for name in ["ground", "road_lift", "kerb_at"]:
		if not name in reached.streets.map and name != "ground":
			errors.append("the streets' fingerprint misses TownMap.%s" % name)
	# (rail_bank is reached through TownMap._load's tunnel side walls since 2026-11-10: a harmless over-cover)
	if "signal_heads" in reached.buildings.map:
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
