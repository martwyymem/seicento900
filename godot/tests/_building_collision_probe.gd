## Building collision vs drawing (dev tool, headless): records every wall TownBuilder draws (_wall), then measures, per
## kind of building, the metres of collision edge (TownMap.bld_rings, what FreeCar hits) more than 0.3 m from any drawn
## wall (an invisible wall) and of drawn wall more than 0.3 m from any collision edge (a wall the car drives through).
## Kinds: "footprint" (walls on the OSM ring), "lod2" (walls on the measured roof outline), "landmark" / "shaft" (not
## drawn as a building: a model stands there; measured against the model's footprint below 2 m).
##   timeout 900 godot --headless --path godot -s tests/_building_collision_probe.gd
extends SceneTree

const GAP := 0.3

class Recorder extends TownBuilder:
	var walls := {} ## bi -> PackedVector2Array of a, b pairs (pushed out as drawn)
	var lod2 := {}
	func _wall(mb: MeshBatch, a: Vector2, b: Vector2, y_lo: float, top_a: float, top_b: float, out: Vector3, color: Color, hi: float, seed: float, code: float, bi := -1, push := 0.0) -> void:
		var o := Vector2(out.x, out.z) * push
		if not walls.has(bi):
			walls[bi] = PackedVector2Array()
		walls[bi].append_array(PackedVector2Array([a + o, b + o]))
		super(mb, a, b, y_lo, top_a, top_b, out, color, hi, seed, code, bi, push)
	func _add_lod2_roof(mb: MeshBatch, faces: Array, hi: float, base: float, roof: Color, wall: Color, uv2_roof: Vector2, uv2_wall: Vector2, bi := -1, push := 0.0) -> bool:
		var ok := super(mb, faces, hi, base, roof, wall, uv2_roof, uv2_wall, bi, push)
		if ok:
			lod2[bi] = true
		return ok

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var root := Node3D.new()
	var rec := Recorder.new(map, root)
	var t0 := Time.get_ticks_msec()
	var built := rec._building_meshes()
	print("built in %.1f s, %d buildings with walls" % [(Time.get_ticks_msec() - t0) / 1000.0, rec.walls.size()])
	var models := ModelRings.drawn(rec, map)
	if OS.get_environment("OLD") == "":
		for bi: int in built[built.size() - 1]: # what build_buildings hands TownMap
			map.set_building_faces(bi, built[built.size() - 1][bi])
		rec.build_landmarks()
		for bi: int in models: # a model's footprint is what is drawn there
			var f := map.building_faces(bi)
			var segs := PackedVector2Array()
			for k in range(0, f.size(), 6):
				segs.append_array(PackedVector2Array([Vector2(f[k], f[k + 1]), Vector2(f[k + 2], f[k + 3])]))
			rec.walls[bi] = segs
	print(BuildingAudit.report(map, rec.walls, rec.lod2, models, GAP))
	root.free()
	quit()

## The footprints of what stands in place of the buildings TownBuilder does not draw: [bi -> ring] (empty for none).
class ModelRings:
	static func drawn(b: TownBuilder, map: TownMap) -> Dictionary:
		var out := {}
		var shafts := b.shaft_towers()
		for bi in map.buildings.size():
			var e: Array = map.buildings[bi]
			var extra: Dictionary = e[6] if e.size() > 6 and e[6] is Dictionary else {}
			if extra.has("lm") and b.has_model(String(extra.lm)):
				out[bi] = "landmark"
			elif shafts.hidden.has(bi):
				out[bi] = "shaft"
		return out

