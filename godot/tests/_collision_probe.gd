## Open-world collision audit (headless): which solid segments TownMap hashes have no drawn mesh, which cross a
## drivable road, which solids a car on a bridge deck hits below it, and how much room each underpass leaves.
##   godot --headless --path godot -s tests/_collision_probe.gd
extends SceneTree

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	var walls: Array = map.raw.get("fences", [])
	var doubled := builder._doubled_fences(walls)
	var by_style := {}
	var undrawn := {}
	var undrawn_m := {}
	var on_road := 0
	var on_road_m := 0.0
	var first_road := []
	for wi in walls.size():
		var w: Array = walls[wi]
		var style := int(w[4]) if w.size() > 4 else 0
		var a := Vector2(float(w[0]), float(w[1]))
		var b := Vector2(float(w[2]), float(w[3]))
		var ln := a.distance_to(b)
		by_style[style] = int(by_style.get(style, 0)) + 1
		# what TownBuilder draws: panels for styles 0, 1, 3 (not doubled), a bush row for a hedge, a closure's barrier
		var drawn := (style == 0 or style == 1 or style == 3 or style == 2) and ln >= 0.35 and (style == 2 or not doubled.has(wi))
		if style == 4:
			drawn = _is_closure(map, a, b)
		var solid_rec := not doubled.has(wi) and (style == 4 or ln >= 0.35) # TownMap._load_obstacles' rule
		if solid_rec and not drawn:
			undrawn[style] = int(undrawn.get(style, 0)) + 1
			undrawn_m[style] = float(undrawn_m.get(style, 0.0)) + ln
		if style == 4:
			continue # a closure stands across its road on purpose
		# a solid across a road at ground level the car drives on
		for f in [0.2, 0.5, 0.8]:
			var q := a.lerp(b, f)
			var hit := map.road_at(q.x, q.y, -INF, -0.3)
			if not hit.is_empty() and float(hit.deck) < 0.5:
				on_road += 1
				on_road_m += ln
				if first_road.size() < 6:
					first_road.append("%s style %d on %s" % [q, style, map.road_name[int(hit.road)]])
				break
	var solid := 0
	for ck in map._wall_cells:
		solid += (map._wall_cells[ck] as PackedFloat32Array).size() / 5
	print("solid wall entries in TownMap's hash (cells x segments): ", solid)
	print("fence segments by style: ", by_style)
	print("solid (TownMap) but not drawn (count): ", undrawn)
	print("solid (TownMap) but not drawn (m): ", _round(undrawn_m))
	print("fence segments on a ground-level carriageway: %d (%.0f m) e.g. %s" % [on_road, on_road_m, first_road])
	# what a car on a raised deck would hit underneath it: fences, trees and buildings under the deck
	var under_walls := 0
	var under_posts := 0
	var under_blds := 0
	for ri in map.road_pts.size():
		var zs := map.road_z[ri]
		if zs.is_empty():
			continue
		var pts := map.road_pts[ri]
		for i in pts.size() - 1:
			if minf(zs[i], zs[i + 1]) < 2.0:
				continue
			var mid := (pts[i] + pts[i + 1]) * 0.5
			var half := map.road_w[ri] * 0.5
			for wall in map.walls_near(mid, half):
				if Geometry2D.get_closest_point_to_segment(mid, Vector2(wall[0], wall[1]), Vector2(wall[2], wall[3])).distance_to(mid) < half:
					under_walls += 1
			under_posts += map.posts_near(mid, half).size()
			for bi in map.buildings_near(mid, 0.0):
				if Geometry2D.is_point_in_polygon(mid, map.bld_rings[bi]):
					under_blds += 1
	print("solids under raised decks (more than 2 m up): walls %d, posts %d, buildings %d" % [under_walls, under_posts, under_blds])
	# posts (trees, lamps) standing in a carriageway
	var posts_on_road := 0
	for ck in map._post_cells:
		for v: Vector3 in map._post_cells[ck]:
			var hit := map.road_at(v.x, v.y, -INF, -0.2)
			if not hit.is_empty() and float(hit.deck) < 0.5:
				posts_on_road += 1
				if posts_on_road <= 14:
					print("  post r %.2f at (%.1f, %.1f) %.2f m from the centre of %s (half %.1f)" % [v.z, v.x, v.y, absf(float(hit.dist)), map.road_name[int(hit.road)], float(hit.half)])
	print("posts in a ground-level carriageway: %d" % posts_on_road)
	# underpasses: clear width between the side walls, and how far the street's edge comes to them
	for t in map.tunnels:
		var c: Vector2 = t.c
		var v: Vector2 = t.v
		var n := Vector2(-v.y, v.x)
		var ri := -1
		for k in map.raw.roads.size():
			if int(map.raw.roads[k].id) == int(t.road):
				ri = k
				break
		var worst := INF
		var worst_s := 0.0
		var s := -float(t.half_foot)
		while s <= float(t.half_foot):
			var q := c + v * s
			# the street's centre line nearest this station, measured across the bore
			var best := INF
			var lat := 0.0
			var pts := map.road_pts[ri]
			for k in pts.size() - 1:
				var cp := Geometry2D.get_closest_point_to_segment(q, pts[k], pts[k + 1])
				var dd := cp.distance_to(q)
				if dd < best:
					best = dd
					lat = (cp - c).dot(n)
			var room := float(t.cut_half) - (absf(lat) + map.road_w[ri] * 0.5)
			if room < worst:
				worst = room
				worst_s = s
			s += 1.0
		print("underpass street %d (%s, w %.1f): clear %.1f m, bore %.1f m long, cut %.0f m; street edge to wall min %.2f m at s=%.0f" % [
			int(t.road), map.road_name[ri], float(t.w), float(t.cut_half) * 2.0, float(t.half_bore) * 2.0, float(t.half_foot) * 2.0, worst, worst_s])
	root.free()
	quit(0)

func _is_closure(map: TownMap, a: Vector2, b: Vector2) -> bool:
	var m := (a + b) * 0.5
	for c in map.closures:
		if m.distance_to(Vector2(float(c[0]), float(c[1]))) < 0.5:
			return true
	return false

func _round(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[k] = roundi(float(d[k]))
	return o
