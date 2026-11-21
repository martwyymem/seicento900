## Pace notes and the co-driver (CMR 2.0's calls), the service area's damaged parts, the split times and the
## car set-up.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	_notes(errors)
	_calls(errors, "fiat") # two corners on a short lap: notes more than half a lap ahead
	_calls(errors, "monaco")
	_braking_cues(errors)
	_service(errors)
	_splits(errors)
	_car_setup(errors)
	completed = true
	return errors

func _notes(errors: Array[String]) -> void:
	for key in ["monza", "monaco", "spa", "nordschleife", "fiat"]:
		var tr: Track = Race.get_track(key)
		var pn := PaceNotes.new(tr)
		if pn.notes.size() < 2:
			errors.append("%s: only %d pace notes" % [key, pn.notes.size()])
			continue
		for i in pn.notes.size():
			var n: Dictionary = pn.notes[i]
			if i > 0 and n.s < pn.notes[i - 1].s:
				errors.append("%s: notes out of order at %d" % [key, i])
			if n.dir != 0 and not n.grade in ["flat", "fast", "easy", "medium", "tight", "square", "hairpin"]:
				errors.append("%s: unknown grade %s" % [key, n.grade])
			if n.link != "" and n.dist > 0:
				errors.append("%s: a note both runs into the next and calls a distance" % key)
			var said := PaceNotes.spoken(n)
			if said.is_empty() or PaceNotes.label(n).is_empty():
				errors.append("%s: note %d says nothing" % [key, i])
	# Monza's first chicane: a square right straight into a left after the long run from the line
	var monza := PaceNotes.new(Race.get_track("monza"))
	var first: Dictionary = monza.notes[0]
	if not (first.dir == 1 and first.link == "into" and first.caution and monza.notes[1].dir == -1):
		errors.append("Monza's Rettifilo should be 'caution, square right into' a left, got '%s' then '%s'" % [PaceNotes.spoken(first), PaceNotes.spoken(monza.notes[1])])
	# Monaco's Grand Hotel hairpin is the tightest corner in the game
	var tight := INF
	var tight_note := {}
	for n in PaceNotes.new(Race.get_track("monaco")).notes:
		if n.radius < tight:
			tight = n.radius
			tight_note = n
	if tight_note.get("grade", "") != "hairpin" or tight_note.get("dir", 0) != -1:
		errors.append("Monaco's tightest corner should be a left hairpin, got %s" % PaceNotes.spoken(tight_note))
	for g in [[200.0, 0.5, "flat"], [100.0, 0.5, "fast"], [60.0, 0.9, "easy"], [35.0, 1.2, "medium"], [15.0, 0.6, "tight"],
			[15.0, 1.5, "square"], [10.0, 3.0, "hairpin"]]:
		if PaceNotes.grade_for(g[0], g[1]) != g[2]:
			errors.append("radius %.0f m turning %.1f rad should be %s, got %s" % [g[0], g[1], g[2], PaceNotes.grade_for(g[0], g[1])])
	for d in [[90.0, 100], [140.0, 150], [260.0, 250], [380.0, 400]]:
		if PaceNotes.distance_call(d[0]) != d[1]:
			errors.append("a %.0f m straight should be called %d" % [d[0], d[1]])

## Drives the player's car along two laps by hand and checks the co-driver calls every note once a lap, in
## order, before the car gets there, and lets each go once through it.
func _calls(errors: Array[String], key: String) -> void:
	var st := RaceSettings.new()
	st.track = key
	st.opponents = 0
	st.race_control = false
	var race := Race.new(st, null, 3)
	race.phase = "racing"
	var p := race.player
	p.mode = "race"
	p.control = "rail"
	var cd := CoDriver.new(race)
	cd.voice_on = false
	var tr := race.track
	var m := cd.notes.notes.size()
	var called: Array = []
	var seen := {}
	p.v = 30.0
	var s0 := tr.wrap_s(p.s)
	var dist := 0.0
	while dist < 2.0 * tr.L:
		p.s = tr.wrap_s(s0 + dist)
		var before := cd.live.duplicate()
		cd.update(true, 1)
		for idx in cd.live:
			if not before.has(idx):
				called.append(idx)
				var ahead := tr.wrap_s(cd.notes.notes[idx].s - p.s)
				if ahead > CoDriver.LEAD_MAX + 125.0 and ahead < tr.L - 30.0:
					errors.append("%s: note %d called %.0f m early" % [key, idx, ahead])
		if cd.live.size() != _unique(cd.live):
			errors.append("%s: a note is up twice" % key)
			break
		seen[cd.live.size()] = true
		dist += 1.5
	if called.size() < 2 * m - 1 or called.size() > 2 * m + 1:
		errors.append("%s: %d calls over two laps for %d notes" % [key, called.size(), m])
	for i in range(1, called.size()):
		if called[i] != (called[i - 1] + 1) % m:
			errors.append("%s: call %d is note %d after note %d" % [key, i, called[i], called[i - 1]])
			break
	if seen.has(0) == false:
		errors.append("%s: the notes never clear on the straights" % key)
	race.dispose()

