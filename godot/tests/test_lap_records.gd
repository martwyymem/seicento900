## Lap records and ghosts: which laps count, the recorded ghost, the live gap to it and the files they keep.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	LapRecords._store = null
	LapRecords._memory_ghosts.clear()
	LapRecords.count_autopilot = false

	var st := RaceSettings.new()
	st.track = "fiat" # the shortest lap
	st.opponents = 0
	st.laps = 4
	st.weather = "dry"
	st.race_control = false
	st.mandatory_stop = false # a lap with a stop in it never counts; keep every lap a flying one
	st.wear_mult = 0.3
	st.fuel_mult = 0.5
	var race := Race.new(st, null, 5)
	race.set_autopilot(true)
	var rec := LapRecords.new(race)
	if rec.ghost_time != null or rec.chasing():
		errors.append("a circuit without a record has no ghost to chase")
	var idle := Race.PlayerInput.new()
	var dt := 1.0 / 120.0
	var p := race.player
	var max_gap := 0.0
	var gaps := 0
	var pose_off := 0.0
	var ticks := 0
	while race.phase != "finished" and ticks < 120 * 1800:
		race.step(dt, idle)
		rec.tick()
		ticks += 1
		var done := p.lap_times.size()
		if done == 1:
			# lap 2 has started under the game's rules (autopilot never counts); count it from lap 3 on
			LapRecords.count_autopilot = true
		if done == 2 and not rec.new_records.is_empty():
			errors.append("an autopilot lap was counted as a record")
			break
		if done == 3 and rec.chasing():
			var g = rec.gap()
			if g != null:
				max_gap = maxf(max_gap, absf(g))
				gaps += 1
			# the ghost a lap-time apart from the player is where the gap says it is
			var pose := rec.pose(race.race_time - p.lap_start)
			if not pose.is_empty() and g != null:
				var ds: float = race.track.rel(pose[3] - p.s)
				pose_off = maxf(pose_off, absf(ds - g * p.v) - 3.0)
	if race.phase != "finished":
		errors.append("the race should finish (%d ticks, lap %d)" % [ticks, p.lap])

	var laps := p.lap_times
	var flying := laps.slice(2) # lap 1 starts on the grid, lap 2 ran with autopilot not counting
	var best: float = flying.min() if not flying.is_empty() else INF
	var r := LapRecords.record("fiat", "dry")
	if not r.has("t") or absf(float(r.t) - best) > 1e-9:
		errors.append("the record should be the best counted lap %s, got %s" % [Race.fmt_time(best), r])
	if rec.new_records.is_empty() or absf(float(rec.new_records[0].t) - float(laps[2])) > 1e-9:
		errors.append("the first counted lap sets the first record")
	if not LapRecords.record("fiat", "wet").is_empty():
		errors.append("a dry race sets no wet record")

	var ghost := LapRecords.load_ghost("fiat", "dry")
	var n := ghost.size() / LapRecords.STRIDE
	if n * LapRecords.DT < best or n * LapRecords.DT > best + 2.0 * LapRecords.DT:
		errors.append("the ghost should cover the lap: %d samples for %s" % [n, Race.fmt_time(best)])
	for i in range(1, n):
		if ghost[i * LapRecords.STRIDE + 3] < ghost[(i - 1) * LapRecords.STRIDE + 3]:
			errors.append("the ghost's distance along the lap goes backwards at sample %d" % i)
			break
	if n > 0 and (ghost[3] > 30.0 or ghost[(n - 1) * LapRecords.STRIDE + 3] < race.track.L - 40.0):
		errors.append("the ghost should run line to line, s %.1f..%.1f of %.1f" % [ghost[3], ghost[(n - 1) * LapRecords.STRIDE + 3], race.track.L])
	if gaps < 100 or max_gap > 1.5:
		errors.append("the gap to the record should be measured through the lap and stay small: %d readings, worst %.2f s" % [gaps, max_gap])
	if pose_off > 3.0:
		errors.append("the ghost's position disagrees with the gap by %.1f m" % pose_off)
	if not rec.pose(1e6).is_empty():
		errors.append("past the end of its lap the ghost is gone")
	race.dispose()

	# a new race on the circuit picks up the record and its ghost
	var again := Race.new(st, null, 6)
	var rec2 := LapRecords.new(again)
	if rec2.ghost_time == null or absf(float(rec2.ghost_time) - best) > 1e-9 or rec2.samples() != n:
		errors.append("the next race on the circuit should chase the saved ghost")
	again.dispose()

	# the files: the store and a ghost survive a reload, and forgetting the circuit removes both
	LapRecords._store = null # the race above lived in memory: don't write it into the sandbox's file
	LapRecords.use_disk = true
	var key := "_test_lap_records"
	var samples := PackedFloat32Array()
	for i in LapRecords.STRIDE * 3:
		samples.append(i * 0.5)
	LapRecords._save_ghost(key, "wet", samples)
	LapRecords.load_store().tracks[key] = {"wet": {"t": 61.25}}
	LapRecords._save_store()
	LapRecords._store = null
	if float(LapRecords.record(key, "wet").get("t", 0.0)) != 61.25 or LapRecords.load_ghost(key, "wet") != samples:
		errors.append("a record and its ghost should be read back from disk")
	LapRecords.forget(key)
	LapRecords._store = null
	if not LapRecords.record(key, "wet").is_empty() or not LapRecords.load_ghost(key, "wet").is_empty():
		errors.append("forgetting a circuit should remove its record and ghost")
	var ghost_pref := LapRecords.ghost_shown(false)
	LapRecords.set_ghost_shown(false, not ghost_pref)
	LapRecords._store = null
	if LapRecords.ghost_shown(false) == ghost_pref:
		errors.append("the ghost preference should be saved")
	LapRecords.set_ghost_shown(false, ghost_pref)

	# ---- records and ghosts are per car; saves from before that count as the stock car's
	LapRecords._store = null
	LapRecords._memory_ghosts.clear()
	LapRecords.use_disk = false
	var legacy := PackedFloat32Array()
	for i in LapRecords.STRIDE * 4:
		legacy.append(i * 0.25)
	LapRecords.load_store().tracks["fiat"] = {"dry": {"t": 70.5, "date": "2026-01-01", "tyre": "M", "assists": "off", "gearbox": "auto"}}
	LapRecords._save_ghost("fiat", "dry", legacy)
	var old := LapRecords.record("fiat", "dry")
	if float(old.get("t", 0.0)) != 70.5 or old.get("car") != "stock" or LapRecords.load_ghost("fiat", "dry") != legacy:
		errors.append("an old record without a car key should load as the stock car's: %s" % [old])
	if LapRecords.record("fiat", "dry", "stock") != old or LapRecords.car_of("") != "stock" or LapRecords.car_of("nonsense") != "stock":
		errors.append("an empty or unknown car key means stock")
	for k in CarCatalog.KEYS:
		if k != "stock" and (not LapRecords.record("fiat", "dry", k).is_empty() or not LapRecords.load_ghost("fiat", "dry", k).is_empty()):
			errors.append("the stock record must not be %s's" % k)
	var other := ""
	for k in CarCatalog.KEYS:
		if k != "stock":
			other = k
			break
	if other == "":
		errors.append("the catalogue should hold a second car")
	else:
		var st2 := RaceSettings.new()
		st2.track = "fiat"
		st2.opponents = 0
		st2.laps = 4
		st2.weather = "dry"
		st2.race_control = false
		st2.mandatory_stop = false
		st2.car_class = other
		var race2 := Race.new(st2, null, 7)
		race2.set_autopilot(true)
		LapRecords.count_autopilot = true
		var rec3 := LapRecords.new(race2)
		if rec3.car_key != other or rec3.ghost_time != null or rec3.chasing():
			errors.append("another car must not chase the stock car's lap (%s, ghost %s)" % [rec3.car_key, rec3.ghost_time])
		var tk := 0
		while race2.phase != "finished" and tk < 120 * 1800:
			race2.step(dt, idle)
			rec3.tick()
			tk += 1
		var mine := LapRecords.record("fiat", "dry", other)
		if mine.is_empty() or mine.get("car") != other or rec3.new_records.is_empty():
			errors.append("the %s should set its own record: %s" % [other, mine])
		if LapRecords.record("fiat", "dry") != old or LapRecords.load_ghost("fiat", "dry") != legacy:
			errors.append("a lap in the %s must leave the stock record and ghost alone" % other)
		if LapRecords.load_ghost("fiat", "dry", other).is_empty():
			errors.append("the %s's ghost should be saved under its own key" % other)
		var rec4 := LapRecords.new(Race.new(st2, null, 8))
		if rec4.ghost_time == null or absf(float(rec4.ghost_time) - float(mine.t)) > 1e-9:
			errors.append("the next race in the %s should chase its record" % other)
		var ghost_node := LapGhost.new()
		Engine.get_main_loop().root.add_child(ghost_node)
		ghost_node.start(null, rec4)
		if ghost_node._visual.car_key != other:
			errors.append("the ghost should draw the %s, got %s" % [other, ghost_node._visual.car_key])
		ghost_node.start(null, LapRecords.new(Race.new(st, null, 9)))
		if ghost_node._visual.car_key != "stock":
			errors.append("a stock lap's ghost draws the stock car")
		ghost_node.free()
		# the file names: stock keeps its old one, others get a suffix
		if not LapRecords._ghost_path("fiat", "dry").ends_with("fiat_dry.ghost") or not LapRecords._ghost_path("fiat", "wet", other).ends_with("fiat_wet_%s.ghost" % other):
			errors.append("ghost file names: stock unchanged, other cars suffixed")
		LapRecords.forget("fiat")
		if not LapRecords.record("fiat", "dry", other).is_empty() or not LapRecords.load_ghost("fiat", "dry", other).is_empty():
			errors.append("forgetting a circuit drops every car's record")
	LapRecords.count_autopilot = false

	LapRecords.use_disk = true
	LapRecords.count_autopilot = false
	LapRecords._store = null
	LapRecords._memory_ghosts.clear()
	if not load("res://scripts/ui/lap_ghost.gd").can_instantiate():
		errors.append("lap_ghost.gd should compile")
	completed = true
	return errors
