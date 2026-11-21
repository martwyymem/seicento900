## Campaign missions (Missions): the data, the saves (on a file of this suite's own: the dev sandbox is shared),
## the race rules each kind needs run as real headless races (knockout eliminations and classification, a drag
## race ending at its distance, a sprint, an off-road race everybody finishes), the drift score and its tiers
## against a scripted driver, judging a result, and the beacons in the open world.
extends RefCounted

var completed := false

const DT := 1.0 / 120.0
const TEST_SAVE := "test_missions_campaign.json"

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	_data(errors)
	var saved_file := Campaign.save_file
	Campaign.save_file = TEST_SAVE
	_saves(errors)
	Campaign.save_file = saved_file
	_drift_unit(errors)
	_knockout(errors)
	_drag(errors)
	_field_race(errors, "offroad", "kolonia_stawowa", 4, {"loose_spans": true})
	_field_race(errors, "sprint", "s1_sprint", 3, {})
	_drift_driver(errors)
	_beacons(errors)
	_map_starts(errors)
	completed = true
	return errors

func _data(errors: Array[String]) -> void:
	var kinds := {}
	var ids := {}
	var acts := {}
	for k in Missions.MISSIONS.size():
		var m: Dictionary = Missions.MISSIONS[k]
		var tag := "mission %s" % m.id
		kinds[m.kind] = true
		acts[int(m.act)] = true
		if ids.has(m.id):
			errors.append("%s: id used twice" % tag)
		ids[m.id] = true
		if not m.kind in Missions.KINDS:
			errors.append("%s: unknown kind %s" % [tag, m.kind])
		if int(m.after) < 0 or int(m.after) >= Campaign.STAGES.size() or Campaign.STAGES[int(m.after)].get("fan_lock", false):
			errors.append("%s: waits for stage %d, which is not a stage the chain clears" % [tag, int(m.after)])
		if Track.load_def(String(m.track)) == null:
			errors.append("%s: no track %s" % [tag, m.track])
		if not m.has("reward_car") or (String(m.reward_car) != "" and (not CarCatalog.is_key(String(m.reward_car)) or String(m.reward_car) in ["stock", "hypercar"])):
			errors.append("%s: reward_car must be there, empty or a catalogue car won by missions" % tag)
		if m.kind == "rally":
			if Rally.event(String(m.rally)).is_empty():
				errors.append("%s: no rally event %s" % [tag, m.rally])
		elif m.kind == "drift":
			var t: Array = m.tiers
			if t.size() != 3 or not (int(t[0]) > 0 and int(t[0]) < int(t[1]) and int(t[1]) < int(t[2])):
				errors.append("%s: tiers must rise bronze < silver < gold: %s" % [tag, t])
		else:
			if int(m.target) < 1 or int(m.target) > int(m.opponents) + 1:
				errors.append("%s: target P%d with %d rivals" % [tag, int(m.target), int(m.opponents)])
		if m.kind == "drag" and (float(m.finish_distance) <= 0.0 or float(m.finish_distance) > Race.get_track(String(m.track)).L * 0.5):
			errors.append("%s: drag distance %.0f m" % [tag, float(m.finish_distance)])
		var st := Campaign.get_stage(Missions.BASE + k)
		if String(st.get("kind", "")) != String(m.kind) or not st.has("target_pos") or not st.has("desc"):
			errors.append("%s: Campaign.get_stage does not read it as a mission stage" % tag)
		if Missions.target_text(Missions.BASE + k) == "" or Missions.length_text(Missions.BASE + k) == "":
			errors.append("%s: no target or length text" % tag)
	for kind in Missions.KINDS:
		if not kinds.has(kind):
			errors.append("no mission of kind %s" % kind)
	for a in [1, 2, 3]:
		if not acts.has(a):
			errors.append("no mission in act %d" % a)
	if Missions.is_mission(Campaign.STAGES.size() - 1) or not Missions.is_mission(Missions.BASE):
		errors.append("Missions.is_mission mixes stages and missions")

func _write(prog: Dictionary) -> Dictionary:
	Campaign.save_progress(prog)
	return Campaign.load_progress()