func _unique(a: Array) -> int:
	var d := {}
	for x in a:
		d[x] = true
	return d.size()

## Braking-distance lead time, distance countdown, BRAKE cue gating, and early hypercar callouts on Goliath.
func _braking_cues(errors: Array[String]) -> void:
	# Stock (~1 g) vs hypercar (~1.8-2.5 g at high speed) deceleration
	var d_stock := PaceNotes.brake_decel(35.0, 15.0, 1.0, 0.0, 1.0)
	var d_hyper := PaceNotes.brake_decel(90.0, 20.0, 1.25, 0.0016, 1.0)
	var d_wet := PaceNotes.brake_decel(35.0, 15.0, 1.0, 0.0, 0.65)
	if not (d_stock > 8.0 and d_stock < 11.0):
		errors.append("stock brake_decel should be ~1 g (9 m/s²), got %.2f" % d_stock)
	if d_hyper <= d_stock * 1.5:
		errors.append("hypercar high-speed brake_decel (%.2f) should exceed stock (%.2f)" % [d_hyper, d_stock])
	if d_wet >= d_stock:
		errors.append("wet brake_decel (%.2f) should be lower than dry (%.2f)" % [d_wet, d_stock])
	# Corner speed & braking distance
	if not is_inf(PaceNotes.corner_speed(INF)):
		errors.append("infinite radius should yield INF corner_speed")
	var vc_stock := PaceNotes.corner_speed(20.0, 1.0, 0.0, 1.0)
	var vc_hyper := PaceNotes.corner_speed(20.0, 1.25, 0.0016, 1.0)
	if not (vc_hyper > vc_stock and vc_stock > 10.0 and vc_stock < 20.0):
		errors.append("20 m corner speeds look wrong: stock=%.1f hyper=%.1f" % [vc_stock, vc_hyper])
	if PaceNotes.braking_distance(15.0, 20.0, 10.0) != 0.0:
		errors.append("already slower than corner should give 0 braking distance")
	var bd := PaceNotes.braking_distance(70.0, 20.0, 20.0) # (4900 - 400) / 40 = 112.5 m
	if absf(bd - 112.5) > 0.01:
		errors.append("braking_distance(70->20 @ 20) should be 112.5 m, got %.2f" % bd)
	# Lead distance: braking distance + 2.5 s reaction at 250 km/h (69.4 m/s) into a square corner
	var v250 := 250.0 / 3.6
	var lead250 := PaceNotes.lead_distance(v250, 18.0, 24.5) # ~2.5 g hypercar braking
	var want_lead := PaceNotes.braking_distance(v250, 18.0, 24.5) + v250 * PaceNotes.BRAKE_REACTION
	if absf(lead250 - want_lead) > 0.5 or lead250 <= CoDriver.LEAD_MAX:
		errors.append("250 km/h square-corner lead should be %.1f m (> LEAD_MAX), got %.1f m" % [want_lead, lead250])
	# No braking needed -> stays inside normal CoDriver.LEAD_MAX window
	var lead_flat := PaceNotes.lead_distance(v250, 90.0, 24.5)
	if lead_flat > CoDriver.LEAD_MAX + 0.01:
		errors.append("flat corner needing no braking should stay <= LEAD_MAX, got %.1f m" % lead_flat)
	# Countdown & HUD label formatting
	for c in [[260.0, 250], [180.0, 200], [60.0, 50], [20.0, 0]]:
		if PaceNotes.countdown_metres(c[0]) != c[1]:
			errors.append("countdown_metres(%.0f) should be %d, got %d" % [c[0], c[1], PaceNotes.countdown_metres(c[0])])
	var sample_note := {"dir": -1, "grade": "square", "mods": [], "link": "into", "dist": 0}
	if PaceNotes.hud_label(sample_note, 250) != "SQUARE LEFT 250":
		errors.append("hud_label with countdown should be 'SQUARE LEFT 250', got '%s'" % PaceNotes.hud_label(sample_note, 250))
	if PaceNotes.hud_label(sample_note, 0) != PaceNotes.label(sample_note):
		errors.append("hud_label at 0 m should fall back to PaceNotes.label")
	# BRAKE cue: off far before braking point, on at/past braking point when too fast, off when already slow enough
	var cue_early := PaceNotes.brake_cue(300.0, v250, 18.0, 24.5)
	var cue_now := PaceNotes.brake_cue(95.0, v250, 18.0, 24.5)
	var cue_slow := PaceNotes.brake_cue(40.0, 19.0, 18.0, 24.5)
	if cue_early.brake:
		errors.append("BRAKE cue should stay off 300 m before corner (brake_dist=%.0f)" % cue_early.brake_dist)
	if not cue_now.brake or cue_now.urgency <= 0.0:
		errors.append("BRAKE cue should light at 95 m when brake_dist=%.0f" % cue_now.brake_dist)
	if cue_slow.brake:
		errors.append("BRAKE cue must stay off when car is already slow enough for the corner")
	# End-to-end CoDriver on Goliath with Hypercar: a tight corner after a fast straight is called > LEAD_MAX ahead
	var st := RaceSettings.new()
	st.track = "goliath"
	st.car_class = "hypercar"
	st.opponents = 0
	st.race_control = false
	var cm := CarCatalog.model("hypercar")
	var ty := Tyres.new()
	var race := Race.new(st, null, 11, {"car_model": cm, "tyres": ty, "strategy": Strategy.new(cm, ty)})
	race.phase = "racing"
	var p := race.player
	p.mode = "race"
	p.control = "rail"
	p.v = 80.0 # ~288 km/h
	var cd := CoDriver.new(race)
	cd.voice_on = false
	var tr := race.track
	# Pick a square or hairpin corner with a long clear approach (>= 450 m after the previous note)
	var target_idx := -1
	for i in cd.notes.notes.size():
		var nt: Dictionary = cd.notes.notes[i]
		var prev: Dictionary = cd.notes.notes[(i - 1 + cd.notes.notes.size()) % cd.notes.notes.size()]
		var gap := tr.wrap_s(float(nt.s) - float(prev.e))
		if nt.grade in ["square", "hairpin"] and gap >= 450.0:
			target_idx = i
			break
	if target_idx < 0:
		errors.append("goliath: could not find a square/hairpin corner with >=450 m approach")
	else:
		var nt: Dictionary = cd.notes.notes[target_idx]
		p.s = tr.wrap_s(float(nt.s) - 260.0) # 260 m before corner (> old 190 m LEAD_MAX cap)
		cd.update(true, 1)
		if not cd.live.has(target_idx):
			errors.append("goliath hypercar at 288 km/h: note %d (%s) not yet called 260 m before corner" % [target_idx, PaceNotes.label(nt)])
	race.dispose()

