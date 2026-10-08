## Runs whole races through Race with the same PRNG seed as js/race.js (reference from
## tools/parity/race_ref.js) and compares the grid, the car states along the way and the results.
## Bit-level differences in sin/pow between V8 and libm make long trajectories drift apart, so the trace is
## held tight only until TIGHT_UNTIL ticks and loosely after that; results are compared as statistics.
extends RefCounted

var completed := false

const TIGHT := 1e-6
const TIGHT_UNTIL := 120 * 20
const POS_LOOSE := 30.0 ## metres along the track, per car, over the rest of the trace
const BEST_LAP_REL := 0.02 ## each finisher's best lap
const TOTAL_REL := 0.03 ## each finisher's race time

var errors := []
var checked := 0

static func snake(k: String) -> String:
	var r := ""
	for ch in k:
		r += "_" + ch.to_lower() if ch != ch.to_lower() else ch
	return r

func settings_for(sc: Dictionary) -> RaceSettings:
	var st := RaceSettings.new()
	st.auto_strategist = true # the reference always boxes the player automatically
	st.dynamic_running = false
	st.draft = false
	for k in sc.settings:
		var v = sc.settings[k]
		var key := snake(k)
		if typeof(st.get(key)) == TYPE_INT:
			v = int(v)
		st.set(key, v)
	st.starting_tyre = sc.player_tyre
	# Godot-only player aids the JS reference doesn't have
	st.brake_assist = false
	st.auto_rejoin = false
	st.race_control = false
	st.real_drivers = false # the reference's field, on the stock car
	st.player_name = "You"
	return st

func snap(c: RaceCar) -> Dictionary:
	return {"s": c.s, "lap": c.lap, "d": c.d, "v": c.v, "x": c.x, "y": c.y, "heading": c.heading,
		"fuel": c.fuel, "wear": c.tyre.wear, "c": c.tyre.c, "gear": c.gear, "mode": c.mode, "control": c.control}

func player_input(t: float) -> Race.PlayerInput:
	var p := Race.PlayerInput.new()
	p.throttle = 0.7 + 0.3 * sin(t * 0.3)
	p.brake = 0.6 if fmod(t, 17.0) < 1.0 else 0.0
	p.steer = 0.5 * sin(t * 0.8)
	return p

func run_scenario(sc: Dictionary) -> void:
	var name: String = sc.name
	var models := {"car_model": preload("res://tests/test_physics.gd").js_car_model()}
	var race := Race.new(settings_for(sc), null, int(sc.seed), models)
	race.bot_uturn = false # the reference puts a spun bot back on the line
	race.bot_smooth_line = false
	var grid := []
	for c in race.cars:
		grid.append(c.name)
	checked += 1
	if grid != sc.grid:
		errors.append("%s: grid %s, want %s" % [name, grid, sc.grid])
		race.dispose()
		return
	if sc.autopilot:
		race.set_autopilot(true)
	var idle := Race.PlayerInput.new()
	var dt := 1.0 / 120.0
	var every := int(sc.trace_every)
	var trace_ticks := int(sc.trace_ticks)
	var ticks := 0
	var ti := 0
	var worst := 0.0
	var worst_at := ""
	var first_off := -1
	var t0 := Time.get_ticks_msec()
	while race.phase != "finished" and ticks < int(sc.ticks) + 120 * 60:
		race.step(dt, idle if sc.autopilot else player_input(ticks * dt))
		ticks += 1
		if ticks > trace_ticks or ticks % every != 0 or ti >= sc.trace.size():
			continue
		var want: Dictionary = sc.trace[ti]
		ti += 1
		for i in race.cars.size():
			var g := snap(race.cars[i])
			var w: Dictionary = want.cars[i]
			for k in w:
				checked += 1
				if w[k] is String:
					if ticks <= TIGHT_UNTIL and g[k] != w[k] and errors.size() < 20:
						errors.append("%s tick %d %s.%s: %s, want %s" % [name, ticks, race.cars[i].name, k, g[k], w[k]])
					continue
				var diff := absf(float(g[k]) - float(w[k]))
				if diff > TIGHT * maxf(1.0, absf(float(w[k]))) and first_off < 0:
					first_off = ticks
				if ticks <= TIGHT_UNTIL and diff > TIGHT * maxf(1.0, absf(float(w[k]))):
					if errors.size() < 20:
						errors.append("%s tick %d %s.%s: %s, want %s" % [name, ticks, race.cars[i].name, k, g[k], w[k]])
				if k == "s":
					var ds := absf(float(g.lap - w.lap) * race.track.L + float(g.s) - float(w.s))
					if ds > worst:
						worst = ds
						worst_at = "tick %d %s" % [ticks, race.cars[i].name]
	print("    %s: %d ticks (js %d) in %d ms, first drift > %s at tick %d, worst %.2f m (%s)" % [
		name, ticks, int(sc.ticks), Time.get_ticks_msec() - t0, str(TIGHT), first_off, worst, worst_at])
	if worst > POS_LOOSE:
		errors.append("%s: cars drifted %.1f m from the reference (%s)" % [name, worst, worst_at])
	if race.phase != sc.phase:
		errors.append("%s: phase %s, want %s" % [name, race.phase, sc.phase])
	var got := {}
	for r in race.results():
		got[r.car.name] = r
	for w in sc.results:
		var g = got.get(w.name)
		checked += 1
		if g == null:
			errors.append("%s: %s missing from the results" % [name, w.name])
			continue
		if g.laps != int(w.laps) or g.car.stops != int(w.stops):
			errors.append("%s %s: %d laps %d stops, want %d laps %d stops" % [name, w.name, g.laps, g.car.stops, w.laps, w.stops])
		if w.best != null and absf(g.car.best_lap - w.best) > BEST_LAP_REL * w.best:
			errors.append("%s %s: best lap %.3f, want %.3f" % [name, w.name, g.car.best_lap, w.best])
		if sc.phase == "finished" and absf(g.total - w.total) > TOTAL_REL * w.total:
			errors.append("%s %s: total %.3f, want %.3f" % [name, w.name, g.total, w.total])
	race.dispose()

func run() -> Array:
	Brain.use_disk = false
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref/race.json"))
	for sc in ref.scenarios:
		run_scenario(sc)
	print("    %d values checked" % checked)
	completed = true
	return errors