func _saves(errors: Array[String]) -> void:
	var drag := Missions.index_of("drag_quarter")
	var ko := Missions.index_of("knockout_bor")
	# an old save from before the missions: nothing is open past the first stage, nothing cleared, no crash
	var prog := _write({"unlocked": 0, "best_pos": {}, "trophies": []})
	if Missions.is_unlocked(drag, prog) or Campaign.is_unlocked(drag):
		errors.append("save: the quarter mile is open before stage 1 is cleared")
	if Missions.is_cleared(drag, prog) or int(Campaign.get_stage(ko).fails) != 0:
		errors.append("save: an old save without missions reads as progress")
	prog = _write({"unlocked": 1, "best_pos": {"0": 2}, "trophies": [Campaign.STAGES[0].trophy]})
	if not Missions.is_unlocked(drag, prog) or Missions.is_unlocked(ko, prog):
		errors.append("save: stage 1 cleared should open the quarter mile and not the Bór knockout")
	# a miss eases the field (knockout: medium -> easy), a clear pays the first-clear fans once
	var miss := Missions.record(ko, {"pos": 5, "success": false})
	var eased := Campaign.get_stage(ko)
	if miss.success or String(eased.difficulty) != "easy" or int(eased.eased) != 1:
		errors.append("save: a missed knockout should ease it to easy, got %s (eased %d)" % [eased.difficulty, int(eased.eased)])
	var first := Missions.record(ko, {"pos": 1, "success": true})
	var again := Missions.record(ko, {"pos": 2, "success": true})
	if not first.first_clear or again.first_clear or int(again.fans) >= int(first.fans) or int(first.fans) <= 0:
		errors.append("save: first clear %s (%d fans), repeat %s (%d fans)" % [first.first_clear, first.fans, again.first_clear, again.fans])
	prog = Campaign.load_progress()
	var p := Missions.progress(prog, ko)
	if not bool(p.get("cleared", false)) or int(p.get("best", 0)) != 1 or p.has("fails") or int(p.get("tries", 0)) != 3:
		errors.append("save: knockout progress after miss, win, P2: %s" % p)
	# the Bór knockout awards the Golf IV: in the save's cars list once, and unlocked in the catalogue
	if String(first.reward_car) != "golf4" or String(again.reward_car) != "" or prog.get("cars", []) != ["golf4"]:
		errors.append("save: knockout car reward %s / %s, cars %s" % [first.reward_car, again.reward_car, prog.get("cars", [])])
	if not CarCatalog.unlocked("golf4") or not CarCatalog.unlock_hint("golf4").contains("Bór"):
		errors.append("save: golf4 not unlocked after the knockout, or hint '%s'" % CarCatalog.unlock_hint("golf4"))
	# Rajd Borów awards the Dacia Logan on its first podium, alongside the Golf already won
	var rally := Missions.index_of("rally_bor")
	var rally_first := Missions.record(rally, {"pos": 3, "success": true})
	prog = Campaign.load_progress()
	if String(rally_first.reward_car) != "logan" or prog.get("cars", []) != ["golf4", "logan"]:
		errors.append("save: rally car reward %s, cars %s" % [rally_first.reward_car, prog.get("cars", [])])
	if not CarCatalog.unlocked("logan") or not CarCatalog.unlock_hint("logan").contains("Rajd Borów"):
		errors.append("save: logan not unlocked after the rally, or hint '%s'" % CarCatalog.unlock_hint("logan"))
	# the standing kilometre awards the Volvo V50, the third car
	var km_first := Missions.record(Missions.index_of("drag_kilometre"), {"pos": 1, "success": true})
	prog = Campaign.load_progress()
	if String(km_first.reward_car) != "v50" or prog.get("cars", []) != ["golf4", "logan", "v50"]:
		errors.append("save: kilometre car reward %s, cars %s" % [km_first.reward_car, prog.get("cars", [])])
	if not CarCatalog.unlocked("v50") or not CarCatalog.unlock_hint("v50").contains("Kilometr na S1"):
		errors.append("save: v50 not unlocked after the kilometre, or hint '%s'" % CarCatalog.unlock_hint("v50"))
	if Campaign.STAGES[4].trophy in prog.get("trophies", []) or int(prog.get("unlocked", 0)) != 1:
		errors.append("save: a mission touched the stage chain: %s" % prog)
	# a drift keeps its best score and tier, and never eases
	var drift := Missions.index_of("drift_babudy")
	Missions.record(drift, {"pos": 3, "score": 900, "tier": 1, "success": true})
	Missions.record(drift, {"pos": 999, "score": 100, "tier": 0, "success": false})
	p = Missions.progress(Campaign.load_progress(), drift)
	if int(p.get("best", 0)) != 900 or int(p.get("tier", 0)) != 1 or int(Campaign.get_stage(drift).eased) != 0:
		errors.append("save: drift progress %s" % p)
	# RESET CAMPAIGN wipes the missions with the rest
	Campaign.reset_progress()
	prog = Campaign.load_progress()
	if prog.has("missions") or Missions.is_cleared(ko, prog):
		errors.append("save: reset left mission progress: %s" % prog)
	DirAccess.remove_absolute(SaveData.path(TEST_SAVE))

