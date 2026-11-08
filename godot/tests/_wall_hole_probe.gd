## Probe: stretches of wall the plan leaves out (_cuts) that no other building's drawn wall covers (visible holes),
## classified by why the covering wall is missing.
## godot --headless --path godot -s tests/_wall_hole_probe.gd
extends SceneTree

var log: Array
const PT := 0.06
var cells := {}

func _key(q: Vector2) -> Vector2i:
	return Vector2i(floori(q.x * 0.2), floori(q.y * 0.2))

func _covered(p: Vector2, y: float, skip_b: int, plane_tol: float, only_b := -1, ignore_y := false) -> bool:
	for i: int in cells.get(_key(p), []):
		var w: Array = log[i]
		if w[0] == skip_b or (only_b >= 0 and w[0] != only_b):
			continue
		var a: Vector2 = w[1]
		var c: Vector2 = w[2]
		var wl := a.distance_to(c)
		if wl < 0.01:
			continue
		var wt := (c - a) / wl
		var n := Vector2(-wt.y, wt.x)
		if absf((p - a).dot(n)) > plane_tol:
			continue
		var f := (p - a).dot(wt) / wl
		if f < -0.01 or f > 1.01:
			continue
		f = clampf(f, 0, 1)
		if ignore_y or (y >= lerpf(w[3], w[4], f) - 0.05 and y <= lerpf(w[5], w[6], f) + 0.05):
			return true
	return false

func _init() -> void:
	var map := TownMap.load_map("brzeszcze")
	var root := Node3D.new()
	var b := TownBuilder.new(map, root)
	b.log_walls = true
	b.build_buildings()
	log = b.wall_log
	print("walls logged %d, buildings with cuts %d" % [log.size(), b._cuts.size()])
	for i in log.size():
		var a: Vector2 = log[i][1]
		var c: Vector2 = log[i][2]
		var ln := a.distance_to(c)
		var seen := {}
		for k in int(ln / 2.0) + 2:
			var q := a.lerp(c, minf(float(k) * 2.0 / maxf(ln, 0.01), 1.0))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var key := _key(q) + Vector2i(dx, dy)
					if seen.has(key):
						continue
					seen[key] = true
					if not cells.has(key):
						cells[key] = []
					cells[key].append(i)
	# plan edges of every building, to find who was meant to cover a hole
	var shafts := b.shaft_towers()
	var not_drawn := {}
	for bi in map.buildings.size():
		var bb: Array = map.buildings[bi]
		var extra: Dictionary = bb[6] if bb.size() > 6 and bb[6] is Dictionary else {}
		if (extra.has("lm") and b.has_model(String(extra.lm))) or shafts.hidden.has(bi):
			not_drawn[bi] = true
	var drawn_b := {}
	for w in log:
		drawn_b[w[0]] = true
	var holes := 0
	var total := 0
	var by_b := {}
	var classes := {}
	var examples := {}
	var edge_cache := {}
	var ecells := {}
	for bi in map.buildings.size():
		var ring := map.bld_rings[bi]
		if ring.size() < 3:
			continue
		for we in b._wall_edges(bi, ring):
			var a: Vector2 = we[0]
			var c: Vector2 = we[1]
			var ln := a.distance_to(c)
			for k in int(ln / 2.0) + 2:
				var q := a.lerp(c, minf(float(k) * 2.0 / maxf(ln, 0.01), 1.0))
				var key := _key(q)
				if not ecells.has(key):
					ecells[key] = {}
				ecells[key][edge_cache.size()] = true
			edge_cache[edge_cache.size()] = [bi, a, c, float(we[3]), float(we[4])]
	for lower: int in b._cuts:
		for r in b._cuts[lower]:
			var la: Vector2 = r[0]
			var lb: Vector2 = r[1]
			var ln := la.distance_to(lb)
			if ln < 0.01:
				continue
			var t := (lb - la) / ln
			for k in 5:
				var f := (k + 0.5) / 5.0
				var s := lerpf(r[2], r[3], f)
				var p := la + t * s
				var yt := lerpf(r[5], r[6], f)
				if yt - float(r[4]) < 0.1:
					continue
				var y := 0.0
				var hole := false
				for yf: float in [0.02, 0.5, 0.98]:
					y = lerpf(float(r[4]), yt, yf)
					total += 1
					if not _covered(p, y, lower, PT):
						hole = true
						break
				if not hole:
					continue
				holes += 1
				by_b[lower] = by_b.get(lower, 0) + 1
				# who was the plan's cover? other buildings' plan edges through p within SHARED_TOL
				var cands := {}
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						for ei: int in ecells.get(_key(p) + Vector2i(dx, dy), {}):
							var e: Array = edge_cache[ei]
							if e[0] == lower:
								continue
							var ea: Vector2 = e[1]
							var ec: Vector2 = e[2]
							var el := ea.distance_to(ec)
							if el < 0.1:
								continue
							var et := (ec - ea) / el
							if absf(et.dot(t)) < 0.99:
								continue
							if absf((p - ea).dot(Vector2(-et.y, et.x))) > 0.05:
								continue
							var ff := (p - ea).dot(et) / el
							if ff < -0.01 or ff > 1.01:
								continue
							cands[e[0]] = lerpf(e[3], e[4], clampf(ff, 0, 1))
				var cls := ""
				if cands.is_empty():
					cls = "no plan cover edge"
				else:
					for u: int in cands:
						var c2 := ""
						if not_drawn.has(u):
							c2 = "cover not drawn (landmark/shaft)"
						elif not drawn_b.has(u):
							c2 = "cover building drew no walls"
						elif _covered(p, y, lower, PT, u):
							c2 = "covered"  # should not happen
						elif _covered(p, y, lower, 3.0, u):
							c2 = "cover pushed/offset >0.3 m"
						elif _covered(p, y, lower, PT, u, true):
							c2 = "cover drawn at other height (plan top %.1f)" % float(cands[u])
						else:
							var cut_there := false
							for rr in b._cuts.get(u, []):
								var ra: Vector2 = rr[0]
								var rb: Vector2 = rr[1]
								var rl := ra.distance_to(rb)
								if rl < 0.01:
									continue
								var rt := (rb - ra) / rl
								if absf((p - ra).dot(Vector2(-rt.y, rt.x))) < 0.05:
									var ss := (p - ra).dot(rt)
									if ss >= float(rr[2]) - 0.05 and ss <= float(rr[3]) + 0.05:
										cut_there = true
							c2 = "cover itself cut (chain)" if cut_there else "cover wall absent here (LoD2/fallback mismatch)"
						if cls == "" or c2 == "cover itself cut (chain)":
							cls = c2
				classes[cls] = classes.get(cls, 0) + 1
				if not examples.has(cls):
					examples[cls] = []
				if examples[cls].size() < 4:
					examples[cls].append("b%d at (%.1f, %.1f) y=%.1f cands=%s" % [lower, p.x, p.y, y, cands])
	print("cut samples %d, uncovered %d, buildings affected %d" % [total, holes, by_b.size()])
	for cls in classes:
		print("  %s: %d" % [cls, classes[cls]])
		for ex in examples[cls]:
			print("     ", ex)
	_footprint_check(map, b)
	root.free()
	quit()

