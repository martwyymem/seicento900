## Probe (headless): the field of each open-world race (the map missions' sprint, off-road race and knockout, and
## generated live sprints, off-road races and knockouts) run with the player out of the way, at each level: every
## rival's time home against the reference driver (LiveEvents.pace_time), the track build time, the sim's cost, the
## bots' contacts and how often a bot is off the drawn road. OLD=1 runs the old StreetRivals field instead (its
## rubber band held neutral by a player kept level with the pack, out of its way).
##   timeout 900 godot --headless --path godot -s tests/_event_field_probe.gd   (ONLY=sprint_s1,... LEVELS=medium)
extends SceneTree

const DT := 1.0 / 60.0

var map: TownMap

func _initialize() -> void:
	map = TownMap.load_map(OpenWorld.MAP_KEY)
	var only := OS.get_environment("ONLY")
	var old := OS.get_environment("OLD") != ""
	var levels := (OS.get_environment("LEVELS") if OS.get_environment("LEVELS") != "" else "easy,medium,hard").split(",")
	var evs := []
	for k in Missions.MISSIONS.size():
		var m: Dictionary = Missions.MISSIONS[k]
		var ev := MapMissions.event(Missions.BASE + k)
		if not ev.is_empty() and ev.kind == "race" and String(ev.get("grid", "")) != "drag":
			evs.append([String(m.id), ev])
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var home := Vector2(s[0], s[1])
	for kind in ["sprint", "offroad", "knockout"]:
		for seed_value in [11, 22]:
			var live := LiveEvents.new(map, seed_value)
			var ev := live.generate(home, PackedVector2Array(), kind)
			if not ev.is_empty():
				evs.append(["%s/%d" % [kind, seed_value], ev])
	var summary := {}
	for e in evs:
		if only != "" and not String(e[0]) in only.split(","):
			continue
		for lv in levels:
			var r := _run(e[1], lv, old)
			print("%-18s %-6s %s" % [e[0], lv, r.line])
			if not summary.has(lv):
				summary[lv] = []
			(summary[lv] as Array).append_array(r.ratios)
	for lv in summary:
		var a: Array = summary[lv]
		a.sort()
		if a.is_empty():
			continue
		print("ALL %-6s n %d  best %.3f  p25 %.3f  median %.3f  p75 %.3f  worst %.3f" % [lv, a.size(), a[0],
			a[a.size() / 4], a[a.size() / 2], a[a.size() * 3 / 4], a[a.size() - 1]])
	quit()

func _run(ev: Dictionary, level: String, old: bool) -> Dictionary:
	var live := LiveEvents.new(map, 5)
	var path: PackedVector2Array = ev.path
	var n := int(ev.rivals) if OS.get_environment("RIVALS") == "" else int(OS.get_environment("RIVALS"))
	var ref := LiveEvents.pace_time(path, "stock", 0.0, live.grip_of(ev))
	var t0 := Time.get_ticks_usec()
	var field
	var beyond := live.beyond(ev)
	if old:
		var ro := {"knockout": false, "difficulty": level, "profile": live.profile(ev, StreetRivals.STEP), "beyond": beyond}
		field = StreetRivals.new(path, "stock", n, 1234, ro)
	else:
		field = EventField.new(path, "stock", n, 1234, {"map": map, "beyond": beyond, "difficulty": level, "key": "probe"})
		if OS.get_environment("PACEK") != "":
			for b in field.bots:
				b.skill = b.skill / field.pace_k * float(OS.get_environment("PACEK"))
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var far := path[0] + Vector2(600.0, 600.0)
	var t := 0.0
	var off := 0
	var samples := 0
	var sim_us := 0
	var limit := ref * 3.0 + 60.0
	while t < limit:
		t += DT
		var t1 := Time.get_ticks_usec()
		if old:
			var mean := 0.0
			for r in field.rivals:
				mean += float(r.s)
			mean /= maxf(field.rivals.size(), 1)
			var ps: Array = field.pose(mean, 60.0)
			field.step(DT, ps[0], 0.0)
		else:
			field.step(DT, far, 0.0)
		sim_us += Time.get_ticks_usec() - t1
		if int(t * 2.0) != int((t - DT) * 2.0):
			for k in field.rivals.size():
				var r: Dictionary = field.rivals[k]
				if bool(r.get("done", float(r.get("t_done", -1.0)) >= 0.0)) or bool(r.get("out", false)):
					continue
				var q: Vector2 = field.pose(float(r.s), float(r.lat))[0] if old else field.car_pose(k)[0]
				samples += 1
				if map.road_at(q.x, q.y, -INF, 0.5).is_empty():
					off += 1
					if OS.get_environment("OFFDBG") != "" and not old:
						var b: RaceCar = field.bots[k]
						var nr := map.nearest_road(q, 30.0)
						var ex := 99.0
						for m in [1.0, 2.0, 3.0, 5.0, 8.0]:
							if not map.road_at(q.x, q.y, -INF, m).is_empty():
								ex = m
								break
						print("      off bot %d s %.0f d %.2f hw %.1f rl %.2f excess<%.0f m  kc %.3f  at %s nearest road half %.1f" % [k, b.s - field.et.start_s, b.d,
							field.track.half_at(b.s), field.track.sample(field.track.RLD, b.s), ex, field.track.sample(field.track.KC, b.s), q,
							map.road_w[int(nr.get("road", 0))] * 0.5])
		if not old and OS.get_environment("TRACE") != "" and int(t) != int(t - DT) and int(t) % int(OS.get_environment("TRACE")) == 0:
			var b: RaceCar = field.bots[0]
			var tr: Track = field.track
			print("   t %3d s %6.0f v %5.1f prof %5.1f K %.3f d %5.2f hw %4.1f rl %5.2f ctl %s err %s" % [int(t), b.s - field.et.start_s,
				Vector2(b.vx, b.vy).length(), tr.sample(tr.PROF, b.s), b.skill, b.d, tr.half_at(b.s), tr.sample(tr.RLD, b.s), b.control, str(b.err != null)])
		if field.finished_count() >= field.rivals.size():
			break
	var ratios := []
	var unfinished := 0
	for r in field.rivals:
		if float(r.t_done) >= 0.0:
			ratios.append(float(r.t_done) / ref)
		else:
			unfinished += 1
	ratios.sort()
	var txt := "ref %5.1f s  " % ref
	if ratios.size() > 0:
		txt += "rivals/ref %.3f .. %.3f (median %.3f)" % [ratios[0], ratios[ratios.size() - 1], ratios[ratios.size() / 2]]
	txt += "  unfinished %d  off-road %.1f%%  build %.0f ms  sim %.2f ms/s" % [unfinished, 100.0 * off / maxf(samples, 1),
		build_ms, sim_us / 1000.0 / maxf(t, 0.01)]
	if not old:
		var walls := 0
		for e in field.race.events:
			if String(e.text).begins_with("Ouch"):
				walls += 1
		txt += "  phases %s n %d  bot contacts %d knocks %d  wall hits(log) %d" % [str(field.et.phase_ms), field.track.n, field.bot_contacts, field.bot_knocks, walls]
		if OS.get_environment("KNOCKS") != "":
			var hist := {}
			for x in field.bot_knock_s:
				var b := int(x / 100.0) * 100
				hist[b] = int(hist.get(b, 0)) + 1
			txt += "\n      knocks by 100 m: %s" % str(hist)
		field.dispose()
	return {"line": txt, "ratios": ratios}