func _drift_unit(errors: Array[String]) -> void:
	var d := DriftScore.new()
	for i in 366: # 3.05 s at 20 m/s and 0.5 rad
		d.step(20.0, 0.5, false, false, DT)
	var combo := 366 * DT * 20.0 * 3.6 * 0.5 * DriftScore.RATE
	if absf(d.combo - combo) > combo * 0.01 or absf(d.mult - 2.0) > 0.01 or d.score != 0:
		errors.append("drift: 3 s slide gives combo %.0f x%.2f (want %.0f x2.00), score %d" % [d.combo, d.mult, combo, d.score])
	for i in int(DriftScore.LINK / DT) + 2:
		d.step(20.0, 0.05, false, false, DT)
	if absi(d.score - int(combo * 2.0)) > 2 or d.combo != 0.0 or d.best_combo != d.score:
		errors.append("drift: the combo should bank to %d after %.1f s straight, score %d" % [int(combo * 2.0), DriftScore.LINK, d.score])
	var banked := d.score
	for i in 120:
		d.step(20.0, 0.6, false, false, DT)
	d.step(20.0, 0.6, false, true, DT) # a crash
	if d.score != banked or d.combo != 0.0 or d.lost != 1:
		errors.append("drift: a crash should lose the combo and keep the score (score %d, combo %.0f, lost %d)" % [d.score, d.combo, d.lost])
	for i in 120:
		d.step(20.0, 0.6, false, false, DT)
	d.step(20.0, 0.6, true, false, DT) # off the road
	if d.score != banked or d.lost != 2:
		errors.append("drift: leaving the road should lose the combo")
	var none := DriftScore.new()
	for i in 240:
		none.step(5.0, 0.8, false, false, DT) # too slow
		none.step(25.0, 0.1, false, false, DT) # too straight
		none.step(25.0, 2.5, false, false, DT) # a spin
	if none.total() != 0:
		errors.append("drift: slow, straight or spinning scored %d" % none.total())
	# two slides linked within LINK s multiply each other
	var linked := DriftScore.new()
	for slide in 2:
		for i in 60:
			linked.step(20.0, 0.5, false, false, DT)
		for i in 60:
			linked.step(20.0, 0.0, false, false, DT)
	if linked.mult < 1.0 + DriftScore.MULT_STEP - 1e-6 or linked.score != 0:
		errors.append("drift: linked slides should still be one combo with a raised multiplier (x%.2f, score %d)" % [linked.mult, linked.score])
	if DriftScore.tier(599, [600, 2500, 6000]) != 0 or DriftScore.tier(2500, [600, 2500, 6000]) != 2 or DriftScore.tier(9999, [600, 2500, 6000]) != 3:
		errors.append("drift: tier boundaries")

func _settings_for(track: String, laps: int, opp: int, diff := "easy") -> RaceSettings:
	var st := RaceSettings.new()
	st.track = track
	st.laps = laps
	st.opponents = opp
	st.difficulty = diff
	st.mandatory_stop = false
	st.ai_learning = "off"
	st.weather = "dry"
	return st