## Every footprint edge, sampled at 1.5 m over the ground: is some drawn wall within 1 m of the point at that height
## (or the point inside another building)? And does every drawn wall face out of its building?
func _footprint_check(map: TownMap, b: TownBuilder) -> void:
	var lod_b := {}
	var drawn_b := {}
	for w in log:
		drawn_b[w[0]] = true
	var rcells := {}
	for bi in map.buildings.size():
		var ring := map.bld_rings[bi]
		if ring.size() < 3:
			continue
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q in ring:
			lo = lo.min(q)
			hi = hi.max(q)
		for x in range(floori(lo.x * 0.2), floori(hi.x * 0.2) + 1):
			for y in range(floori(lo.y * 0.2), floori(hi.y * 0.2) + 1):
				var k := Vector2i(x, y)
				if not rcells.has(k):
					rcells[k] = []
				rcells[k].append(bi)
	var samples := 0
	var bare := 0
	var bare_b := {}
	var bare_kind := {}
	var ex := []
	for bi in drawn_b:
		var ring := map.bld_rings[bi]
		var bb: Array = map.buildings[bi]
		var extra: Dictionary = bb[6] if bb.size() > 6 and bb[6] is Dictionary else {}
		var is_lod := extra.has("rs") and not (extra.rs as Array).is_empty()
		for i in ring.size():
			var a := ring[i]
			var c := ring[(i + 1) % ring.size()]
			var ln := a.distance_to(c)
			if ln < 1.0:
				continue
			var n := int(ln / 1.5) + 1
			for k in n:
				var p := a.lerp(c, (k + 0.5) / n)
				var y := map.ground(p.x, p.y) + 1.5
				samples += 1
				if _covered(p, y, -1, 1.0):
					continue
				var inside := false
				for oj: int in rcells.get(_key(p), []):
					if oj != bi and Geometry2D.is_point_in_polygon(p + (p - (a + c) * 0.5).normalized() * 0.0 + Vector2(-(c - a).y, (c - a).x).normalized() * 0.3, map.bld_rings[oj]) and Geometry2D.is_point_in_polygon(p - Vector2(-(c - a).y, (c - a).x).normalized() * 0.3, map.bld_rings[oj]):
						inside = true
				if inside:
					continue
				# a neighbour flush against this edge: the wall is a party wall
				var party := false
				for oj: int in rcells.get(_key(p), []):
					if oj == bi:
						continue
					var nn := Vector2(-(c - a).y, (c - a).x).normalized()
					if Geometry2D.is_point_in_polygon(p + nn * 0.3, map.bld_rings[oj]) or Geometry2D.is_point_in_polygon(p - nn * 0.3, map.bld_rings[oj]):
						party = true
				if party:
					continue
				bare += 1
				bare_b[bi] = true
				var kk := "lod2" if is_lod else "footprint"
				bare_kind[kk] = bare_kind.get(kk, 0) + 1
				if ex.size() < 12:
					ex.append("b%d %s %s at (%.1f, %.1f) edge len %.1f" % [bi, kk, bb[0], p.x, p.y, ln])
	print("footprint samples %d, bare %d, buildings %d, by kind %s" % [samples, bare, bare_b.size(), bare_kind])
	for e in ex:
		print("   ", e)
	# facing: a footprint wall's outward side must be outside its ring; a LoD2 wall's outside its own roof plane
	var wrong := {"footprint": 0, "lod2": 0}
	var tested := {"footprint": 0, "lod2": 0}
	var wrong_b := {"footprint": {}, "lod2": {}}
	var wlen := {"footprint": 0.0, "lod2": 0.0}
	var wex := []
	var fixed_wrong := {}
	for w in log:
		var bi: int = w[0]
		var a: Vector2 = w[1]
		var c: Vector2 = w[2]
		if a.distance_to(c) < 0.5:
			continue
		var m := (a + c) * 0.5
		var o: Vector2 = w[7]
		var ring := map.bld_rings[bi]
		var on_ring := false
		for i in ring.size():
			var q0 := ring[i]
			var q1 := ring[(i + 1) % ring.size()]
			if Geometry2D.get_closest_point_to_segment(a, q0, q1).distance_to(a) < 0.1 and Geometry2D.get_closest_point_to_segment(c, q0, q1).distance_to(c) < 0.1:
				on_ring = true
				break
		var kind := "footprint" if on_ring else "lod2"
		var polys: Array = [ring]
		if not on_ring:
			var bb: Array = map.buildings[bi]
			var extra: Dictionary = bb[6] if bb.size() > 6 and bb[6] is Dictionary else {}
			polys = []
			for f in extra.get("rs", []):
				var pl := PackedVector2Array()
				for j in range(0, f.size() - 2, 3):
					pl.append(Vector2(f[j], f[j + 1]))
				for i in pl.size():
					var q0 := pl[i]
					var q1 := pl[(i + 1) % pl.size()]
					if Geometry2D.get_closest_point_to_segment(a, q0, q1).distance_to(a) < 0.05 and Geometry2D.get_closest_point_to_segment(c, q0, q1).distance_to(c) < 0.05:
						polys.append(pl)
						break
			if polys.is_empty():
				continue
		var t2 := (c - a).normalized()
		var fix_ok := false
		var fix_test := false
		for poly in polys:
			var A := TownBuilder.ring_area(poly)
			var cand := Vector2(-t2.y, t2.x) if on_ring else Vector2(t2.y, -t2.x) * signf(A)
			if not on_ring:
				# the wall runs in the plane's order only when a comes before c in it
				var fwd := false
				for i in poly.size():
					if poly[i].distance_to(a) < 0.05 and poly[(i + 1) % poly.size()].distance_to(c) < 0.05:
						fwd = true
				if not fwd:
					continue
			var pin2 := Geometry2D.is_point_in_polygon(m - cand * 0.1, poly)
			var pout2 := Geometry2D.is_point_in_polygon(m + cand * 0.1, poly)
			if pin2 == pout2:
				continue
			fix_test = true
			if pin2:
				fix_ok = true
		if fix_test and not fix_ok:
			fixed_wrong[kind] = fixed_wrong.get(kind, 0) + 1
		var any_ok := false
		var any_test := false
		for poly in polys:
			var pin := Geometry2D.is_point_in_polygon(m - o * 0.1, poly)
			var pout := Geometry2D.is_point_in_polygon(m + o * 0.1, poly)
			if pin == pout:
				continue
			any_test = true
			if pin:
				any_ok = true
		if not any_test:
			continue
		tested[kind] += 1
		if not any_ok:
			wrong[kind] += 1
			wrong_b[kind][bi] = true
			wlen[kind] += a.distance_to(c)
			if wex.size() < 10 and (kind == "footprint" or wex.size() > 5):
				wex.append("b%d %s %s wall (%.1f, %.1f)-(%.1f, %.1f) faces in" % [bi, kind, map.buildings[bi][0], a.x, a.y, c.x, c.y])
	print("with winding-based outward: still inward %s" % fixed_wrong)
	for k in wrong:
		print("facing %s: tested %d, inward %d (%.0f m of wall), buildings %d" % [k, tested[k], wrong[k], wlen[k], wrong_b[k].size()])
	for e in wex:
		print("   ", e)
