## Pace notes and the co-driver (CMR 2.0's calls) and the service area's damaged parts.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	_notes(errors)
	_calls(errors, "fiat") # two corners on a short lap: notes more than half a lap ahead
	_calls(errors, "monaco")
	_service(errors)
	_splits(errors)
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