func _run(race: Race, input: Race.PlayerInput, secs: float) -> void:
	var n := 0
	while race.phase != "finished" and n < int(secs / DT):
		race.step(DT, input)
		n += 1

## Four cars, three laps of the Fiat track: one car out at each of the first two laps, the last two race the
## third; the classification runs in reverse order of leaving.
func _knockout(errors: Array[String]) -> void:
	var st := _settings_for("fiat", 3, 3, "medium")
	st.knockout = true
	st.mission = "knockout"
	var race := Race.new(st, null, 11)
	race.set_autopilot(true)
	_run(race, Race.PlayerInput.new(), 900.0)
	if race.phase != "finished":
		errors.append("knockout: not finished after 900 s")
	if race.knocked_out.size() != 2 or int(race.knocked_out[0].lap) != 1 or int(race.knocked_out[1].lap) != 2:
		errors.append("knockout: want one car out after laps 1 and 2, got %s" % [race.knocked_out.map(func(e): return "%s lap %d" % [e.car.name, e.lap])])
	var rows := race.results()
	if race.knocked_out.size() == 2:
		if rows[3].car != race.knocked_out[0].car or rows[2].car != race.knocked_out[1].car:
			errors.append("knockout: the first out should be last, the second third: %s" % [rows.map(func(r): return r.car.name)])
		for e in race.knocked_out:
			var c: RaceCar = e.car
			if not c.dnf or not c.recovered or not c.dnf_reason.begins_with("Knocked out"):
				errors.append("knockout: %s left without being cleared off (%s)" % [c.name, c.dnf_reason])
	if not rows[0].car.finished or not rows[1].car.finished or race.winner != rows[0].car:
		errors.append("knockout: the final two should both finish, the winner first")
	race.dispose()

	# Projected finish in knockout mode (skipping / early DNF)
	var st_proj := _settings_for("fiat", 3, 3, "medium")
	st_proj.knockout = true
	st_proj.mission = "knockout"
	var r_proj := Race.new(st_proj, null, 12)
	_run(r_proj, Race.PlayerInput.new(), 2.0)
	r_proj.approximate_finish()
	if r_proj.phase != "finished":
		errors.append("knockout projection: race not finished")
	if r_proj.knocked_out.size() != 2:
		errors.append("knockout projection: want 2 cars knocked out, got %d" % r_proj.knocked_out.size())
	var rows_proj := r_proj.results()
	if rows_proj.size() != 4 or not rows_proj[0].car.finished or not rows_proj[1].car.finished:
		errors.append("knockout projection: final two cars should finish")
	if not rows_proj[2].car.dnf or not rows_proj[3].car.dnf:
		errors.append("knockout projection: eliminated cars should be marked DNF")
	r_proj.dispose()

	# Projected mid-way: one car already knocked out for real (lap 1), the rest of the eliminations projected.
	var st_mid := _settings_for("fiat", 4, 4, "medium")
	st_mid.knockout = true
	st_mid.mission = "knockout"
	var r_mid := Race.new(st_mid, null, 13)
	r_mid.set_autopilot(true)
	var guard := 0
	while r_mid.knocked_out.is_empty() and r_mid.phase != "finished" and guard < int(900.0 / DT):
		r_mid.step(DT, Race.PlayerInput.new())
		guard += 1
	if r_mid.knocked_out.size() != 1 or r_mid.phase == "finished":
		errors.append("knockout mid-projection: setup wanted one car out and the race running, got %d out" % r_mid.knocked_out.size())
	else:
		var real_first: RaceCar = r_mid.knocked_out[0].car
		r_mid.approximate_finish()
		if r_mid.phase != "finished":
			errors.append("knockout mid-projection: race not finished")
		var ko: Array = r_mid.knocked_out
		# 5 cars (4 rivals + player): out after laps 1, 2 and 3 until two are left
		if ko.size() != 3:
			errors.append("knockout mid-projection: want 3 cars out, got %s" % [ko.map(func(e): return "%s lap %d" % [e.car.name, e.lap])])
		else:
			if ko[0].car != real_first:
				errors.append("knockout mid-projection: the real first knock-out was displaced")
			for i in ko.size():
				if int(ko[i].lap) != i + 1:
					errors.append("knockout mid-projection: knock-out %d on lap %d, want %d" % [i, int(ko[i].lap), i + 1])
				if int(r_mid.out_order.get(ko[i].car, 0)) != i + 1:
					errors.append("knockout mid-projection: out_order of knock-out %d is %s" % [i, r_mid.out_order.get(ko[i].car, 0)])
				var c: RaceCar = ko[i].car
				if not c.dnf or not c.dnf_reason.begins_with("Knocked out"):
					errors.append("knockout mid-projection: %s not marked knocked out" % c.name)
			var rr := r_mid.results()
			if rr.size() != 5 or not rr[0].car.finished or not rr[1].car.finished or r_mid.winner != rr[0].car:
				errors.append("knockout mid-projection: the final two should finish, winner first")
			elif rr[4].car != ko[0].car or rr[3].car != ko[1].car or rr[2].car != ko[2].car:
				errors.append("knockout mid-projection: classification should reverse the knock-out order: %s" % [rr.map(func(r): return r.car.name)])
	r_mid.dispose()

	# The player retires on lap 1 (the usual reason to project): they rank below nobody who was knocked out later,
	# and the other eliminations are still projected.
	var r_ret := Race.new(st_mid, null, 14)
	r_ret.set_autopilot(true)
	guard = 0
	while r_ret.player.lap < 1 and guard < int(900.0 / DT):
		r_ret.step(DT, Race.PlayerInput.new())
		guard += 1
	r_ret.player.dnf = true
	r_ret.player.dnf_reason = "Retired"
	r_ret.approximate_finish()
	if r_ret.phase != "finished" or r_ret.knocked_out.size() < 2:
		errors.append("knockout retirement projection: finished=%s, %d knocked out" % [r_ret.phase == "finished", r_ret.knocked_out.size()])
	var rr2 := r_ret.results()
	if rr2.size() != 5 or not rr2[0].car.finished or not rr2[1].car.finished or rr2[2].car.finished:
		errors.append("knockout retirement projection: want exactly two finishers: %s" % [rr2.map(func(r): return "%s %s" % [r.car.name, r.car.finished])])
	elif int(r_ret.out_order.get(r_ret.player, 0)) != int(r_ret.out_order.get(rr2[3].car, -1)) or int(r_ret.out_order.get(rr2[4].car, 99)) > int(r_ret.out_order.get(r_ret.player, 0)):
		errors.append("knockout retirement projection: the player (out #%s) should rank just above the cars that left before them: %s" % [r_ret.out_order.get(r_ret.player, 0), rr2.map(func(r): return "%s #%s" % [r.car.name, r_ret.out_order.get(r.car, 0)])])
	r_ret.dispose()

