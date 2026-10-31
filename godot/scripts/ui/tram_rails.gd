## Tram rails laid in a street stage's carriageway (visual only, no collision): a dark rail bed with two steel rails
## on it, sitting a hair above the tarmac. The runs come from the baked "tram_rails" of <key>_env.json
## (tools/build_street_tracks.py): [s, d, s, d, ...] in the track's own frame (distance along, offset across).
class_name TramRails
extends RefCounted

const GAUGE := 1.435 ## m between the rail heads
const RAIL_W := 0.09
const BED_W := 3.1
const LIFT_BED := 0.018 ## m above the road surface (the depth buffer needs a few mm at distance)
const LIFT_RAIL := 0.03

## Adds a MeshInstance3D "TramRails" to `root`. `world` is the race world (its _road_y and world_center place it).
static func build(root: Node3D, world: Node3D, track: Track, runs: Array) -> MeshInstance3D:
	if runs.is_empty():
		return null
	var bed := _Strip.new()
	var rails := _Strip.new()
	var c: Vector2 = world.world_center
	for run: Array in runs:
		var n := run.size() / 2
		if n < 2:
			continue
		var pos: Array[Vector3] = []
		for i in n:
			var s := float(run[i * 2])
			var d := float(run[i * 2 + 1])
			var cx := track.sample(track.X, s) + track.sample(track.NX, s) * d - c.x
			var cz := track.sample(track.Y, s) + track.sample(track.NY, s) * d - c.y
			pos.append(Vector3(cx, world._road_y(s) + track.bank_rise(s, d), cz))
		for i in n:
			var a := pos[maxi(i - 1, 0)]
			var b := pos[mini(i + 1, n - 1)]
			var t := Vector2(b.x - a.x, b.z - a.z)
			if t.length() < 1e-4:
				continue
			t = t.normalized()
			var perp := Vector3(-t.y, 0.0, t.x)
			var p := pos[i]
			bed.add(p + perp * BED_W * 0.5 + Vector3.UP * LIFT_BED, p - perp * BED_W * 0.5 + Vector3.UP * LIFT_BED)
			for sgn: float in [-1.0, 1.0]:
				var q: Vector3 = p + perp * (GAUGE * 0.5 * sgn) + Vector3.UP * LIFT_RAIL
				rails.add_to(sgn, q + perp * RAIL_W * 0.5, q - perp * RAIL_W * 0.5)
		bed.end_run()
		rails.end_run()
	var mesh := ArrayMesh.new()
	bed.commit(mesh, _mat(Color("#34363a"), 0.95, 0.0))
	rails.commit(mesh, _mat(Color("#9aa0a6"), 0.35, 0.8))
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "TramRails"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi

static func _mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Collects quad strips: pairs of edge points per sample, broken into separate ribbons per run (and, for the
## rails, per side).
class _Strip:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var _last := {} ## side key -> index of the previous pair's first vertex, or -1
	func add(l: Vector3, r: Vector3) -> void:
		add_to(0.0, l, r)
	func add_to(key: float, l: Vector3, r: Vector3) -> void:
		var k := verts.size()
		verts.append(l)
		verts.append(r)
		var prev: int = _last.get(key, -1)
		if prev >= 0:
			idx.append_array(PackedInt32Array([prev, prev + 1, k, prev + 1, k + 1, k]))
		_last[key] = k
	func end_run() -> void:
		_last.clear()
	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if idx.is_empty():
			return
		var normals := PackedVector3Array()
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
