extends SceneTree
## Probe: loads two GLBs at run time (GLTFDocument, not the imported scene) and compares every mesh's blend-shape
## arrays (positions and normals), node by node. `godot --headless --path godot -s tests/_glb_blend_diff.gd -- A.glb B.glb`
## prints, per node, the surface/vertex counts, the blend-shape names and the largest position/normal difference.

func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		push_error("cannot load %s (%d)" % [path, err])
		return null
	return doc.generate_scene(st)

func _mx(d: Vector3) -> float:
	return maxf(maxf(absf(d.x), absf(d.y)), absf(d.z))

func _meshes(n: Node, out: Dictionary, all_names: Array = []) -> void:
	all_names.append(str(n.name))
	if n is ImporterMeshInstance3D or n is MeshInstance3D:
		out[n.name] = n
	for c in n.get_children():
		_meshes(c, out, all_names)

func _mesh_of(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	return null

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- A.glb B.glb")
		quit(1)
		return
	var ra := _load(args[0])
	var rb := _load(args[1])
	var ma := {}
	var mb := {}
	var na_all: Array = []
	var nb_all: Array = []
	_meshes(ra, ma, na_all)
	_meshes(rb, mb, nb_all)
	na_all.sort()
	nb_all.sort()
	print("NODES A=%d B=%d same_names=%s" % [na_all.size(), nb_all.size(), str(na_all == nb_all)])
	var worst_p := 0.0
	var worst_n := 0.0
	var bad := 0
	var names: Array = ma.keys()
	names.sort()
	for k in names:
		if not mb.has(k):
			print("MISSING in B: ", k)
			bad += 1
			continue
		var a: Mesh = _mesh_of(ma[k])
		var b: Mesh = _mesh_of(mb[k])
		if a == null or b == null:
			continue
		var line := "%s surfs=%d/%d shapes=%d/%d" % [k, a.get_surface_count(), b.get_surface_count(), a.get_blend_shape_count(), b.get_blend_shape_count()]
		var dp := 0.0
		var dn := 0.0
		var verts := 0
		var vb_tot := 0
		for s in a.get_surface_count():
			var sa := a.surface_get_arrays(s)
			var sb := b.surface_get_arrays(s)
			verts += (sa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			vb_tot += (sb[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if (sa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != (sb[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				bad += 1
			var ia: Material = a.surface_get_material(s)
			var ib: Material = b.surface_get_material(s)
			if (ia.resource_name if ia else "") != (ib.resource_name if ib else ""):
				bad += 1
				print("MATERIAL MISMATCH ", k, " surf ", s)
			var ba := a.surface_get_blend_shape_arrays(s)
			var bb := b.surface_get_blend_shape_arrays(s)
			for i in ba.size():
				var pa: PackedVector3Array = ba[i][Mesh.ARRAY_VERTEX]
				var pb: PackedVector3Array = bb[i][Mesh.ARRAY_VERTEX]
				for v in pa.size():
					dp = maxf(dp, _mx(pa[v] - pb[v]))
				var na = ba[i][Mesh.ARRAY_NORMAL]
				var nb = bb[i][Mesh.ARRAY_NORMAL]
				if na is PackedVector3Array and nb is PackedVector3Array:
					for v in (na as PackedVector3Array).size():
						dn = maxf(dn, _mx(na[v] - nb[v]))
		if a.get_surface_count() != b.get_surface_count() or a.get_blend_shape_count() != b.get_blend_shape_count() or verts != vb_tot:
			bad += 1
		print("%s verts=%d/%d dpos=%.5f dnrm=%.5f" % [line, verts, vb_tot, dp, dn])
		worst_p = maxf(worst_p, dp)
		worst_n = maxf(worst_n, dn)
	for k in mb.keys():
		if not ma.has(k):
			print("EXTRA in B: ", k)
			bad += 1
	print("WORST dpos=%.5f dnrm=%.5f missing/mismatch=%d" % [worst_p, worst_n, bad])
	ra.free()
	rb.free()
	quit(0)
