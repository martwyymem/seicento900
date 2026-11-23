## Headless: builds the open world's slow steps (CACHE=1: via the user:// mesh cache) and prints one hash per step group over every
## mesh array and MultiMesh buffer, to prove a refactor gives the same meshes.   godot --headless --path godot -s tests/_mesh_fingerprint.gd
## The "state" column hashes what the steps record besides meshes (cumulative, so a change shows from its step on): the
## buildings' collision faces (map.bld_faces, which build_buildings fills from the last element of _building_meshes()'s
## result, building index -> PackedFloat32Array) and rects, the street drawn_cones, the rail crossings and booms, the lamp
## placements (props step's lamp_spots / lamp_dirs / grid) and the festival dressing's records (its placements and
## instance transforms), every dictionary with its keys sorted.
extends SceneTree

## Every step runs except the horizon (only a backdrop). LEGACY=1 runs just the seven steps the first version of this probe
## covered, to compare with hashes recorded then: the mesh hashes of Buildings and later differ otherwise, because the
## Tunnels step (which changes what the buildings and props see) now runs before them.
const SKIP := ["Horizon"]
const LEGACY := ["Terrain", "Ponds and streams", "Streets", "Railway", "Buildings", "Woods and gardens", "Garden fences"]

var _buf_total := 0

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var world := Node3D.new()
	root.add_child(world)
	var builder := TownBuilder.new(map, world)
	if OS.get_environment("CACHE") != "":
		builder.mesh_cache_dir = OS.get_environment("CACHE")
		builder.start_ahead()
	for s in builder.steps():
		if s[0] in SKIP or (OS.get_environment("LEGACY") != "" and not s[0] in LEGACY):
			continue
		var a := Time.get_ticks_usec()
		await (s[1] as Callable).call()
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		var group: Node = world.get_child(world.get_child_count() - 1)
		_feed(ctx, group)
		print("%-18s %7.0f ms  %s  %d nodes  %d buffer floats  state %s" % [s[0], ms, ctx.finish().hex_encode(), group.get_child_count(), _buf_total, _state_hash(map, builder)])
		_buf_total = 0
	builder.wait_for_stores()
	quit()

func _feed(ctx: HashingContext, n: Node) -> void:
	for c in n.get_children():
		_upd(ctx, String(c.name).to_utf8_buffer())
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			_upd(ctx, PackedFloat32Array([mi.visibility_range_end, float(mi.cast_shadow)]).to_byte_array())
			_upd(ctx, str(mi.material_override.get_class() if mi.material_override else "").to_utf8_buffer())
			var m := mi.mesh
			if m is ArrayMesh:
				for s in m.get_surface_count():
					var arr := m.surface_get_arrays(s)
					for a in arr:
						if a is PackedVector3Array: _upd(ctx, (a as PackedVector3Array).to_byte_array())
						elif a is PackedVector2Array: _upd(ctx, (a as PackedVector2Array).to_byte_array())
						elif a is PackedColorArray: _upd(ctx, (a as PackedColorArray).to_byte_array())
						elif a is PackedInt32Array: _upd(ctx, (a as PackedInt32Array).to_byte_array())
			else:
				_upd(ctx, str(m.get_class()).to_utf8_buffer())
		elif c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			_upd(ctx, PackedFloat32Array([mmi.visibility_range_end, float(mmi.cast_shadow)]).to_byte_array())
			_upd(ctx, PackedInt32Array([mmi.multimesh.instance_count, int(mmi.multimesh.use_colors)]).to_byte_array())
			_upd(ctx, mmi.multimesh.buffer.to_byte_array())
			_buf_total += mmi.multimesh.buffer.size()
		_feed(ctx, c)

## One hash over the non-mesh records the steps leave in the map and the builder (see the header).
func _state_hash(map: TownMap, builder: TownBuilder) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	_hash_value(ctx, map.bld_faces)
	_hash_value(ctx, map.bld_rect)
	_hash_value(ctx, map.booms)
	_hash_value(ctx, builder.drawn_cones)
	_hash_value(ctx, builder.crossing_points)
	_hash_value(ctx, builder.lamp_spots)
	_hash_value(ctx, builder.lamp_dirs)
	_hash_value(ctx, builder._lamp_cells)
	_hash_value(ctx, builder.festival_pos)
	if builder.festival:
		for p in builder.festival.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(p.type) != TYPE_OBJECT:
				_upd(ctx, String(p.name).to_utf8_buffer())
				_hash_value(ctx, builder.festival.get(p.name))
	return ctx.finish().hex_encode()

## Feeds any value deterministically: dictionaries with their keys sorted, arrays in order, packed arrays as bytes, objects by class only.
func _hash_value(ctx: HashingContext, v: Variant) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys := d.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			_upd(ctx, PackedInt32Array([TYPE_DICTIONARY, keys.size()]).to_byte_array())
			for k in keys:
				_hash_value(ctx, k)
				_hash_value(ctx, d[k])
		TYPE_ARRAY:
			var a: Array = v
			_upd(ctx, PackedInt32Array([TYPE_ARRAY, a.size()]).to_byte_array())
			for e in a:
				_hash_value(ctx, e)
		TYPE_OBJECT:
			_upd(ctx, str(v.get_class() if v else "null").to_utf8_buffer())
		_:
			_upd(ctx, var_to_bytes(v))

## HashingContext.update errors on an empty buffer (an unnamed node, a blank mesh array): nothing to feed then.
func _upd(ctx: HashingContext, bytes: PackedByteArray) -> void:
	if not bytes.is_empty():
		ctx.update(bytes)
