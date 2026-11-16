## Headless audit of the open world's streets (data from tools/build_open_world.py, drawing from
## TownBuilder._street_meshes): per category a count and the worst cases with map coordinates.
##   timeout 600 godot --headless --path godot -s tests/_road_audit_probe.gd
## Rebuilds the ribbon's edge vertices the way TownBuilder does (TownBuilder.ribbon_edges) so what it measures is
## what is drawn.
extends SceneTree

const GRADE_WINDOW := 4.0
var map: TownMap
var node_roads := {}
var node_width := {}

func _initialize() -> void:
	map = TownMap.load_map(OpenWorld.MAP_KEY)
	for ri in map.road_pts.size():
		for m in map.road_marks[ri]:
			var nid := str(m[1])
			node_roads[nid] = int(node_roads.get(nid, 0)) + 1
			node_width[nid] = maxf(float(node_width.get(nid, 0.0)), map.road_w[ri])
	print("AUDIT %d roads, %d graph nodes" % [map.road_pts.size(), map.node_pos.size()])
	_classes()
	_geometry()
	_joins()
	_ends()
	_heights()
	_duplicates()
	_junction_potholes()
	quit()

func _nm(ri: int) -> String:
	return "'%s' %s w%.1f #%d" % [map.road_name[ri], map.road_kind[ri], map.road_w[ri], ri]

func _top(rows: Array, k: int, fmt: Callable) -> void:
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for r in rows.slice(0, k):
		print("    " + str(fmt.call(r)))

static func _pct(v: PackedFloat32Array, qs: Array) -> String:
	var a := v.duplicate()
	a.sort()
	var out := []
	for q: float in qs:
		out.append("p%s %.3f" % [str(q * 100.0), a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)]] if not a.is_empty() else "-")
	return ", ".join(out)

func _classes() -> void:
	var by := {}
	for ri in map.road_pts.size():
		var k := map.road_kind[ri]
		if not by.has(k):
			by[k] = [0, 0.0, PackedFloat32Array(), [0, 0, 0], [0, 0, 0, 0]]
		by[k][0] += 1
		by[k][1] += map.road_len[ri]
		by[k][2].append(map.road_w[ri])
		by[k][3][clampi(map.road_surface[ri], 0, 2)] += 1
		by[k][4][TownBuilder._style_of(map, ri)] += 1
	print("CLASSES kind: count, km, width min/med/max, surface asphalt/setts/unpaved, marking style 0/1/2/3")
	for k in by:
		var w: PackedFloat32Array = by[k][2]
		w.sort()
		print("    %-14s %4d %6.1f km  w %.1f/%.1f/%.1f  surf %s  style %s" % [k, by[k][0], by[k][1] / 1000.0, w[0], w[w.size() / 2],
			w[w.size() - 1], by[k][3], by[k][4]])

