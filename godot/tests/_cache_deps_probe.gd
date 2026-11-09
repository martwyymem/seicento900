## Headless, slow (minutes): checks TownBuilder.cache_spec(). For every section of the baked map and every cached step that does not list it,
## empties the section, rebuilds the step and compares it with the unmodified build; any difference means the step reads the section.
##   godot --headless --path godot -s tests/_cache_deps_probe.gd [-- section,section]   (prints as it goes)
extends SceneTree

const FUNCS := {"terrain": "_terrain_meshes", "streets": "_street_meshes", "rail": "_rail_meshes", "buildings": "_building_meshes"}

func _initialize() -> void:
	var raw0 = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/brzeszcze.json"))
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		only = a.split(",")
	var base := _fingerprints(_map_of(raw0))
	print("base: ", base)
	var bad := 0
	for section in raw0:
		if not only.is_empty() and not section in only:
			continue
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/brzeszcze.json"))
		var v = raw[section]
		if v is Array and not (v as Array).is_empty() and (v[0] is float or v[0] is int) and (v as Array).size() <= 4:
			v[0] = float(v[0]) + 1.0 # bounds, extent, origin: the loader needs them, so nudge instead of emptying
		elif section == "terrain":
			continue # every step lists it
		else:
			raw[section] = [] if v is Array else ({} if v is Dictionary else "")
		var tags: Array = []
		for tag in TownBuilder.CACHED_TAGS:
			if not section in TownBuilder.cache_spec(tag).data:
				tags.append(tag)
		print("--- %s emptied; steps that do not list it: %s" % [section, tags])
		if tags.is_empty():
			continue
		var fps := _fingerprints(_map_of(raw), tags)
		for tag in tags:
			var same: bool = fps.get(tag, "?") == base[tag]
			print("   %-10s %s" % [tag, "same" if same else "DIFFERENT: the step reads this section"])
			if not same:
				bad += 1
	print("RESULT: %d undeclared dependencies" % bad)
	quit()

func _map_of(raw: Dictionary) -> TownMap:
	var m := TownMap.new()
	m.key = "brzeszcze"
	m.raw = raw
	m._from_raw()
	return m

func _fingerprints(map: TownMap, tags := TownBuilder.CACHED_TAGS) -> Dictionary:
	var out := {}
	var b := TownBuilder.new(map, Node3D.new())
	for tag in tags:
		var r
		match tag:
			"trees": r = b._tree_records(TownBuilder.SURROUNDINGS.tree_meshes())
			"fences": r = b._fence_records(b._model("Fence", b._fallback_fence))
			_: r = b.call(FUNCS[tag])
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		_feed(ctx, r)
		out[tag] = ctx.finish().hex_encode()
	return out

static func _feed(ctx: HashingContext, v) -> void:
	if v is Mesh:
		for s in (v as ArrayMesh).get_surface_count():
			_feed(ctx, (v as ArrayMesh).surface_get_arrays(s))
	elif v is Array:
		ctx.update(PackedInt32Array([(v as Array).size()]).to_byte_array())
		for e in v:
			_feed(ctx, e)
	elif v is PackedFloat32Array or v is PackedVector3Array or v is PackedVector2Array or v is PackedColorArray or v is PackedInt32Array:
		ctx.update(v.to_byte_array())
	elif v is Object:
		ctx.update(v.get_class().to_utf8_buffer())
	else:
		ctx.update(var_to_bytes(v))
