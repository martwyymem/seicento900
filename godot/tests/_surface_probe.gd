## Surface handling probe: measures the stock Seicento on each surface, dry and wet, in the race physics and the
## open-world FreeCar, plus a rally stage on gravel against tarmac; then runs tests/test_surfaces.gd.
## godot --headless --path godot -s tests/_surface_probe.gd
extends SceneTree

const S := preload("res://tests/test_surfaces.gd")

func _row(rig: String, surf: String, mu: float, m: Dictionary) -> void:
	print("%-8s %-14s %4.2f  %6s  %6.1f  %6.1f  %6.1f  %5.2f  %5.1f" % [rig, surf, mu,
		"%.2f" % m.t100 if m.t100 < INF else "never", m.v30, m.brake, m.coast, m.lat_g, m.skid_v])

func _initialize() -> void:
	await process_frame
	print("rig      surface        mu    0-100s  v30kmh  brake_m coast5s lat_g  skid_kmh")
	var ids := S.surf_ids()
	var dry := {}
	for rig in ["physics", "freecar"]:
		for sname in ids:
			for mu in [1.0, 0.7]:
				var r = S.PhysRig.new(ids[sname], mu) if rig == "physics" else S.FreeRig.new(ids[sname], mu)
				var m := S.measure(r)
				_row(rig, sname, mu, m)
				if rig == "physics":
					dry[sname + ("" if mu == 1.0 else " wet")] = m
	# the summary: every surface against dry tarmac (race physics; the open-world car matches it)
	print("---- against dry tarmac (physics rig)")
	print("surface          0-100      v30         brake      lat_g")
	var t0: Dictionary = dry.tarmac
	for sname in dry:
		var m: Dictionary = dry[sname]
		print("%-14s  %+6.1f%%  %+6.1f km/h  %+6.1f%%  %+6.1f%%" % [sname, (S.accel_score(m) / S.accel_score(t0) - 1.0) * 100.0,
			m.v30 - t0.v30, (m.brake / t0.brake - 1.0) * 100.0, (m.lat_g / t0.lat_g - 1.0) * 100.0])
	# a rally stage: Race.grip and Race.surface_at as the race uses them
	for surface in ["tarmac", "gravel"]:
		var race := S.rally_race(surface)
		var p := race.player
		var g := race.grip(p)
		var sid := race.surface_at(p, p.x, p.y)
		_row("rally", "%s(s%d)" % [surface, sid], g, S.measure(S.PhysRig.new(sid, g)))
		var k: float = Physics.SURF_STEER[sid]
		print("    max_steer at 20 m/s: %.4f rad (env.mu %.3f, SURF_STEER %.2f)" % [p.physics.max_steer(20.0, g, k), g, k])
		race.dispose()
	# what the open world's baked roads map to
	var tm := TownMap.new()
	for code in [0, 1, 2]:
		print("TownMap.surface_of(baked surface %d) -> SURF %d" % [code, tm.surface_of({"dist": 0.0, "half": 3.0, "surface": code})])
	var map := TownMap.load_map("brzeszcze")
	if map:
		var len_by := {0: 0.0, 1: 0.0, 2: 0.0}
		for ri in map.road_pts.size():
			var pts: PackedVector2Array = map.road_pts[ri]
			var l := 0.0
			for i in pts.size() - 1:
				l += pts[i].distance_to(pts[i + 1])
			len_by[map.road_surface[ri]] = len_by.get(map.road_surface[ri], 0.0) + l
		print("Brzeszcze road km by baked surface: ", len_by.keys().map(func(k): return "%d: %.1f" % [k, len_by[k] / 1000.0]))
		# what the car actually gets on the real map: sample segment midpoints, and drive the longest straight of each kind
		var hist := {0: {}, 1: {}, 2: {}}
		var longest := {0: [0.0, Vector2.ZERO, 0.0], 1: [0.0, Vector2.ZERO, 0.0], 2: [0.0, Vector2.ZERO, 0.0]}
		for ri in map.road_pts.size():
			var pts: PackedVector2Array = map.road_pts[ri]
			var code: int = map.road_surface[ri]
			for i in pts.size() - 1:
				var mid := (pts[i] + pts[i + 1]) * 0.5
				var hit := map.road_at(mid.x, mid.y, map.ground(mid.x, mid.y) + map.deck_at(ri, i, 0.5))
				var sid := map.surface_of(hit)
				hist[code][sid] = hist[code].get(sid, 0) + 1
				var l := pts[i].distance_to(pts[i + 1])
				if l > longest[code][0] and map.road_z[ri].is_empty():
					longest[code] = [l, pts[i], (pts[i + 1] - pts[i]).angle()]
		for code in hist:
			print("  baked %d: segment midpoints -> SURF ids %s" % [code, hist[code]])
		for code in [0, 2]:
			# the longest road of this kind, driven flat out for 20 s with a pure-pursuit steer along its centreline
			var best_ri := -1
			var best_l := 0.0
			for ri in map.road_pts.size():
				if map.road_surface[ri] != code or not map.road_z[ri].is_empty():
					continue
				var pts: PackedVector2Array = map.road_pts[ri]
				var l := 0.0
				for i in pts.size() - 1:
					l += pts[i].distance_to(pts[i + 1])
				if l > best_l:
					best_l = l
					best_ri = ri
			var path: PackedVector2Array = map.road_pts[best_ri]
			var fc := FreeCar.new(map)
			fc.place(path[0], (path[1] - path[0]).angle())
			var seen := {}
			var t := 0.0
			var t60 := INF
			var vmax := 0.0
			var k := 0
			while t < 20.0 and k < path.size() - 1:
				var c := Vector2(fc.car.x, fc.car.y)
				while k < path.size() - 1 and path[k].distance_to(c) < 12.0:
					k += 1
				var want := (path[k] - c).angle()
				var steer := clampf(wrapf(want - fc.car.heading, -PI, PI) * 2.5, -1.0, 1.0)
				fc.step(S.DT, 1.0, 0.0, steer)
				t += S.DT
				seen[fc.surface] = seen.get(fc.surface, 0) + 1
				vmax = maxf(vmax, fc.speed_kmh())
				if t60 == INF and fc.speed_kmh() >= 60.0:
					t60 = t
			print("  real map, baked %d road %d (%.0f m): %.1f s driven, top %.1f km/h, 0-60 %s s, surfaces %s" % [code, best_ri, best_l, t, vmax, "%.1f" % t60 if t60 < INF else "never", seen])

	print("---- tests/test_surfaces.gd")
	var suite = S.new()
	var errors: Array = suite.run()
	if not suite.completed:
		errors.append("run() aborted by a script error")
	for e in errors:
		print("  FAIL ", e)
	print("%d failure(s)" % errors.size())
	quit()
