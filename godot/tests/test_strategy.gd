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
	print("    %d values checked" % checked)
	if checked < 1000:
		errors.append("only %d values checked" % checked)
	completed = true
	return errors
