## Race soak test (dev tool): runs short races on every TRACKS circuit across a matrix of settings (weather,
## night, timed races, refuelling and tyre rules, time warp) with the player on autopilot, and reports
## anything that looks wrong: values that are not finite, cars that stop making progress, results out of
## order, fuel or wear out of range, plans that run out.
## TRACKS=gp,monaco godot --headless --path godot -s tests/_soak.gd
extends SceneTree

const CONFIGS := [
	{"weather": "variable", "laps": 3, "refuel": true, "two_compounds": false, "warp": 30, "start_hour": 14.0},
	{"weather": "wet", "laps": 2, "refuel": false, "two_compounds": true, "warp": 1, "start_hour": 21.5},
	{"format": "time", "hours": 0.25, "weather": "dry", "refuel": true, "two_compounds": true, "warp": 30, "start_hour": 5.0},
	{"format": "time", "hours": 0.3, "weather": "variable", "refuel": false, "two_compounds": false, "warp": 30, "start_hour": 19.0},
	{"laps": 62, "weather": "variable", "refuel": true, "two_compounds": false, "warp": 30, "start_hour": 12.0, "crew": "amateur"},
]

var problems := 0

func _initialize() -> void:
	Brain.use_disk = false
	var keys := (OS.get_environment("TRACKS") if OS.get_environment("TRACKS") else "gp").split(",")
	var only := int(OS.get_environment("CONFIG")) if OS.get_environment("CONFIG") else -1
	var seed := 100
	for key in keys:
		for ci in CONFIGS.size():
			if only >= 0 and ci != only:
				continue
			seed += 1
			_run(key, ci, CONFIGS[ci], seed)
	print("SOAK done: %d problem(s)" % problems)
	quit()

func _flag(tag: String, text: String) -> void:
	problems += 1
	print("  !! %s %s" % [tag, text])

func _run(key: String, ci: int, cfg: Dictionary, seed: int) -> void:
	var st := RaceSettings.new()
	st.track = key
	st.grid = "random"
	st.difficulty = ["easy", "medium", "hard", "alien"][seed % 4]
	st.opponents = 15
	for k in cfg:
		if k != "warp":
			st.set(k, cfg[k])
	if key in ["nordschleife", "lemans"] and st.format == "laps":
		st.laps = 1
	var tag := "%s#%d" % [key, ci]
	var t0 := Time.get_ticks_msec()
	var race := Race.new(st, null, seed)
	race.set_autopilot(true)
	race.warp = int(cfg.warp)
	var inp := Race.PlayerInput.new()
	var ticks := 0
	var t := 0.0
	var last_progress := {}
	var stalled := {}
	# room for every lap three times over (stops, rain, safety cars): a 62-lap GP with an amateur crew and two
	# showers really takes just over 4 hours, which a flat 4-hour cap reported as a race that never ends
	var limit := maxf(3600.0 * 4.0, race.R * race.cal.T0 * 3.0)
	while race.phase != "finished" and t < limit:
		var dt := 1.0 / 120.0 if race.warp == 1 or race.player.control == "free" else 1.0 / 30.0
		race.step(dt, inp)
		t += dt
		ticks += 1
		if ticks % 240 != 0:
			continue
		for c in race.cars:
			for f in ["x", "y", "s", "d", "v", "heading", "fuel"]:
				var v = c.get(f)
				if not is_finite(float(v)):
					_flag(tag, "t=%.0f %s.%s = %s" % [race.race_time, c.name, f, v])
			if c.fuel < -0.01:
				_flag(tag, "t=%.0f %s fuel %.2f" % [race.race_time, c.name, c.fuel])
			if c.tyre.wear < -0.001 or c.tyre.wear > 1.001:
				_flag(tag, "t=%.0f %s wear %.3f" % [race.race_time, c.name, c.tyre.wear])
			if race.phase == "racing" and not c.finished and not c.dnf and c.mode == "race":
				var prog: float = c.lap * race.track.L + c.s
				if last_progress.has(c.id) and prog - last_progress[c.id] < 1.0:
					stalled[c.id] = stalled.get(c.id, 0) + 1
					if stalled[c.id] == 15: # 30 s of race time without moving a metre
						_flag(tag, "t=%.0f %s stalled at s=%.0f lap %d (control %s, v %.1f)" % [race.race_time, c.name, c.s, c.lap, c.control, c.v])
				else:
					stalled[c.id] = 0
				last_progress[c.id] = prog
	var ms := Time.get_ticks_msec() - t0
	if race.phase != "finished":
		_flag(tag, "not finished after %.0f s of race (phase %s)" % [t, race.phase])
	var res := race.results()
	var prev = null
	var stops := 0
	var dnfs := 0
	for r in res:
		stops += r.car.stops
		if r.car.dnf:
			dnfs += 1
		if not r.car.dnf and r.total != null and not is_finite(float(r.total)):
			_flag(tag, "%s total %s" % [r.car.name, r.total])
		if prev != null and not prev.car.dnf and not r.car.dnf and race.phase == "finished":
			if r.laps > prev.laps or (r.laps == prev.laps and r.total != null and prev.total != null and r.total < prev.total - 1e-6):
				_flag(tag, "results out of order: P%d %s (%d laps %s) ahead of P%d %s (%d laps %s)" % [
					prev.pos, prev.car.name, prev.laps, Race.fmt_time(prev.total), r.pos, r.car.name, r.laps, Race.fmt_time(r.total)])
		prev = r
	var bad := 0
	for e in race.events:
		var low: String = str(e.text).to_lower()
		if "nan" in low.split(" ") or " inf" in low or "null" in low:
			bad += 1
			_flag(tag, "event text: %s" % e.text)
	if dnfs == res.size():
		_flag(tag, "every car retired (%s)" % (res[0].car.dnf_reason if res.size() else ""))
	print("%s: %s in %.0f s race time (%d ms), %d stops, %d DNF, winner %s" % [tag, race.phase, t, ms, stops, dnfs,
		res[0].car.name if res.size() else "-"])
	race.dispose()
