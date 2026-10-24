## Rally mode: the events table, a stage's settings, its clock and splits, jump-start and cut penalties,
## the seeded rival model, the stage and overall classification, service between stages and saving.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	var dt := 1.0 / 120.0
	var idle := Race.PlayerInput.new()

	# ---- the events table
	for e in Rally.EVENTS:
		var n: int = e.stages.size()
		if n < 3 or n > 6:
			errors.append("%s: a rally is 3–6 stages, got %d" % [e.key, n])
		if not Race.DIFFICULTY.has(e.difficulty):
			errors.append("%s: unknown difficulty %s" % [e.key, e.difficulty])
		for sd in e.stages:
			if not ResourceLoader.exists("res://data/tracks/%s.tres" % sd.track):
				errors.append("%s: no track %s" % [e.key, sd.track])
			if not Rally.SURFACE_GRIP.has(sd.surface):
				errors.append("%s: unknown surface %s" % [e.key, sd.surface])
			if not sd.weather in ["dry", "wet", "snow", "hail", "fog", "variable"]:
				errors.append("%s: unknown weather %s" % [e.key, sd.weather])
	if Rally.event("nope") != {} or Rally.event("sprint").is_empty():
		errors.append("Rally.event looks an event up by key")
	if absf(Rally.stage_length({"from": 0.0, "to": 0.0}, 3000.0) - 3000.0) > 1e-6 \
			or absf(Rally.stage_length({"from": 1800.0, "to": 0.0}, 3000.0) - 1200.0) > 1e-6 \
			or absf(Rally.stage_length({"from": 500.0, "to": 1500.0}, 3000.0) - 1000.0) > 1e-6:
		errors.append("stage_length: a full lap, a section to the line and a section inside the lap")

	# ---- the settings a stage runs on
	var st := RaceSettings.new()
	st.player_name = "Kubica"
	st.gearbox = "manual"
	Rally.configure_stage(st, {"track": "fiat", "from": 0.0, "to": 0.0, "surface": "gravel", "weather": "dry", "hour": 9.0})
	if st.mode != "rally" or st.opponents != 0 or st.mandatory_stop or st.refuel or not st.race_control or st.ai_learning != "off":
		errors.append("configure_stage: a solo stage with race control for damage, no pit rules, no learning")
	if st.player_name != "Kubica" or st.gearbox != "manual" or st.surface != "gravel" or st.start_hour != 9.0:
		errors.append("configure_stage keeps the player's choices and takes the stage's conditions")
	if RaceSettings.new().mode != "race" or RaceSettings.new().surface != "tarmac":
		errors.append("settings default to a plain race on tarmac")

	# ---- gravel grip, and nothing changes for a race
	var plain := RaceSettings.new()
	plain.track = "fiat"
	plain.opponents = 0
	var pr := Race.new(plain, null, 3)
	if pr.stage != null or pr.tt != null or pr.rc == null:
		errors.append("a plain race has no stage or time-trial tracker")
	var gr := Race.new(st, null, 3)
	gr.player.tyre = pr.player.tyre.duplicate()
	if absf(gr.grip(gr.player) - pr.grip(pr.player) * Rally.SURFACE_GRIP.gravel) > 1e-9:
		errors.append("a gravel stage scales the grip by SURFACE_GRIP.gravel")
	if gr.rc == null or gr.cars.size() != 1 or gr.stage == null:
		errors.append("a stage: the player alone, with race control and a Rally.Stage")
	pr.dispose()
	gr.dispose()

	# ---- the rival model: seeded, incidents only cost time
	var rivals := Rally.make_rivals("medium", 11)
	if rivals.size() != Rally.RIVALS or rivals != Rally.make_rivals("medium", 11):
		errors.append("make_rivals: %d rivals, the same for the same seed" % Rally.RIVALS)
	var base := []
	for r in rivals:
		base.append(150.0 * (1.0 + (0.96 - float(r.skill))))
	var fr := [0.33, 0.66]
	var a := Rally.simulate_rivals(rivals, base, fr, 5, 2, "gravel")
	var b := Rally.simulate_rivals(rivals, base, fr, 5, 2, "gravel")
	var c := Rally.simulate_rivals(rivals, base, fr, 6, 2, "gravel")
	if JSON.stringify(a) != JSON.stringify(b):
		errors.append("simulate_rivals is deterministic for a seed and stage")
	if JSON.stringify(a) == JSON.stringify(c):
		errors.append("another seed gives other runs")
	var incidents := 0
	var worst_form := 0.0
	for seed in 40:
		var runs := Rally.simulate_rivals(rivals, base, fr, seed, 0, "gravel")
		for i in runs.size():
			var x: Dictionary = runs[i]
			if x.dnf:
				incidents += 1
				continue
			worst_form = minf(worst_form, x.time / base[i] - 1.0)
			if x.note != "":
				incidents += 1
			if x.splits[0] >= x.splits[1] or x.splits[1] >= x.time:
				errors.append("rival splits come in order before the finish")
				break
	if worst_form < -0.013:
		errors.append("form on the day is a fraction of a per cent, got %.3f" % worst_form)
	if incidents < 10:
		errors.append("over 40 gravel stages someone should spin or puncture (%d incidents)" % incidents)

	# ---- a stage driven: timed from the start to the finish line, splits on the way
	var ev := RallyEvent.new("sprint", 42)
	var ss := ev.settings_for_stage()
	if ss.track != "wilamowice" or ss.mode != "rally":
		errors.append("settings_for_stage builds the event's first stage")
	var sdef := {"name": "Test", "track": "fiat", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 12.0}
	var rs := RaceSettings.new()
	Rally.configure_stage(rs, sdef)
	var race := Race.new(rs, null, 9)
	ev.begin_stage(race) # rivals simulated for the stage on this race (here: the Fiat track)
	if race.stage.rivals.size() != Rally.RIVALS or race.stage.event != ev:
		errors.append("begin_stage hands the stage its rivals")
	race.set_autopilot(true)
	var ticks := 0
	while race.phase != "finished" and ticks < 120 * 400:
		race.step(dt, idle)
		ticks += 1
	var stg := race.stage
	if race.phase != "finished" or stg.time == null:
		errors.append("the stage should finish at the line (phase %s)" % race.phase)
	else:
		if absf(stg.time - race.player.finish_time) > 1e-9 or absf(stg.time - race.race_time) > 0.1:
			errors.append("stage time %.3f is the finish time, timed at the line" % stg.time)
		if stg.split_times.size() != Rally.SPLITS + 1 or stg.split_times[0] >= stg.split_times[1]:
			errors.append("two splits then the finish, in order: %s" % [stg.split_times])
		if not stg.penalties.is_empty():
			errors.append("a clean autopilot run has no penalties: %s" % [stg.penalties])
		var lead := stg.leader_at(Rally.SPLITS)
		if lead.is_empty() or absf(stg.time / lead.t - 1.0) > 0.06:
			errors.append("the rivals' times should be close to the co-driver's (%.2f vs %s)" % [stg.time, lead])
		var ls := stg.last_split()
		if ls.k != Rally.SPLITS or ls.pos < 1 or ls.pos > Rally.RIVALS + 1:
			errors.append("last_split: the finish, with a stage position")
	var rows := ev.finish_stage(race)
	if rows.size() != Rally.RIVALS + 1 or ev.stage_index != 1 or ev.results.size() != 1:
		errors.append("finish_stage classifies the stage and moves on")
	for i in range(1, rows.size()):
		if rows[i].time < rows[i - 1].time or rows[i].pos != i + 1:
			errors.append("stage results sorted by time")
			break
	race.dispose()

	# ---- a section of the lap
	var sec := RaceSettings.new()
	Rally.configure_stage(sec, {"track": "fiat", "from": 900.0, "to": 1900.0, "surface": "tarmac", "weather": "dry", "hour": 12.0})
	var sr := Race.new(sec, null, 4)
	if absf(sr.player.s - (900.0 - Rally.START_BACK)) > 1e-6:
		errors.append("a section stage starts the car at its start, got s=%.1f" % sr.player.s)
	sr.set_autopilot(true)
	ticks = 0
	while sr.phase != "finished" and ticks < 120 * 200:
		sr.step(dt, idle)
		ticks += 1
	if sr.stage.time == null or sr.stage.time > 60.0 or sr.stage.time < 15.0:
		errors.append("a 1 km section takes 15–60 s, got %s" % [sr.stage.time])
	sr.dispose()

	# ---- jump start: moving before the start costs JUMP_PENALTY
	var jr := Race.new(rs, null, 9)
	var go := Race.PlayerInput.new()
	go.throttle = 1.0
	ticks = 0
	while jr.phase == "countdown" and ticks < 120 * 10:
		jr.step(dt, go)
		ticks += 1
	if not jr.stage.jumped or jr.stage.penalty() != Rally.JUMP_PENALTY:
		errors.append("full throttle before the start is a jump start (+%d s), got %s" % [Rally.JUMP_PENALTY, jr.stage.penalties])
	var held := Race.new(rs, null, 9)
	ticks = 0
	while held.phase == "countdown" and ticks < 120 * 10:
		held.step(dt, idle)
		ticks += 1
	if held.stage.jumped:
		errors.append("a car waiting at the line has not jumped the start")

	# ---- cutting: back on the road far further along than the path driven
	var tr := held.track
	var p := held.player
	var cut := held.stage
	held.phase = "racing"
	held.green_at = held.clock
	var put := func(s: float, d: float, path: float) -> void:
		p.s = s
		p.d = d
		var xy := tr.pos(s, d)
		p.x = xy[0]
		p.y = xy[1]
		p.px = p.x - path
		p.py = p.y
	put.call(400.0, 0.0, 1.0)
	cut.tick(dt, idle)
	put.call(402.0, tr.half + Rally.CUT_MARGIN + 2.0, 2.0)
	cut.tick(dt, idle)
	put.call(500.0, 0.0, 20.0) # 98 m of road for some 22 m driven
	cut.tick(dt, idle)
	if cut.cuts != 1 or absf(cut.penalty() - Rally.CUT_PENALTY) > 1e-9:
		errors.append("a cut costs CUT_PENALTY, got %s" % [cut.penalties])
	put.call(510.0, tr.half + Rally.CUT_MARGIN + 2.0, 10.0)
	cut.tick(dt, idle)
	put.call(560.0, 0.0, 50.0) # off the road alongside it: as long as the road
	cut.tick(dt, idle)
	if cut.cuts != 1:
		errors.append("running wide along the road is not a cut")
	jr.dispose()
	held.dispose()

	# ---- overall classification, superrally, service and saving
	var e2 := RallyEvent.new("bor", 7)
	var mk := func(times: Array, dnf_id := -1) -> Array:
		var out := []
		for i in e2.rivals.size():
			out.append({"id": e2.rivals[i].id, "time": null if e2.rivals[i].id == dnf_id else times[i], "splits": [1.0, 2.0],
				"dnf": e2.rivals[i].id == dnf_id, "note": ""})
		return out
	var t1 := []
	var t2 := []
	for i in e2.rivals.size():
		t1.append(100.0 + i)
		t2.append(200.0 + i)
	e2.record_stage(99.0, [["Jump start", 10.0]], false, [], mk.call(t1)) # 109 with the penalty: P10 of 10 on stage 1
	var s1 := e2.stage_results(0)
	var me1: Dictionary = s1.filter(func(r): return r.is_player)[0]
	if absf(me1.time - 109.0) > 1e-9 or me1.pos != 10:
		errors.append("stage time includes penalties (109 s, P10), got %.1f P%d" % [me1.time, me1.pos])
	e2.record_stage(190.0, [], false, [], mk.call(t2, 3)) # rival 3 retires on stage 2
	var s2 := e2.stage_results(1)
	var r3: Dictionary = s2.filter(func(r): return r.id == 3)[0]
	if not r3.dnf or absf(r3.time - (208.0 + Rally.SUPERRALLY)) > 1e-9:
		errors.append("a retired rival is classified at the slowest time + SUPERRALLY, got %.1f" % r3.time)
	var tab := e2.standings()
	var me: Dictionary = tab.filter(func(r): return r.is_player)[0]
	if absf(me.time - 299.0) > 1e-9 or tab[0].time > tab[-1].time:
		errors.append("overall = the sum of stage times, sorted (me %.1f)" % me.time)
	if me.pos != 1 or me.stage_wins != 1:
		errors.append("299 s beats every rival's 300+ s: P1 with one stage win, got P%d" % me.pos)
	if e2.service_minutes() != Rally.event("bor").stages[2].service:
		errors.append("service_minutes reads the next stage's service halt")
	var late := e2.apply_service({"Body": 0.2, "Engine": 0.0}, e2.service_minutes() + 3)
	if absf(late - 3.0 * Rally.SERVICE_LATE) > 1e-9 or e2.parts.has("Engine") or not e2.parts.has("Body"):
		errors.append("3 minutes over the service allocation cost 3 × SERVICE_LATE")
	if absf(e2.standings().filter(func(r): return r.is_player)[0].time - 299.0 - late) > 1e-9:
		errors.append("the service penalty goes on the overall time")
	var back := RallyEvent.from_dict(JSON.parse_string(JSON.stringify(e2.to_dict())))
	if back.stage_index != 2 or JSON.stringify(back.standings()) != JSON.stringify(e2.standings()):
		errors.append("an event survives a trip through JSON")

	# ---- damage carried into the next stage
	var e3 := RallyEvent.new("sprint", 1)
	e3.parts = {"Suspension": 0.5}
	var dr := Race.new(e3.settings_for_stage(), null, 2)
	e3.begin_stage(dr)
	if absf(dr.player.damage - Service.total({"Suspension": 0.5})) > 1e-9:
		errors.append("begin_stage fits the damage carried in")
	dr.dispose()

	completed = true
	return errors
