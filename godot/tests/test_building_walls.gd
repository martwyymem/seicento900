## Building meshes in the open world: no two neighbouring buildings draw coplanar, overlapping walls (they z-fight and
## each has its own window layout, the "block of flats changes colour" flicker), the wall data the shader needs for corner
## quoins and cornices is in the vertex data, roof UVs follow the slope, and the baked detail textures share one texel
## density.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	_textures(errors)
	var raw := _overlaps(map, false, errors)
	var fixed := _overlaps(map, true, errors)
	if raw < 20:
		errors.append("only %d coplanar wall overlaps without the plan: the fixture no longer exercises it" % raw)
	if fixed > 0:
		errors.append("%d coplanar overlapping wall faces between neighbouring buildings remain (%d without the plan)" % [fixed, raw])
	completed = true
	return errors

func _textures(errors: Array[String]) -> void:
	var size := Vector2i.ZERO
	for n in ["wall", "brick", "roof"]:
		var path := "res://textures/buildings/building_%s.png" % n
		var tex := load(path) as Texture2D
		if tex == null:
			errors.append("%s did not load" % path)
			continue
		var s := Vector2i(tex.get_width(), tex.get_height())
		if size != Vector2i.ZERO and s != size:
			errors.append("%s is %s, the others %s: texel density differs" % [path, s, size])
		size = s
		var img := tex.get_image()
		var sum := 0.0
		for y in range(0, s.y, 7):
			for x in range(0, s.x, 7):
				sum += img.get_pixel(x, y).r
		if n != "brick" and (sum / float((s.x / 7 + 1) * (s.y / 7 + 1)) < 0.15):
			errors.append("%s is nearly black" % path)

## Builds the town's buildings, returns how many wall rectangles lie in one plane (within 2 cm), face one way and overlap
## by more than 10 cm both along the wall and in height, between two different buildings. Also checks the mesh data.
func _overlaps(map: TownMap, plan: bool, errors: Array[String]) -> int:
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	builder.wall_plan_enabled = plan
	builder.log_walls = true
	builder.build_buildings()
	var log: Array = builder.wall_log
	var cells := {}
	for i in log.size():
		var w: Array = log[i]
		var a: Vector2 = w[1]
		var b: Vector2 = w[2]
		var ln := a.distance_to(b)
		for k in int(ln / 5.0) + 2:
			var q := a.lerp(b, minf(float(k) * 5.0 / maxf(ln, 0.01), 1.0))
			var key := Vector2i(floori(q.x * 0.1), floori(q.y * 0.1))
			if not cells.has(key):
				cells[key] = {}
			cells[key][i] = true
	var seen := {}
	var count := 0
	for key in cells:
		var ids: Array = cells[key].keys()
		for x in ids.size():
			for y in range(x + 1, ids.size()):
				var i: int = mini(ids[x], ids[y])
				var j: int = maxi(ids[x], ids[y])
				var pair := i * 4000003 + j
				if seen.has(pair):
					continue
				seen[pair] = true
				if _coplanar(log[i], log[j]):
					count += 1
					if plan and count <= 3:
						errors.append("example: buildings %d and %d, wall %s / %s" % [log[i][0], log[j][0], log[i].slice(1, 7), log[j].slice(1, 7)])
	if plan:
		_mesh_data(root, errors)
	root.free()
	return count

func _coplanar(w: Array, v: Array) -> bool:
	if w[0] == v[0] or (w[7] as Vector2).dot(v[7]) < 0.99:
		return false
	var a: Vector2 = w[1]
	var b: Vector2 = w[2]
	var ln := a.distance_to(b)
	if ln < 0.1:
		return false
	var t := (b - a) / ln
	var n := Vector2(-t.y, t.x)
	var c: Vector2 = v[1]
	var d: Vector2 = v[2]
	if absf((c - a).dot(n)) > 0.02 or absf((d - a).dot(n)) > 0.02:
		return false
	var s0 := (c - a).dot(t)
	var s1 := (d - a).dot(t)
	var lo := maxf(0.0, minf(s0, s1))
	var hi := minf(ln, maxf(s0, s1))
	if hi - lo < 0.1:
		return false
	# the two quads are trapezoids: compare their heights at a few points of the shared stretch
	for f: float in [0.125, 0.375, 0.625, 0.875]:
		var s := lerpf(lo, hi, f)
		var p := a + t * s
		var y_lo := maxf(_lerp_at(w, p), _lerp_at(v, p))
		var y_hi := minf(_lerp_at(w, p, true), _lerp_at(v, p, true))
		if y_hi - y_lo > 0.05:
			return true
	return false

## Bottom (or top) of wall rectangle w above map point p, interpolated along it.
func _lerp_at(w: Array, p: Vector2, top := false) -> float:
	var a: Vector2 = w[1]
	var b: Vector2 = w[2]
	var f := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
	return lerpf(float(w[5 if top else 3]), float(w[6 if top else 4]), f)

## Wall vertices carry their wall's length in UV2.y and UV.x runs from 0 to it; roof triangles' UVs run along the eave
## and up the slope.
func _mesh_data(root: Node3D, errors: Array[String]) -> void:
	var walls := 0
	var bad_u := 0
	var steep := 0
	var bad_roof := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var arr := mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		for i in range(0, vs.size() - 2, 3):
			var code := uv2[i].y
			var len_dm := floorf(code / 20.0 + 0.001)
			var face := floorf((code - len_dm * 20.0) / 10.0 + 0.01)
			if face < 0.5 and len_dm > 0.0:
				walls += 1
				for k in 3:
					if uv[i + k].x < -0.01 or uv[i + k].x > len_dm * 0.1 + 0.05:
						bad_u += 1
			elif face > 0.5:
				var e1 := vs[i + 1] - vs[i]
				var e2 := vs[i + 2] - vs[i]
				var nrm := e1.cross(e2)
				if nrm.length() < 1e-3:
					continue
				nrm = nrm.normalized()
				if nrm.y < 0.0:
					nrm = -nrm
				if nrm.y > 0.95 or nrm.y < 0.2:
					continue
				# gradient of u and v over the triangle, in world space
				var du1 := uv[i + 1] - uv[i]
				var du2 := uv[i + 2] - uv[i]
				var m := Basis(e1, e2, nrm)
				if absf(m.determinant()) < 1e-4:
					continue
				var inv := m.inverse()
				var gu := inv.transposed() * Vector3(du1.x, du2.x, 0.0)
				var gv := inv.transposed() * Vector3(du1.y, du2.y, 0.0)
				steep += 1
				if absf(gu.y) > 0.05 * maxf(gu.length(), 1e-3) or gv.y < 0.0:
					bad_roof += 1
	if walls < 1000:
		errors.append("only %d wall triangles carry a wall length" % walls)
	if bad_u > 0:
		errors.append("%d wall vertices have UV.x outside 0..wall length" % bad_u)
	if steep < 100:
		errors.append("only %d pitched roof triangles checked" % steep)
	elif bad_roof > steep / 50:
		errors.append("%d of %d pitched roof triangles have UVs off the eave/slope axes" % [bad_roof, steep])