## The quarter mile: four cars two abreast, every car stops the clock at 402 m from its own spot, the stock
## Seicento in a plausible time (0-100 km/h takes it about 17-20 s, so 402 m is 19-24 s).
func _drag(errors: Array[String]) -> void:
	for box in ["auto", "manual"]:
		var st := _settings_for("s1_sprint", 1, 3)
		st.finish_distance = 402.0
		st.grid = "pole"
		st.gearbox = box
		st.mission = "drag"
		var race := Race.new(st, null, 4)
		var inp := Race.PlayerInput.new()
		var at_finish := -1.0
		var n := 0
		while race.phase != "finished" and n < 120 * 90:
			var p := race.player
			inp.throttle = 1.0
			var aim := race.track.pos(p.s + 25.0, 0.0)
			inp.steer = clampf(wrapf(atan2(aim[1] - p.y, aim[0] - p.x) - p.heading, -PI, PI) * 2.2, -1.0, 1.0)
			inp.shift_up = box == "manual" and race.phase == "racing" and p.rpm > race.spec.limiter - 200.0
			var was := p.finished
			race.step(DT, inp)
			if p.finished and not was:
				at_finish = race.run_distance(p)
			n += 1
		var tag := "drag %s" % box
		if race.phase != "finished" or race.cars.any(func(c: RaceCar) -> bool: return not c.finished):
			errors.append("%s: not every car finished" % tag)
		if absf(at_finish - 402.0) > 3.0:
			errors.append("%s: the player finished %.1f m from the start, not 402" % [tag, at_finish])
		var rows := race.results()
		for i in rows.size() - 1:
			if rows[i].total == null or rows[i + 1].total == null or float(rows[i].total) > float(rows[i + 1].total):
				errors.append("%s: classification not by time" % tag)
				break
		var me: Dictionary = rows.filter(func(r): return r.car.is_player)[0]
		if me.total == null or float(me.total) < 19.0 or float(me.total) > 24.0:
			errors.append("%s: player's 402 m took %s s (want 19-24)" % [tag, me.total])
		for r in rows:
			if r.total != null and (float(r.total) < 19.0 or float(r.total) > 26.0):
				errors.append("%s: %s took %.2f s" % [tag, r.car.name, float(r.total)])
		race.dispose()