func _service(errors: Array[String]) -> void:
	var share := 0.0
	for part in Service.PARTS:
		share += Service.PARTS[part][0]
	if absf(share - 1.0) > 1e-6:
		errors.append("part shares add up to %.3f, not 1" % share)
	for z in Service.ZONES:
		var w := 0.0
		for part in Service.ZONES[z]:
			w += Service.ZONES[z][part]
		if absf(w - 1.0) > 1e-6:
			errors.append("%s hit weights add up to %.3f" % [z, w])
	if Service.zone(0.9) != "front" or Service.zone(0.0) != "side" or Service.zone(-0.9) != "rear":
		errors.append("hit zones by direction are wrong")
	# a head-on hit breaks the front, not the exhaust; the parts make up the damage they came from
	var car := RaceCar.new()
	Service.spread(car, 0.2, 1.0)
	if car.parts.has("Exhaust") or not car.parts.has("Engine"):
		errors.append("a front hit should damage the engine and not the exhaust: %s" % car.parts)
	if absf(Service.total(car.parts) - 0.2) > 1e-6:
		errors.append("the parts should add up to the damage: %.3f" % Service.total(car.parts))
	Service.spread(car, 0.15, -1.0)
	if not car.parts.has("Exhaust") or not car.parts.has("Gearbox"):
		errors.append("a hit from behind should damage the exhaust and gearbox")
	# race control spreads its impacts the same way, and a pit repair clears them
	var st := RaceSettings.new()
	st.track = "fiat"
	st.opponents = 1
	st.mechanical_damage = true # (a circuit race is cosmetic-only unless it is opted in)
	var race := Race.new(st, null, 2)
	var p := race.player
	race.rc.hurt(p, 6.0, true, 0.95)
	if p.damage <= 0.0 or absf(Service.total(p.parts) - p.damage) > 1e-6:
		errors.append("race control damage %.3f should be what the parts add up to (%.3f)" % [p.damage, Service.total(p.parts)])
	race.rc.repaired(p)
	if not p.parts.is_empty():
		errors.append("a repair in the pits should clear the parts")
	# carried over between rounds: the damage and the pull's side come back, scaled by what is still bent
	car.dmg_pull = 0.03
	var snap := Service.snapshot(car)
	var rate := Service.pull_rate(car)
	var next := RaceCar.new()
	Service.fit(next, snap, rate)
	if absf(next.damage - Service.total(snap)) > 1e-6 or signf(next.dmg_pull) != 1.0:
		errors.append("a carried-over car should start with its damage and pull (%.3f, %.3f)" % [next.damage, next.dmg_pull])
	snap.erase("Suspension")
	snap.erase("Steering")
	Service.fit(next, snap, rate)
	if next.dmg_pull != 0.0:
		errors.append("with the suspension and steering fixed the car should run straight")
	if Service.minutes("Body", 0.0) != 0 or Service.minutes("Body", 0.5) != 15 or Service.minutes("Brakes", 0.02) != 1:
		errors.append("repair minutes are wrong")
	race.dispose()