## Sharp corners, narrowed corners and folded (bow-tie) ribbon quads.
func _geometry() -> void:
	var sharp45 := 0
	var sharp90 := 0
	var narrow := 0
	var folds := 0
	var fold_rows := []
	var corner_rows := []
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var n := pts.size()
		if n < 3:
			continue
		var rib := TownBuilder.ribbon(map, ri)
		var left: PackedVector2Array = rib.left
		var right: PackedVector2Array = rib.right
		var halves: PackedFloat32Array = rib.half
		for i in range(1, n - 1):
			var half := halves[i]
			if pts[i].distance_to(pts[i - 1]) < 0.05 or pts[i].distance_to(pts[i + 1]) < 0.05:
				continue
			var d0 := (pts[i] - pts[i - 1]).normalized()
			var d1 := (pts[i + 1] - pts[i]).normalized()
			var turn := absf(d0.angle_to(d1))
			if turn > PI / 4.0:
				sharp45 += 1
			if turn > PI / 2.0:
				sharp90 += 1
			# the ribbon's width across each neighbouring segment at this vertex
			var w_eff := absf((right[i] - left[i]).dot(Vector2(-d0.y, d0.x))) / (2.0 * half)
			if w_eff < 0.85:
				narrow += 1
				corner_rows.append([1.0 - w_eff, ri, pts[i], rad_to_deg(turn)])
		for i in n - 1:
			var seg := pts[i + 1] - pts[i]
			var sl := (left[i + 1] - left[i]).dot(seg)
			var sr := (right[i + 1] - right[i]).dot(seg)
			if sl < 0.0 or sr < 0.0:
				folds += 1
				fold_rows.append([-minf(sl, sr) / maxf(seg.length(), 0.01), ri, pts[i], i])
	print("GEOMETRY vertices turning >45 deg %d, >90 deg %d; ribbon narrower than 85%% at %d; folded quads %d" % [sharp45, sharp90, narrow, folds])
	print("  worst folds (metres the edge runs backwards):")
	_top(fold_rows, 10, func(r: Array) -> String: return "%.2f m %s at %s seg %d" % [r[0], _nm(r[1]), r[2], r[3]])
	print("  worst narrowed corners:")
	_top(corner_rows, 10, func(r: Array) -> String: return "-%.0f%% (turn %.0f deg) %s at %s" % [r[0] * 100.0, r[3], _nm(r[1]), r[2]])

## Two ways joined end to end (a node on exactly two roads, an end of both): width and class steps.
func _joins() -> void:
	var ends := {}
	for ri in map.road_pts.size():
		var n := map.road_pts[ri].size()
		for m in map.road_marks[ri]:
			var idx := int(m[0])
			if idx == 0 or idx == n - 1:
				var nid := str(m[1])
				if not ends.has(nid):
					ends[nid] = []
				ends[nid].append(ri)
	var joins := 0
	var steps := 0
	var rows := []
	var edge_rows := []
	for nid in ends:
		if int(node_roads.get(nid, 0)) != 2 or ends[nid].size() != 2:
			continue
		joins += 1
		var a: int = ends[nid][0]
		var b: int = ends[nid][1]
		var dw := absf(map.road_w[a] - map.road_w[b])
		if dw > 0.3:
			steps += 1
			rows.append([dw, a, b, map.node_pos[nid]])
		# the drawn edges of the two ribbons at the shared point: apart by how much
		var ia := 0 if map.road_pts[a][0].distance_to(map.node_pos[nid]) < 0.2 else map.road_pts[a].size() - 1
		var ib := 0 if map.road_pts[b][0].distance_to(map.node_pos[nid]) < 0.2 else map.road_pts[b].size() - 1
		if a == b:
			ib = map.road_pts[b].size() - 1
			ia = 0
		var ra := TownBuilder.ribbon(map, a)
		var rb := TownBuilder.ribbon(map, b)
		var la: Vector2 = ra.left[ia]
		var lb: Vector2 = rb.left[ib] if (ia == 0) != (ib == 0) else rb.right[ib]
		var ra_r: Vector2 = ra.right[ia]
		var rb_r: Vector2 = rb.right[ib] if (ia == 0) != (ib == 0) else rb.left[ib]
		var mis := maxf(la.distance_to(lb), ra_r.distance_to(rb_r))
		if mis > 0.3:
			edge_rows.append([mis, a, b, map.node_pos[nid]])
	print("JOINS %d way-to-way joins, %d with a width step > 0.3 m in the data; %d with the drawn edges > 0.3 m apart" % [joins, steps, edge_rows.size()])
	_top(rows, 6, func(r: Array) -> String: return "%.1f m: %s -> %s at %s" % [r[0], _nm(r[1]), _nm(r[2]), r[3]])
	print("  drawn edge mismatch:")
	_top(edge_rows, 8, func(r: Array) -> String: return "%.2f m: %s -> %s at %s" % [r[0], _nm(r[1]), _nm(r[2]), r[3]])

