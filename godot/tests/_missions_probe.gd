## Probe (headless): runs each campaign mission's race rules once and prints the numbers the missions are tuned on.
##   timeout 900 godot --headless --path godot -s tests/_missions_probe.gd   (ONLY=drag,drift,... to pick)
extends SceneTree

const DT := 1.0 / 120.0

func _initialize() -> void:
	var only := OS.get_environment("ONLY")
	var want := func(k: String) -> bool: return only == "" or k in only.split(",")
	if want.call("steer"):
		for sgn in [1.0, -1.0]:
			var r := _drag(402.0, "auto", sgn, 7)
			print("steer sign %+.0f: |d| max %.2f  finished %s  time %s" % [sgn, r.dmax, r.fin, r.t])
	if want.call("drag"):
		for dist in [402.0, 1000.0]:
			for box in ["auto", "manual"]:
				for seed in [1, 2, 3]:
					var r := _drag(dist, box, 1.0, seed)
					print("drag %4d m %-6s seed %d: player %s  P%d  field %s  0-100 %s" % [dist, box, seed, r.t, r.pos, r.field, r.t100])
	if want.call("knockout"):
		_knockout()
	if want.call("sprint"):
		_field_race("sprint", "s1_sprint", 1, 7, "easy", {})
	if want.call("offroad"):
		_field_race("offroad", "kolonia_stawowa", 1, 5, "easy", {"loose_spans": true})
	if want.call("drift"):
		for key in (OS.get_environment("TRACKS") if OS.get_environment("TRACKS") != "" else "babudy_gora").split(","):
			for style in ["none", "tidy", "flick", "hard"]:
				_drift(key, style, float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 2600.0)
	quit()

func _settings(track: String, laps: int, opp: int, diff: String) -> RaceSettings:
	var st := RaceSettings.new()
	st.track = track
	st.laps = laps
	st.opponents = opp
	st.difficulty = diff
	st.mandatory_stop = false
	st.weather = "dry"
	st.ai_learning = "off"
	return st

func _steer(race: Race, c: RaceCar, sgn: float, look := 12.0) -> float:
	var tr := race.track
	var aim := tr.pos(c.s + look, 0.0)
	var want := atan2(aim[1] - c.y, aim[0] - c.x)
	var err := wrapf(want - c.heading, -PI, PI)
	return clampf(sgn * err * 2.2, -1.0, 1.0)

func _drag(dist: float, box: String, sgn: float, seed: int) -> Dictionary:
	var st := _settings("s1_sprint", 1, 3, OS.get_environment("DIFF") if OS.get_environment("DIFF") != "" else "easy")
	st.finish_distance = dist
	st.grid = "pole"
	st.gearbox = box
	var race := Race.new(st, null, seed)
	var inp := Race.PlayerInput.new()
	var dmax := 0.0
	var t100 = null
	var n := 0
	while race.phase != "finished" and n < 120 * 120:
		var p := race.player
		inp.throttle = 1.0
		inp.steer = _steer(race, p, sgn, 25.0)
		inp.shift_up = box == "manual" and p.rpm > race.spec.limiter - 150.0
		if box == "manual" and p.gear == 0 and race.phase == "racing":
			inp.shift_up = true
		race.step(DT, inp)
		if race.phase == "racing":
			dmax = maxf(dmax, absf(p.d))
		if t100 == null and absf(p.speed) * 3.6 >= 100.0:
			t100 = race.race_time
		n += 1
	var rows := race.results()
	var me: Dictionary = rows.filter(func(r): return r.car.is_player)[0]
	var field := []
	for r in rows:
		field.append("%s%s" % ["*" if r.car.is_player else "", "%.2f" % r.total if r.total != null else "-"])
	race.dispose()
	return {"t": "%.3f" % me.total if me.total != null else "-", "pos": me.pos, "field": " ".join(field), "dmax": dmax,
		"fin": race.player.finished, "t100": ("%.1f" % t100) if t100 != null else "-"}

func _knockout() -> void:
	for seed in [1, 2]:
		var st := _settings("bor", 5, 5, "medium")
		st.knockout = true
		var race := Race.new(st, null, seed)
		race.set_autopilot(true)
		var idle := Race.PlayerInput.new()
		var n := 0
		while race.phase != "finished" and n < 120 * 1500:
			race.step(DT, idle)
			n += 1
		var outs := race.knocked_out.map(func(e): return "%s(lap %d)" % [e.car.name, e.lap])
		var rows := race.results().map(func(r): return "P%d %s%s" % [r.pos, r.car.name, " DNF" if r.car.dnf else ""])
		print("knockout seed %d: %.0f s, out: %s\n   classification: %s" % [seed, race.race_time, ", ".join(outs), ", ".join(rows)])
		race.dispose()

func _field_race(label: String, track: String, laps: int, opp: int, diff: String, extra: Dictionary) -> void:
	var st := _settings(track, laps, opp, diff)
	for k in extra:
		st.set(k, extra[k])
	var race := Race.new(st, null, 5)
	race.set_autopilot(true)
	var idle := Race.PlayerInput.new()
	var n := 0
	while race.phase != "finished" and n < 120 * 1200:
		race.step(DT, idle)
		n += 1
	var rows := race.results().map(func(r): return "P%d %s %s%s" % [r.pos, r.car.name.get_slice(" ", 1), Race.fmt_time(r.total), (" " + r.status) if r.status != "" else ""])
	var dnf := race.cars.filter(func(c): return c.dnf or c.running).size()
	print("%s %s: phase %s after %.0f s, not home: %d\n   %s" % [label, track, race.phase, race.race_time, dnf, ", ".join(rows)])
	race.dispose()

## A scripted drifter: follows the road, flicks the handbrake into the tighter bends, holds the throttle through.
func _drift(track: String, style: String, dist: float) -> void:
	var st := _settings(track, 1, 0, "easy")
	st.drift_score = true
	st.finish_distance = dist
	st.assists = "abs"
	var race := Race.new(st, null, 3)
	var inp := Race.PlayerInput.new()
	var tr := race.track
	var hb_t := 0.0
	var n := 0
	var offs := 0
	while race.phase != "finished" and n < 120 * 600:
		var p := race.player
		var v := absf(p.speed)
		var k := 0.0
		for a in [10.0, 20.0, 30.0]:
			k = maxf(k, absf(tr.sample(tr.KC, p.s + a)))
		var target := tr.sample(tr.PROF, p.s + 25.0) * (0.85 if style == "none" or style == "tidy" else 0.95)
		inp.throttle = 1.0 if v < target else 0.2
		inp.brake = 0.6 if v > target + 4.0 else 0.0
		inp.steer = _steer(race, p, 1.0, 6.0 + v * 0.45)
		if style != "none" and style != "tidy" and hb_t <= 0.0 and k > (0.025 if style == "flick" else 0.015) and v > 11.0:
			hb_t = 0.35 if style == "flick" else 0.6
		inp.handbrake = 1.0 if hb_t > 0.0 else 0.0
		hb_t -= DT
		if style == "tidy":
			inp.handbrake = 0.0
		race.step(DT, inp)
		if absf(p.d) > tr.half + 0.8:
			offs += 1
		n += 1
	var ds := race.drift
	print("drift %s %4.0f m %-5s: %s s  score %d  best combo %d  lost %d  ticks off %d  finished %s" % [track, dist, style,
		"%.1f" % race.race_time, ds.score, ds.best_combo, ds.lost, offs, race.player.finished])
	race.dispose()