## The HUD's split times: marked at each third of the lap, and put against the best lap's once there is one.
func _splits(errors: Array[String]) -> void:
	var st := RaceSettings.new()
	st.track = "fiat"
	st.opponents = 0
	st.race_control = false
	var race := Race.new(st, null, 4)
	var hud := RaceHud.new()
	hud.race = race # (only the split bookkeeping is under test, so the panels are never built)
	race.phase = "racing"
	var p := race.player
	p.mode = "race"
	p.control = "rail"
	p.v = 30.0
	var L := race.track.L
	p.s = 1.0
	p.lap = 0
	p.lap_start = 0.0
	race.clock = 0.0
	race.green_at = 0.0
	var dt := 1.0 / 60.0
	var laps := [] # [split 1, split 2] seen on each lap
	for lap in 3:
		var speed := 30.0 if lap != 1 else 33.0 # the second lap is the quickest
		var t0 := race.race_time
		while p.s + speed * dt < L:
			p.v = speed
			p.s += speed * dt
			race.clock += dt
			hud._update_splits()
		laps.append(hud._split_marks.duplicate())
		# over the line: a new lap
		var lap_time := race.race_time + (L - p.s) / speed - t0
		race.clock = t0 + lap_time
		p.s = 0.5
		p.lap += 1
		p.last_lap = lap_time
		p.best_lap = lap_time if p.best_lap == null else minf(p.best_lap, lap_time)
		p.lap_start = race.race_time
		hud._update_splits()
	if laps[0].size() != 2:
		errors.append("a lap should have two splits before the line, got %d" % laps[0].size())
	elif absf(laps[0][0] - L / 3.0 / 30.0) > 0.05:
		errors.append("the first split should be at %.2f s, got %.2f" % [L / 3.0 / 30.0, laps[0][0]])
	if hud._split_ref.size() != 3 or absf(hud._split_ref[2] - L / 33.0) > 0.05:
		errors.append("the reference should be the quickest lap's splits, got %s" % [hud._split_ref])
	elif hud._split_show.is_empty() or hud._split_show.delta == null or hud._split_show.delta <= 0.0:
		errors.append("a slower lap should show a split behind the best: %s" % [hud._split_show])
	hud.free()
	race.dispose()