## Loose ends: a road end on no other road but within reach of one (a gap or a stub short of the junction), and stubs.
func _ends() -> void:
	var gaps := []
	var stubs := []
	var dead := 0
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var n := pts.size()
		if map.road_len[ri] < 12.0:
			stubs.append([map.road_len[ri], ri, pts[0]])
		for m in map.road_marks[ri]:
			var idx := int(m[0])
			if (idx != 0 and idx != n - 1) or int(node_roads.get(str(m[1]), 0)) >= 2:
				continue
			dead += 1
			var p := pts[idx]
			var near := _nearest_except(p, ri, map.road_w[ri] * 0.5 + 6.0)
			if near.is_empty():
				continue
			var gap: float = float(near.dist) - map.road_w[int(near.road)] * 0.5
			if gap > 0.05:
				gaps.append([gap, ri, int(near.road), p])
	print("ENDS %d free road ends; %d end 0.05-%.0f m short of another road's edge; %d roads shorter than 12 m" % [dead, gaps.size(), 6.0, stubs.size()])
	_top(gaps, 10, func(r: Array) -> String: return "gap %.1f m: %s ends near %s at %s" % [r[0], _nm(r[1]), _nm(r[2]), r[3]])
	stubs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for r in stubs.slice(0, 6):
		print("    stub %.1f m %s at %s" % [r[0], _nm(r[1]), r[2]])

