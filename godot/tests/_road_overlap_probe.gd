## Headless probe: where two streets' drawn surfaces lie on top of each other away from any junction node (coplanar
## or a few mm apart: they z-fight). Samples every street's centreline and lists the other streets covering the point.
##   godot --headless --path godot -s tests/_road_overlap_probe.gd
extends SceneTree

func _initialize() -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	var nodes: Array = map.node_pos.values()
	var grid := {}
	for q: Vector2 in nodes:
		var k := Vector2i(floori(q.x / 20.0), floori(q.y / 20.0))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(q)
	var pairs := {}
	var metres := 0.0
	var same := 0.0
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		for i in pts.size() - 1:
			var l := pts[i].distance_to(pts[i + 1])
			var steps := maxi(1, int(l / 3.0))
			for k in steps:
				var p := pts[i].lerp(pts[i + 1], (k + 0.5) / steps)
				var ck := map._cell_key(int(floor(p.x / TownMap.CELL)), int(floor(p.y / TownMap.CELL)))
				if not map._seg_cells.has(ck):
					continue
				var hit := -1
				for sid in map._seg_cells[ck]:
					var rj := map._seg_road[sid]
					if rj == ri:
						continue
					var a := map.road_pts[rj][map._seg_i[sid]]
					var b := map.road_pts[rj][map._seg_i[sid] + 1]
					var t := clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
					if p.distance_to(a.lerp(b, t)) < map.road_w[rj] * 0.5 - 0.3:
						hit = rj
						break
				if hit < 0:
					continue
				# away from every junction node by more than the wider street's half width + 2 m
				var clear := true
				var reach := maxf(map.road_w[ri], map.road_w[hit]) * 0.5 + 2.0
				var gk := Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))
				for gx in range(gk.x - 1, gk.x + 2):
					for gy in range(gk.y - 1, gk.y + 2):
						for q: Vector2 in grid.get(Vector2i(gx, gy), []):
							if q.distance_to(p) < reach:
								clear = false
				if not clear:
					continue
				var dz_i := map.road_z[ri][i] if not map.road_z[ri].is_empty() else 0.0
				var dz_h := 0.0 if map.road_z[hit].is_empty() else map.road_z[hit][0]
				if absf(dz_i - dz_h) > 0.5:
					continue # one is on a bridge
				metres += l / steps
				if map.road_rank[ri] == map.road_rank[hit]:
					same += l / steps
				var key := "%d/%d" % [mini(ri, hit), maxi(ri, hit)]
				if not pairs.has(key):
					pairs[key] = [0.0, ri, hit, p]
				pairs[key][0] += l / steps
	print("OVERLAP %.0f m of centreline under another street away from junctions (%.0f m at the same height), %d pairs" % [metres, same, pairs.size()])
	var rows: Array = pairs.values()
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for r in rows.slice(0, 14):
		print("  %.0f m: '%s' %s w %.1f rank %d  x  '%s' %s w %.1f rank %d at %s" % [r[0], map.road_name[r[1]], map.road_kind[r[1]], map.road_w[r[1]],
			map.road_rank[r[1]], map.road_name[r[2]], map.road_kind[r[2]], map.road_w[r[2]], map.road_rank[r[2]], r[3]])
	for r in rows:
		if "Kosynier" in map.road_name[r[1]] or "Kosynier" in map.road_name[r[2]]:
			print("  KOS %.0f m: '%s' %s x '%s' %s at %s" % [r[0], map.road_name[r[1]], map.road_kind[r[1]], map.road_name[r[2]], map.road_kind[r[2]], r[3]])
	quit()
