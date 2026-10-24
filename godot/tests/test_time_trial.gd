## Time trial: the session's settings, sector times and colours, the live delta, the best and ideal laps,
## invalid laps, the rolling start's run-up, restart, and the lap records it feeds.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	LapRecords._store = null
	LapRecords._memory_ghosts.clear()

	# ---- the settings
	var st := RaceSettings.new()
	st.track = "fiat"
	st.weather = "wet"
	TimeTrial.configure(st, true)
	if st.mode != "time_trial" or st.opponents != 0 or st.laps < 1000 or st.race_control or st.mandatory_stop or st.refuel:
		errors.append("configure: solo, laps until quit, no race control or pit rules")
	if st.wear_mult != 0.0 or st.fuel_mult != 0.0 or not st.rolling_start or st.weather != "wet" or st.starting_tyre != "W":
		errors.append("configure: no wear or fuel use, the chosen conditions kept, wets in the wet")

	# ---- the core: three sectors, colours, delta, best and ideal laps
	var tt := TimeTrial.new()
	tt.set_length(3000.0)
	var drive := func(t1: float, t2: float, t3: float, ok := true) -> Dictionary:
		# constant speed within each sector of 1000 m
		var ts := [t1, t2, t3]
		var t0 := 0.0
		for k in 3:
			for i in 100:
				tt.advance(k * 1000.0 + i * 10.0, t0 + ts[k] * i / 100.0)
			t0 += ts[k]
		return tt.cross(t1 + t2 + t3, ok)
	var l1: Dictionary = drive.call(30.0, 30.0, 30.0)
	if l1.colors != ["purple", "purple", "purple"] or tt.best_lap != 90.0:
		errors.append("the first lap is purple all round and the best: %s" % [l1])
	for k in 3:
		if absf(float(l1.sectors[k]) - 30.0) > 0.35:
			errors.append("sector %d should be about 30 s, got %.2f" % [k + 1, l1.sectors[k]])
	# halfway through lap 2, a second down
	for i in 150:
		tt.advance(i * 10.0, i * 10.0 / 1000.0 * 30.0 + (1.0 if i * 10.0 >= 1000.0 else i / 100.0))
	var dl = tt.delta(1500.0, 46.0)
	if dl == null or absf(dl - 1.0) > 0.05:
		errors.append("delta at 1500 m one second down should be +1.0, got %s" % [dl])
	if tt.current_colors() != ["red"]:
		errors.append("a slower first sector is red, got %s" % [tt.current_colors()])
	tt._begin_lap()
	var l2: Dictionary = drive.call(29.0, 31.0, 30.5) # S1 a new best, S2 and S3 slower
	if l2.colors != ["purple", "red", "red"] or tt.best_lap != 90.0:
		errors.append("lap 2 should be purple / red / red and not the best: %s" % [l2.colors])
	var l3: Dictionary = drive.call(29.5, 30.5, 29.8) # S1 better than lap 1's but not lap 2's; S3 a best
	if l3.colors != ["green", "red", "purple"]:
		errors.append("lap 3 should be green / red / purple, got %s" % [l3.colors])
	var ideal = tt.ideal_lap()
	if ideal == null or absf(ideal - (29.0 + 30.0 + 29.8)) > 0.4:
		errors.append("the ideal lap adds the best sectors (88.8), got %s" % [ideal])
	var l4: Dictionary = drive.call(20.0, 20.0, 20.0, false)
	if l4.valid or l4.colors != ["invalid", "invalid", "invalid"] or tt.best_lap != 89.8:
		errors.append("an invalid lap counts for nothing (best stays lap 3's 89.8, got %s)" % [tt.best_lap])
	if tt.laps.size() != 4 or tt.laps[3].n != 4:
		errors.append("every lap is on the list")
	# against a record faster than any of this session's sectors nothing is purple
	tt.record_sectors = [25.0, 25.0, 25.0]
	if tt.sector_color(0, 28.9) != "green" or tt.sector_color(0, 24.0) != "purple":
		errors.append("purple only at or under the record's sector")

	# ---- a session on the Fiat track: rolling start, laps, invalid laps, records, restart
	LapRecords.count_autopilot = true
	var ts := RaceSettings.new()
	ts.track = "fiat"
	TimeTrial.configure(ts, true)
	var race := Race.new(ts, null, 5)
	var p := race.player
	if race.tt == null or race.rc != null or race.cars.size() != 1:
		errors.append("a time trial: the player alone with a TimeTrial, no race control")
	if not race.tt.out_lap() or p.speed < 10.0 or race.track.rel(p.s) > -100.0:
		errors.append("a rolling start begins at speed on the run-up to the line (s %.0f, %.1f m/s)" % [p.s, p.speed])
	var rec := LapRecords.new(race)
	race.set_autopilot(true)
	var idle := Race.PlayerInput.new()
	var dt := 1.0 / 120.0
	var ticks := 0
	var saw_delta := false
	while race.tt.laps.size() < 2 and ticks < 120 * 400:
		race.step(dt, idle)
		rec.tick()
		ticks += 1
		if race.tt.laps.size() == 1 and race.tt.live_delta() != null:
			saw_delta = true
	if race.tt.laps.size() != 2:
		errors.append("two laps after the run-up, got %d" % race.tt.laps.size())
	else:
		if not race.tt.laps[0].valid or race.tt.laps[0].time < 60.0:
			errors.append("the first lap is a full, valid lap (the run-up isn't one): %s" % [race.tt.laps[0]])
		if not saw_delta:
			errors.append("lap 2 shows a live delta to lap 1")
		if absf(float(race.tt.best_lap) - float(p.best_lap)) > 1e-9:
			errors.append("the session best is the race's best lap")
	if p.fuel != TimeTrial.FUEL or p.tyre.wear != 1.0:
		errors.append("no fuel used, no wear (fuel %.2f, wear %.3f)" % [p.fuel, p.tyre.wear])
	if LapRecords.record("fiat", "dry").is_empty():
		errors.append("a clean flying lap sets the lap record")
	if race.phase != "racing":
		errors.append("a time trial never finishes on its own")
	# off the road: the lap is invalid
	p.d = race.track.half + 3.0
	race.tt.tick()
	if race.tt.valid or not p.invalid_lap:
		errors.append("a car off the tarmac invalidates the lap")
	# restart: back to the start at once, the session kept
	var n_laps := race.tt.laps.size()
	race.tt.restart()
	if p.lap != 0 or race.clock != 0.0 or race.tt.laps.size() != n_laps or not race.tt.valid or race.tt.restarts != 1:
		errors.append("restart: lap 0, clock 0, the laps kept, a clean lap ahead")
	if not race.tt.out_lap() or p.speed < 10.0:
		errors.append("a rolling restart is back on the run-up at speed")
	for i in 240:
		race.step(dt, idle)
	if race.phase != "racing" or p.lap != 0:
		errors.append("after a restart the car runs up to the line again")
	race.dispose()

	# standing start: counts lap 0 from the line, held during the countdown
	var ss := RaceSettings.new()
	ss.track = "fiat"
	TimeTrial.configure(ss, false)
	var sr := Race.new(ss, null, 5)
	if sr.tt.out_lap() or sr.player.speed != 0.0:
		errors.append("a standing start waits at the line")
	sr.tt.restart()
	if sr.phase != "countdown" or absf(sr.lights_out_at - TimeTrial.RESTART_LIGHTS) > 1e-9:
		errors.append("a standing restart has a short countdown")
	sr.dispose()

	LapRecords.count_autopilot = false
	LapRecords._store = null
	LapRecords._memory_ghosts.clear()
	completed = true
	return errors