## The car set-up: stock is the stock car exactly, only the player's car runs it, and the settings do what the
## page says they do.
func _car_setup(errors: Array[String]) -> void:
	var base: CarSpec = load("res://data/seicento.tres")
	if CarSetup.apply(base, {}) != base or CarSetup.apply(base, CarSetup.stock()) != base:
		errors.append("a stock set-up should drive the stock spec itself")
	var cleaned := CarSetup.clean({"springs": 7, "roll": -1.6, "turbo": 2})
	if cleaned.springs != CarSetup.NOTCHES or cleaned.roll != -1 or cleaned.has("turbo") or cleaned.size() != CarSetup.SETTINGS.size():
		errors.append("a saved set-up should come back clamped to whole notches: %s" % cleaned)
	var st := RaceSettings.new()
	st.track = "fiat"
	st.opponents = 1
	st.race_control = false
	var race := Race.new(st, null, 5)
	if race.player.model != race.car_model or race.player.physics != race.phys:
		errors.append("with no set-up the player should drive the race's stock car")
	race.dispose()
	st.car_setup = {"brakes": 2}
	race = Race.new(st, null, 5)
	if race.player.physics == race.phys or race.player.model.spec.brake_rear <= base.brake_rear or race.spec != base:
		errors.append("a set-up should give the player a car of its own and leave the race's stock car alone")
	race.dispose()
	# more rear brake stops shorter without ABS but turns the car; a low car digs into the grass
	var stock_stop := _stop({}, Physics.SURF_TRACK)
	var rear_stop := _stop({"brakes": 2}, Physics.SURF_TRACK)
	if not (rear_stop[0] < stock_stop[0] and rear_stop[1] > stock_stop[1] + 2.0):
		errors.append("rear brake bias should stop shorter and yaw more: %s against %s" % [rear_stop, stock_stop])
	var low := _stop({"height": -2}, Physics.SURF_GRASS, 0.0)
	var high := _stop({"height": 2}, Physics.SURF_GRASS, 0.0)
	if not (low[0] < high[0] - 5.0):
		errors.append("a low car should slow sooner rolling on grass: %.1f m against %.1f m" % [low[0], high[0]])
	# every car runs a set-up: the field is the roster's drivers on theirs, cars on the same one share a model
	st.car_setup = {}
	st.opponents = 15
	race = Race.new(st, null, 6)
	var by_setup := {}
	for car in race.cars:
		if car.is_player:
			continue
		var who := Drivers.find(car.name)
		if who.is_empty():
			errors.append("%s is not on the roster" % car.name)
			continue
		if car.setup != CarSetup.clean(who.setup) or car.number != who.number or car.agg != who.wear:
			errors.append("%s should run their own set-up, number and tyre wear" % car.name)
		var key := str(car.setup)
		if by_setup.has(key) and by_setup[key] != car.physics:
			errors.append("cars on the same set-up should share one physics model")
		by_setup[key] = car.physics
	var senna := Drivers.find("Ayrton Senna")
	var prost := Drivers.find("Alain Prost")
	for car in race.cars:
		if car.name == "Ayrton Senna" and not car.model.spec.roll_front < base.roll_front:
			errors.append("Senna's car should be stiffer at the rear (looser) than stock")
		if car.name == "Alain Prost" and not car.model.spec.roll_front > base.roll_front:
			errors.append("Prost's car should be stiffer at the front (safer) than stock")
	if senna.wet <= prost.wet:
		errors.append("Senna should be the better of the two in the rain")
	race.dispose()
	var base_phys := Physics.new(CarModel.new(base))
	var quick := Physics.new(CarModel.new(CarSetup.apply(base, {"steering": 2})))
	if not quick.max_steer(30.0, 1.0) > base_phys.max_steer(30.0, 1.0) * 1.1:
		errors.append("quick steering should give more lock at speed")

## Metres a car covers from 100 km/h (brake: pedal) on one surface, and the most it yaws on the way.
func _stop(setup: Dictionary, surface: int, brake := 1.0) -> Array:
	var cm := CarModel.new(CarSetup.apply(load("res://data/seicento.tres"), setup))
	var ph := Physics.new(cm)
	var car := RaceCar.new()
	car.vx = 100.0 / 3.6
	car.gear = 3
	var env := Physics.Env.new()
	env.mass = cm.mass_with_fuel(20.0)
	env.abs_on = false
	env.tc_on = false
	env.esc_on = false
	env.surface = func(_x: float, _y: float) -> int: return surface
	var c := Physics.Controls.new()
	c.brake = brake
	c.steer = 0.08 if brake > 0.0 else 0.0
	var yaw := 0.0
	var t := 0.0
	while car.vx * cos(car.heading) + car.vy * sin(car.heading) > (0.5 if brake > 0.0 else 15.0) and t < 30.0:
		ph.step(car, c, env, 1.0 / 120.0)
		t += 1.0 / 120.0
		yaw = maxf(yaw, absf(car.heading))
	return [car.x, rad_to_deg(yaw)]