func _nearest_except(p: Vector2, skip: int, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	var r := int(ceil(radius / TownMap.CELL))
	var cx := int(floor(p.x / TownMap.CELL))
	var cy := int(floor(p.y / TownMap.CELL))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var ck := map._cell_key(cx + dx, cy + dy)
			if not map._seg_cells.has(ck):
				continue
			for sid in map._seg_cells[ck]:
				var ri := map._seg_road[sid]
				if ri == skip:
					continue
				var a := map.road_pts[ri][map._seg_i[sid]]
				var ab := map.road_pts[ri][map._seg_i[sid] + 1] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				if d < best_d:
					best_d = d
					best = {"road": ri, "dist": d}
	return best

## Longitudinal grade and its change, cross slope, drawn surface vs the terrain and vs the car's ride height.
func _heights() -> void:
	var grade := PackedFloat32Array()
	var dgrade := PackedFloat32Array()
	var cross := PackedFloat32Array()
	var over := PackedFloat32Array()
	var ride := PackedFloat32Array()
	var steep_rows := []
	var kink_rows := []
	var cross_rows := []
	var bury_rows := []
	var ride_rows := []
	var float_rows := []
	var buried := 0
	var floating := 0
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var n := pts.size()
		if n < 2:
			continue
		var half := map.road_w[ri] * 0.5
		var lift := map.road_lift(ri)
		var zs := map.road_z[ri]
		var rib := TownBuilder.ribbon(map, ri)
		var hl: PackedFloat32Array = rib.hl
		var hr: PackedFloat32Array = rib.hr
		var left: PackedVector2Array = rib.left
		var right: PackedVector2Array = rib.right
		var prev_g := INF
		var prev_l := 0.0
		# grade over windows of at least GRADE_WINDOW m of centreline (a bend's short chords say nothing alone)
		var w0 := 0
		var run := 0.0
		for i in range(1, n):
			run += pts[i].distance_to(pts[i - 1])
			if run < GRADE_WINDOW and i < n - 1:
				continue
			if run < 1.0:
				break
			var g := ((hl[i] + hr[i]) - (hl[w0] + hr[w0])) * 0.5 / run
			grade.append(absf(g))
			if absf(g) > 0.1:
				steep_rows.append([absf(g), ri, pts[i]])
			if prev_g < INF:
				var dg := absf(g - prev_g) / ((run + prev_l) * 0.5)
				dgrade.append(dg)
				if dg > 0.004:
					kink_rows.append([dg, ri, pts[w0], g, prev_g])
			prev_g = g
			prev_l = run
			w0 = i
			run = 0.0
		for i in n:
			var deck := zs[i] if not zs.is_empty() else 0.0
			if deck <= 0.3:
				var cs := absf(hl[i] - hr[i]) / maxf(left[i].distance_to(right[i]), 0.1)
				cross.append(cs)
				if cs > 0.04:
					cross_rows.append([cs, ri, pts[i]])
			if i == n - 1:
				break
			if pts[i].distance_to(pts[i + 1]) < 0.05:
				continue
			# the drawn quad (two triangles over left_i, right_i, right_i+1, left_i+1) against the terrain and the ride
			for k in 3:
				var t := (k + 0.5) / 3.0
				for u: float in [0.1, 0.5, 0.9]:
					var lp := left[i].lerp(left[i + 1], t)
					var rp := right[i].lerp(right[i + 1], t)
					var p := lp.lerp(rp, u)
					var h_draw := lerpf(lerpf(hl[i], hl[i + 1], t), lerpf(hr[i], hr[i + 1], t), u)
					if deck <= 0.05:
						var o := h_draw - map.terrain(p.x, p.y)
						over.append(o)
						if o < 0.03:
							buried += 1
							bury_rows.append([0.03 - o, ri, p])
						elif o > 0.5:
							floating += 1
							float_rows.append([o, ri, p, i])
					var hit := map.road_at(p.x, p.y, h_draw)
					if not hit.is_empty() and int(hit.road) == ri:
						var dr := float(hit.height) - h_draw
						ride.append(absf(dr))
						if absf(dr) > 0.05:
							ride_rows.append([absf(dr), ri, p, dr])
	print("GRADE |grade| %s; > 8%%: %d segs, > 12%%: %d" % [_pct(grade, [0.5, 0.9, 0.99, 1.0]), _count(grade, 0.08), _count(grade, 0.12)])
	_top(steep_rows, 6, func(r: Array) -> String: return "%.1f%% %s at %s" % [r[0] * 100.0, _nm(r[1]), r[2]])
	print("GRADE CHANGE per m %s; > 0.4%%/m: %d, > 1%%/m: %d" % [_pct(dgrade, [0.5, 0.9, 0.99, 1.0]), _count(dgrade, 0.004), _count(dgrade, 0.01)])
	_top(kink_rows, 8, func(r: Array) -> String: return "%.2f%%/m (%.1f%% -> %.1f%%) %s at %s" % [r[0] * 100.0, r[4] * 100.0, r[3] * 100.0, _nm(r[1]), r[2]])
	print("CROSS SLOPE %s; > 2%%: %d, > 4%%: %d of %d vertices" % [_pct(cross, [0.5, 0.9, 0.99, 1.0]), _count(cross, 0.02), _count(cross, 0.04), cross.size()])
	_top(cross_rows, 6, func(r: Array) -> String: return "%.1f%% %s at %s" % [r[0] * 100.0, _nm(r[1]), r[2]])
	print("OVER TERRAIN drawn - terrain %s; buried (< 3 cm) %d, floating (> 0.5 m) %d of %d samples" % [_pct(over, [0.0, 0.01, 0.5, 0.99, 1.0]), buried, floating, over.size()])
	_top(float_rows, 8, func(r: Array) -> String: return "%.2f m over the terrain %s at %s seg %d" % [r[0], _nm(r[1]), r[2], r[3]])
	_top(bury_rows, 6, func(r: Array) -> String: return "%.2f m under %s at %s" % [r[0], _nm(r[1]), r[2]])
	print("RIDE vs DRAWN |diff| %s; > 5 cm: %d of %d" % [_pct(ride, [0.5, 0.99, 1.0]), _count(ride, 0.05), ride.size()])
	_top(ride_rows, 6, func(r: Array) -> String: return "%.2f m (%+.2f) %s at %s" % [r[0], r[3], _nm(r[1]), r[2]])

static func _count(v: PackedFloat32Array, lim: float) -> int:
	var c := 0
	for x in v:
		if x > lim:
			c += 1
	return c

## Two streets drawn over each other side by side (dual-mapped ways, duplicated service roads) away from junctions.
func _duplicates() -> void:
	var pairs := {}
	var total := 0.0
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		for i in pts.size() - 1:
			var p := (pts[i] + pts[i + 1]) * 0.5
			var dir := (pts[i + 1] - pts[i]).normalized()
			var l := pts[i].distance_to(pts[i + 1])
			var ck := map._cell_key(int(floor(p.x / TownMap.CELL)), int(floor(p.y / TownMap.CELL)))
			if not map._seg_cells.has(ck):
				continue
			for sid in map._seg_cells[ck]:
				var rj := map._seg_road[sid]
				if rj <= ri:
					continue
				var a := map.road_pts[rj][map._seg_i[sid]]
				var b := map.road_pts[rj][map._seg_i[sid] + 1]
				if absf((b - a).normalized().dot(dir)) < 0.94:
					continue
				var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
				var d := p.distance_to(a.lerp(b, t))
				if d > (map.road_w[ri] + map.road_w[rj]) * 0.5 - 0.5:
					continue
				var dz := absf(map.deck_at(ri, i, 0.5) - map.deck_at(rj, map._seg_i[sid], t))
				if dz > 0.5:
					continue
				if _near_node(p, maxf(map.road_w[ri], map.road_w[rj]) + 3.0):
					continue
				var key := "%d/%d" % [ri, rj]
				if not pairs.has(key):
					pairs[key] = [0.0, ri, rj, p, d]
				pairs[key][0] += l
				total += l
				break
	print("DUPLICATES %.0f m of street drawn alongside/over another parallel street, %d pairs" % [total, pairs.size()])
	_top(pairs.values(), 12, func(r: Array) -> String: return "%.0f m, centres %.1f m apart: %s || %s at %s" % [r[0], r[4], _nm(r[1]), _nm(r[2]), r[3]])

var _node_grid := {}
func _near_node(p: Vector2, r: float) -> bool:
	if _node_grid.is_empty():
		for nid in map.node_pos:
			if int(node_roads.get(nid, 0)) < 2:
				continue
			var q: Vector2 = map.node_pos[nid]
			var k := Vector2i(floori(q.x / 20.0), floori(q.y / 20.0))
			if not _node_grid.has(k):
				_node_grid[k] = []
			_node_grid[k].append(q)
	var gk := Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))
	for gx in range(gk.x - 2, gk.x + 3):
		for gy in range(gk.y - 2, gk.y + 3):
			for q: Vector2 in _node_grid.get(Vector2i(gx, gy), []):
				if q.distance_to(p) < r:
					return true
	return false