## A sprint or an off-road race on a baked route: every car gets home (the AI copes with the loose roads).
func _field_race(errors: Array[String], kind: String, track: String, opp: int, extra: Dictionary) -> void:
	var st := _settings_for(track, 1, opp)
	st.mission = kind
	for k in extra:
		st.set(k, extra[k])
	var race := Race.new(st, null, 5)
	race.set_autopilot(true)
	_run(race, Race.PlayerInput.new(), 900.0)
	var home := race.cars.filter(func(c: RaceCar) -> bool: return c.finished and not c.running and not c.dnf).size()
	if race.phase != "finished" or home != race.cars.size():
		errors.append("%s on %s: %d of %d cars home (phase %s)" % [kind, track, home, race.cars.size(), race.phase])
	if kind == "offroad":
		var loose := 0.0
		for z in race.track.loose:
			loose += z.y - z.x
		if loose < race.track.L * 0.8:
			errors.append("offroad: %s is only %.0f%% loose" % [track, 100.0 * loose / race.track.L])
		var loose_sum := 0.0
		for v in race.track.PROF:
			loose_sum += v
		var paved := Race.new(_settings_for(track, 1, 0), null, 5) # without loose_spans the AI's profile is the tarmac one
		var paved_sum := 0.0
		for v in paved.track.PROF:
			paved_sum += v
		if loose_sum >= paved_sum * 0.97:
			errors.append("offroad: the AI's loose-road profile is not slower (%.0f vs %.0f)" % [loose_sum, paved_sum])
		paved.dispose()
	race.dispose()

## The drift mission's tiers against a scripted driver (road follower, handbrake flicks into the bends, throttle
## through): it reaches bronze, and gold stays out of its reach.
func _drift_driver(errors: Array[String]) -> void:
	var idx := Missions.index_of("drift_babudy")
	var m: Dictionary = Missions.get_def(idx)
	var st := _settings_for(String(m.track), 1, 0)
	st.mission = "drift"
	st.drift_score = true
	st.drift_tiers = PackedInt32Array(m.tiers)
	st.finish_distance = float(m.finish_distance)
	st.assists = "abs"
	var race := Race.new(st, null, 3)
	var inp := Race.PlayerInput.new()
	var tr := race.track
	var hb_t := 0.0
	var n := 0
	while race.phase != "finished" and n < 120 * 400:
		var p := race.player
		var v := absf(p.speed)
		var k := 0.0
		for a in [10.0, 20.0, 30.0]:
			k = maxf(k, absf(tr.sample(tr.KC, p.s + a)))
		var target := tr.sample(tr.PROF, p.s + 25.0) * 0.95
		inp.throttle = 1.0 if v < target else 0.2
		inp.brake = 0.6 if v > target + 4.0 else 0.0
		var aim := tr.pos(p.s + 6.0 + v * 0.45, 0.0)
		inp.steer = clampf(wrapf(atan2(aim[1] - p.y, aim[0] - p.x) - p.heading, -PI, PI) * 2.2, -1.0, 1.0)
		if hb_t <= 0.0 and k > 0.015 and v > 11.0:
			hb_t = 0.6
		inp.handbrake = 1.0 if hb_t > 0.0 else 0.0
		hb_t -= DT
		race.step(DT, inp)
		n += 1
	var tiers: Array = m.tiers
	var score := race.drift.total() if race.drift else 0
	var tier := DriftScore.tier(score, tiers)
	print("    drift calibration: scripted driver %d points (bronze %d, gold %d), best combo %d, lost %d, %.0f s" % [
		score, int(tiers[0]), int(tiers[2]), race.drift.best_combo, race.drift.lost, race.race_time])
	if race.phase != "finished" or not race.player.finished:
		errors.append("drift: the scripted run did not finish the %.0f m" % float(m.finish_distance))
	if score < int(tiers[0]) or tier < 1:
		errors.append("drift: the scripted driver scored %d, short of bronze %d" % [score, int(tiers[0])])
	if score >= int(tiers[2]):
		errors.append("drift: the scripted driver reached gold (%d): gold is trivial" % score)
	race.dispose()

