## Compares Strategy (calibration, lap/stint model, planner) against js/strategy.js
## (reference from tools/parity/strategy_ref.js).
extends RefCounted

var completed := false

const TOL := 1e-9

var errors := []
var checked := 0

func near(what: String, got, want) -> void:
	checked += 1
	if want == null and (got is float and is_inf(got)):
		return # JSON writes Infinity as null
	if want is String or want is bool or want == null:
		if got != want:
			errors.append("%s: got %s, want %s" % [what, got, want])
	elif want is Array:
		if got.size() != want.size():
			errors.append("%s: size %d, want %d" % [what, got.size(), want.size()])
			return
		for i in want.size():
			near("%s[%d]" % [what, i], got[i], want[i])
	elif want is Dictionary:
		for k in want:
			near("%s.%s" % [what, k], got.get(k), want[k])
	elif absf(float(got) - float(want)) > TOL * maxf(1.0, absf(float(want))):
		errors.append("%s: got %s, want %s" % [what, got, want])

## JSON options (numbers as floats) -> planner options with ints where the planner expects them.
func opts_for(track: Track, o: Dictionary) -> Dictionary:
	var r := o.duplicate(true)
	r.track = track
	r.laps = int(r.laps)
	if r.has("max_stops"):
		r.max_stops = int(r.max_stops)
	if r.has("current"):
		r.current.mask = int(r.current.mask)
		r.current.stops_done = int(r.current.stops_done)
	return r

## Order-independent key of a plan's stints.
static func stint_set(p: Dictionary) -> String:
	var parts := []
	for st in p.stints:
		parts.append("%s%d/%.9f/%s" % [st.c, st.laps, st.fuel, st.get("cont", false)])
	parts.sort()
	return "%d:%s" % [p.stops, ",".join(parts)]

func run() -> Array:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref/strategy.json"))
	var strat := Strategy.new(CarModel.new(), Tyres.new())
	for e in ref.service:
		near("service_time%s" % [e.args], Strategy.service_time(e.args[0], e.args[1], e.args[2], e.args[3]), e.v)
	for key in ref.tracks:
		var want: Dictionary = ref.tracks[key]
		var tr := Track.new(Track.load_def(key))
		var t0 := Time.get_ticks_msec()
		var cal := strat.calibrate(tr)
		print("    %s: calibrated in %d ms" % [key, Time.get_ticks_msec() - t0])
		near("%s.cal" % key, cal, want.cal)
		for e in want.lap_time:
			near("%s.lap_time%s" % [key, e.args], Strategy.lap_time(cal, e.args[0], e.args[1]), e.v)
		for pc in want.plans:
			t0 = Time.get_ticks_msec()
			var plans := strat.plan(opts_for(tr, pc.opts))
			var ms := Time.get_ticks_msec() - t0
			if ms > 500:
				print("    %s: plan(%d laps) took %d ms" % [key, pc.opts.laps, ms])
			if plans.size() != pc.plans.size():
				errors.append("%s plan(%s): %d plans, want %d" % [key, pc.opts, plans.size(), pc.plans.size()])
				continue
			# Plans whose times tie to the last bit (the same stints in another order) can swap places or
			# replace each other in the planner's buckets, since pow/log differ in the last bit between V8
			# and libm. So: the time sequence must match, and each plan must be a permutation of the stints
			# of a reference plan with the same time.
			var by_stints := {}
			for w in pc.plans:
				by_stints.get_or_add(stint_set(w), []).append(w)
			for i in plans.size():
				var g: Dictionary = plans[i]
				var what := "%s plan(%d laps)[%d] %s" % [key, pc.opts.laps, i, Strategy.label(g)]
				near(what + ".time", g.time, pc.plans[i].time)
				var w = null
				for cand in by_stints.get(stint_set(g), []):
					if absf(cand.time - g.time) <= TOL * cand.time:
						w = cand
				if w == null:
					errors.append("%s: no reference plan with these stints and time" % what)
					continue
				near(what + ".time(matched)", g.time, w.time)
				near(what + ".stops", g.stops, w.stops)
				near(what + ".horizon", g.horizon, w.horizon)
		for e in want.evals:
			var st := []
			for s in e.stints:
				st.append({"c": s.c, "laps": int(s.laps)})
			var got := strat.evaluate(opts_for(tr, e.opts), st)
			near("%s.evaluate.time" % key, got.time, e.v.time)
			near("%s.evaluate.stops" % key, got.stops, e.v.stops)
			near("%s.evaluate.stints" % key, got.stints, e.v.stints)
			near("%s.evaluate.errors" % key, got.errors, e.v.errors)
		for e in want.est:
			near("%s.estimate_laps%s" % [key, e.args], strat.estimate_laps(tr, e.args[0], e.args[1]), e.v)
	_fuel_mixes(strat)
	print("    %d values checked" % checked)
	if checked < 1000:
		errors.append("only %d values checked" % checked)
	completed = true
	return errors