class BuildingAudit:
	static func _near(p: Vector2, segs: PackedVector2Array, cells: Dictionary, r: float) -> bool:
		var cx := floori(p.x / 8.0)
		var cy := floori(p.y / 8.0)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for k: int in cells.get(Vector2i(cx + dx, cy + dy), []):
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p, segs[k], segs[k + 1])) <= r:
						return true
		return false

	static func _index(segs: PackedVector2Array) -> Dictionary:
		var cells := {}
		for k in range(0, segs.size(), 2):
			var lo := segs[k].min(segs[k + 1])
			var hi := segs[k].max(segs[k + 1])
			for cx in range(floori(lo.x / 8.0), floori(hi.x / 8.0) + 1):
				for cy in range(floori(lo.y / 8.0), floori(hi.y / 8.0) + 1):
					var c := Vector2i(cx, cy)
					if not cells.has(c):
						cells[c] = []
					cells[c].append(k)
		return cells

	## {kind: [collision m, invisible m, drawn m, drive-through m, buildings with > 1 m invisible]} as text, plus worst cases.
	static func report(map: TownMap, walls: Dictionary, lod2: Dictionary, models: Dictionary, gap: float) -> String:
		var got := measure(map, walls, lod2, models, gap)
		var stats: Dictionary = got[0]
		var worst: Array = got[1]
		var out := "kind        collision m  invisible m  drawn m  drive-through m  buildings >1 m invisible\n"
		for kind in stats:
			var st: Array = stats[kind]
			out += "%-10s %11.0f %12.0f %8.0f %16.0f %8d\n" % [kind, st[0], st[1], st[2], st[3], st[4]]
		for w in worst.slice(0, 12):
			var c := Vector2.ZERO
			for p in map.bld_rings[w[1]]:
				c += p
			c /= maxf(map.bld_rings[w[1]].size(), 1)
			out += "  building %d (%s, %s) at (%.0f, %.0f): %.1f m of collision edge with no wall\n" % [w[1], w[2], map.buildings[w[1]][0], c.x, c.y, w[0]]
		return out

	## [{kind: [collision m, invisible m, drawn m, drive-through m, buildings with > 1 m invisible]}, worst [m, bi, kind] first]
	static func measure(map: TownMap, walls: Dictionary, lod2: Dictionary, models: Dictionary, gap: float) -> Array:
		var drawn := PackedVector2Array()
		for bi in walls:
			drawn.append_array(walls[bi])
		var dcells := _index(drawn)
		var coll := PackedVector2Array()
		var rings := {} # bi -> collision segment pairs (TownMap.building_faces: what FreeCar meets)
		for bi in map.bld_rings.size():
			var f := map.building_faces(bi)
			var segs := PackedVector2Array()
			for k in range(0, f.size(), 6):
				segs.append_array(PackedVector2Array([Vector2(f[k], f[k + 1]), Vector2(f[k + 2], f[k + 3])]))
			rings[bi] = segs
			coll.append_array(segs)
		var ccells := _index(coll)
		var stats := {}
		var worst := []
		for bi in map.bld_rings.size():
			var segs: PackedVector2Array = rings[bi]
			var kind: String = models.get(bi, "lod2" if lod2.has(bi) else ("footprint" if walls.has(bi) else "undrawn"))
			if not stats.has(kind):
				stats[kind] = [0.0, 0.0, 0.0, 0.0, 0]
			var st: Array = stats[kind]
			var miss := 0.0
			if true:
				for k in range(0, segs.size(), 2):
					var a := segs[k]
					var b := segs[k + 1]
					var n := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
					var piece := a.distance_to(b) / n
					for j in n:
						var p := a.lerp(b, (j + 0.5) / n)
						st[0] += piece
						if not _near(p, drawn, dcells, gap):
							miss += piece
			st[1] += miss
			if miss > 1.0:
				st[4] += 1
				worst.append([miss, bi, kind])
			var mine: PackedVector2Array = walls.get(bi, PackedVector2Array())
			for k in range(0, mine.size(), 2):
				var a := mine[k]
				var b := mine[k + 1]
				var n := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
				var piece := a.distance_to(b) / n
				for j in n:
					var p := a.lerp(b, (j + 0.5) / n)
					st[2] += piece
					if not _near(p, coll, ccells, gap):
						st[3] += piece
		worst.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
		return [stats, worst]
