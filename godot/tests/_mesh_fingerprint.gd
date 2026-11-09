## Headless: builds the open world's slow steps (CACHE=1: via the user:// mesh cache) and prints one hash per step group over every
## mesh array and MultiMesh buffer, to prove a refactor gives the same meshes.   godot --headless --path godot -s tests/_mesh_fingerprint.gd
extends SceneTree

var _buf_total := 0

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var world := Node3D.new()
	root.add_child(world)
	var builder := TownBuilder.new(map, world)
	if OS.get_environment("CACHE") != "":
		builder.mesh_cache_dir = OS.get_environment("CACHE")
	for s in builder.steps():
		if not s[0] in ["Terrain", "Streets", "Railway", "Buildings", "Woods and gardens", "Garden fences"]:
			continue
		var a := Time.get_ticks_usec()
		await (s[1] as Callable).call()
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		var group: Node = world.get_child(world.get_child_count() - 1)
		_feed(ctx, group)
		print("%-18s %7.0f ms  %s  %d nodes  %d buffer floats" % [s[0], ms, ctx.finish().hex_encode(), group.get_child_count(), _buf_total])
		_buf_total = 0
	quit()

func _feed(ctx: HashingContext, n: Node) -> void:
	for c in n.get_children():
		ctx.update(String(c.name).to_utf8_buffer())
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			ctx.update(PackedFloat32Array([mi.visibility_range_end, float(mi.cast_shadow)]).to_byte_array())
			ctx.update(str(mi.material_override.get_class() if mi.material_override else "").to_utf8_buffer())
			var m := mi.mesh
			if m is ArrayMesh:
				for s in m.get_surface_count():
					var arr := m.surface_get_arrays(s)
					for a in arr:
						if a is PackedVector3Array: ctx.update((a as PackedVector3Array).to_byte_array())
						elif a is PackedVector2Array: ctx.update((a as PackedVector2Array).to_byte_array())
						elif a is PackedColorArray: ctx.update((a as PackedColorArray).to_byte_array())
						elif a is PackedInt32Array: ctx.update((a as PackedInt32Array).to_byte_array())
			else:
				ctx.update(str(m.get_class()).to_utf8_buffer())
		elif c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			ctx.update(PackedFloat32Array([mmi.visibility_range_end, float(mmi.cast_shadow)]).to_byte_array())
			ctx.update(PackedInt32Array([mmi.multimesh.instance_count, int(mmi.multimesh.use_colors)]).to_byte_array())
			ctx.update(mmi.multimesh.buffer.to_byte_array())
			_buf_total += mmi.multimesh.buffer.size()
		_feed(ctx, c)