## Every mission's beacon stands inside the play area, on a road, and apart from the stage beacons.
func _beacons(errors: Array[String]) -> void:
	if not OpenWorld.available():
		return
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		var pose := Missions.place(idx, map)
		var tag := "beacon %s" % Missions.MISSIONS[k].id
		if pose.size() != 3:
			errors.append("%s: no pose" % tag)
			continue
		var p := Vector2(pose[0], pose[1])
		if not map.in_play(p):
			errors.append("%s: %s outside the play area" % [tag, p])
		if map.road_at(p.x, p.y, -INF, 3.0).is_empty():
			errors.append("%s: %s is not on a road" % [tag, p])
		for k2 in range(k + 1, Missions.MISSIONS.size()):
			var q := Missions.place(Missions.BASE + k2, map)
			if q.size() == 3 and Vector2(q[0], q[1]).distance_to(p) < 14.0 and Missions.MISSIONS[k2].track != Missions.MISSIONS[k].track:
				errors.append("%s: on top of %s" % [tag, Missions.MISSIONS[k2].id])

## Each mission as raced on the map (MapMissions + LiveEvents): the player's grid spot, every rival's and every
## checkpoint stand on the map's roads (the roads were rebaked: this catches a start left in the verge); the field
## takes the mission's difficulty; a gravel rally stage slows the crews' reference as it slows the player.
func _map_starts(errors: Array[String]) -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("map did not load")
		return
	var live := LiveEvents.new(map, 7)
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		var ev := MapMissions.event(idx)
		if ev.is_empty():
			errors.append("mission %s has no map event" % Missions.MISSIONS[k].id)
			continue
		live.begin(ev, "stock")
		var g := live.grid_pose(ev)
		if map.road_at(g[0].x, g[0].y, -INF, 0.2).is_empty():
			errors.append("%s: the player's grid spot is off the road" % ev.id)
		var rv := live.rivals()
		if rv:
			if String(ev.difficulty) != String(Missions.as_stage(idx).difficulty):
				errors.append("%s: the field does not take the mission's difficulty" % ev.id)
			for j in rv.rivals.size():
				var ps: Array = rv.pose(float(rv.rivals[j].s), float(rv.rivals[j].lat))
				if map.road_at(ps[0].x, ps[0].y, -INF, 0.5).is_empty():
					errors.append("%s: rival %d's grid spot is off the road" % [ev.id, j])
				if (ps[0] as Vector2).distance_to(g[0]) < 2.0:
					errors.append("%s: rival %d starts on top of the player" % [ev.id, j])
		var off := 0
		var all_cps: Array = [ev.cps]
		if ev.kind == "rally":
			all_cps = ev.stages.map(func(st): return st.cps)
		for cps in all_cps:
			for c in cps:
				if map.nearest_road(c, 6.0).is_empty():
					off += 1
		if off > 0:
			errors.append("%s: %d checkpoints more than 6 m off the roads" % [ev.id, off])
		if ev.kind == "rally":
			var dry := MapMissions.rally_times(ev, "stock", 3)
			var wet := MapMissions.rally_times(ev, "stock", 3, (ev.stages as Array).map(func(st): return 0.7))
			if float(wet[0][0]) <= float(dry[0][0]):
				errors.append("rally crews are not slowed by a loose stage's grip")
		live.abandon()