## Junction discs are drawn with the pot-holed style, so a main road's junction shows holes the car never feels.
func _junction_potholes() -> void:
	var styles := TownBuilder.junction_styles(map)
	var joins := map.way_joins()
	var bad := 0
	var tar_on_dirt := 0
	var dirt_nodes := 0
	var node_ri := {}
	for ri in map.road_pts.size():
		for m in map.road_marks[ri]:
			if not node_ri.has(str(m[1])):
				node_ri[str(m[1])] = []
			node_ri[str(m[1])].append(ri)
	var total := 0
	for nid in node_roads:
		if int(node_roads[nid]) < 2 or not map.node_pos.has(nid) or joins.has(nid):
			continue
		total += 1
		var p: Vector2 = map.node_pos[nid]
		var hit := map.road_at(p.x, p.y)
		var look: Vector2i = styles.get(nid, Vector2i.ZERO)
		if not hit.is_empty() and map.road_surface[int(hit.road)] == 0 and map.road_wear(int(hit.road)) == 0.0 and look.x == 0 and look.y == 0:
			bad += 1
		var all_dirt := true
		for ri in node_ri.get(nid, []):
			if map.road_surface[ri] != 2:
				all_dirt = false
		if all_dirt:
			dirt_nodes += 1
		if all_dirt and look.y == 0:
			tar_on_dirt += 1
	print("JUNCTION DISCS %d of %d drawn with potholes over a road the car finds sound; %d drawn as tarmac of %d where only dirt roads meet" % [bad, total, tar_on_dirt, dirt_nodes])
