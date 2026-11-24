## Prints where a car scene's imported mesh bytes go, per mesh: vertex, attribute, blend-shape, index and LOD data.
##   CAR=golf4 godot --headless --path godot -s tests/_car_mesh_budget.gd   (CAR=all for every catalogue car)
extends SceneTree

const KEYS := ["seicento", "golf4", "logan", "v50", "i20", "sandero", "focus", "zafira"]

func _initialize() -> void:
	var key := OS.get_environment("CAR")
	if key == "": key = "golf4"
	var grand := 0
	for k in (KEYS if key == "all" else [key]):
		grand += _report(k, key != "all")
	if key == "all":
		print("all cars: %.1f MB of mesh data" % (grand / 1048576.0))
	quit()

func _report(key: String, rows_out: bool) -> int:
	var root: Node = load("res://models/%s.glb" % key).instantiate()
	var sums := {"vertex": 0, "attribute": 0, "blend": 0, "index": 0, "lod": 0}
	var rows: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		if am == null: continue
		var mesh_sum := {"vertex": 0, "attribute": 0, "blend": 0, "index": 0, "lod": 0}
		var fmt := 0
		for s in am.get_surface_count():
			var d: Dictionary = RenderingServer.mesh_get_surface(am.get_rid(), s)
			fmt = d.get("format", 0)
			mesh_sum.vertex += (d.get("vertex_data", PackedByteArray()) as PackedByteArray).size()
			mesh_sum.attribute += (d.get("attribute_data", PackedByteArray()) as PackedByteArray).size()
			mesh_sum.blend += (d.get("blend_shape_data", PackedByteArray()) as PackedByteArray).size()
			mesh_sum.index += (d.get("index_data", PackedByteArray()) as PackedByteArray).size()
			for l in d.get("lods", []):
				mesh_sum.lod += (l.get("index_data", PackedByteArray()) as PackedByteArray).size()
		var tot := 0
		for c in sums: sums[c] += mesh_sum[c]; tot += mesh_sum[c]
		rows.append([tot, "%-18s shapes=%2d tangent=%s compressed=%s  vtx %6.0f  attr %5.0f  blend %7.0f  idx %5.0f  lod %5.0f KB" % [
			mi.name, am.get_blend_shape_count(), bool(fmt & Mesh.ARRAY_FORMAT_TANGENT), bool(fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES),
			mesh_sum.vertex / 1024.0, mesh_sum.attribute / 1024.0, mesh_sum.blend / 1024.0, mesh_sum.index / 1024.0, mesh_sum.lod / 1024.0]])
	root.free()
	if rows_out:
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in rows.slice(0, 12): print(r[1])
	var total := 0
	for c in sums: total += sums[c]
	print("%-9s %5.1f MB: vertex %.1f, attribute %.1f, blend shapes %.1f, index %.1f, LOD %.1f" % [key, total / 1048576.0,
		sums.vertex / 1048576.0, sums.attribute / 1048576.0, sums.blend / 1048576.0, sums.index / 1048576.0, sums.lod / 1048576.0])
	return total