func expect(what: String, ok: bool, detail := "") -> void:
	checked += 1
	if not ok:
		errors.append("%s %s" % [what, detail])

## Fuel mixes (not in the JS): what they cost and save, and the Indianapolis fuel race they make.
func _fuel_mixes(strat: Strategy) -> void:
	var indy := Track.new(Track.load_def("indy"))
	var cal := strat.calibrate(indy)
	var save: Dictionary = cal.mix.save
	expect("save is slower", save.time > 1.01 and save.time < 1.05, str(save))
	expect("save burns less", save.fuel < 0.9 and save.fuel > 0.8, str(save))
	var o := {"track": indy, "laps": 12, "wet": 0.0, "wear_mult": 1.0, "fuel_mult": 15.0,
		"rules": {"mandatory_stop": true, "two_compounds": false, "refuel": true}, "crew": "club", "parallel": false}
	var plans := strat.plan(o)
	var best: Dictionary = plans[0]
	var flat_out = null
	for p in plans:
		if p.stints.all(func(st): return st.mix == "normal"):
			flat_out = p
			break
	expect("Indy fuel race: one stop on the save mix beats flat out", best.stops == 1 and best.stints.all(func(st): return st.mix == "save"), Strategy.label(best))
	expect("Indy fuel race: flat out needs two stops", flat_out != null and flat_out.stops == 2, Strategy.label(flat_out) if flat_out else "none")
	expect("Indy fuel race: and it is close", flat_out != null and flat_out.time < best.time * 1.03, "%s vs %s" % [best.time, flat_out.time if flat_out else 0.0])
	expect("the label shows the mix", Strategy.label(best).contains("save"), Strategy.label(best))
	# a pro crew's quicker stops make flat out the closer call
	o.crew = "pro"
	var pro := strat.plan(o)
	var pro_gap := 0.0
	for p in pro:
		if p.stops == 2:
			pro_gap = p.time - pro[0].time
			break
	var club_gap: float = flat_out.time - best.time if flat_out else 0.0
	expect("a faster crew narrows the gap to flat out", pro_gap < club_gap, "%f vs %f" % [pro_gap, club_gap])
	# without refuelling the race shares one tank, so every stint runs the normal mix
	var no_refuel := strat.plan({"track": indy, "laps": 12, "wet": 0.0, "wear_mult": 1.0, "fuel_mult": 1.0,
		"rules": {"mandatory_stop": true, "two_compounds": false, "refuel": false}, "crew": "club", "parallel": false})
	expect("no refuelling plans only the normal mix", no_refuel.size() > 0 and no_refuel.all(func(p): return p.stints.all(func(st): return st.mix == "normal")))
	# a hand-built save stint is timed and fuelled on that mix
	var ev := strat.evaluate(o, [{"c": "M", "laps": 6, "mix": "save"}, {"c": "M", "laps": 6, "mix": "save"}])
	var ev_flat := strat.evaluate(o, [{"c": "M", "laps": 6}, {"c": "M", "laps": 6}])
	expect("six save laps fit the tank", ev.errors.is_empty(), str(ev.errors))
	expect("six flat-out laps don't", not ev_flat.errors.is_empty())
