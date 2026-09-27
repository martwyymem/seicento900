## Compares Track (geometry, racing line, profile, lookups) and SimUtil.Rng against js/track.js
## (reference from tools/parity/track_ref.js).
extends RefCounted

var completed := false

const TOL := 1e-9
const ARRS := ["X", "Y", "H", "GRADE", "TX", "TY", "NX", "NY", "ANG", "KC", "KP", "RLD", "RX", "RY", "RDS", "RK", "CORNER", "PROF"]

var errors := []
var checked := 0

func near(what: String, got, want) -> void:
	checked += 1
	if want is String:
		if got != want:
			errors.append("%s: got %s, want %s" % [what, got, want])
		return
	if want is Array:
		for i in want.size():
			near("%s[%d]" % [what, i], got[i], want[i])
		checked -= 1
		return
	if absf(float(got) - float(want)) > TOL * maxf(1.0, absf(float(want))):
		errors.append("%s: got %s, want %s" % [what, got, want])

func run() -> Array:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref/track.json"))
	for seed_key in ["_rng", "_rng2"]:
		var rng := SimUtil.Rng.new(int(ref[seed_key].seed))
		for i in ref[seed_key].values.size():
			near("%s %d" % [seed_key, i], rng.next(), ref[seed_key].values[i])
	for key in ref:
		if key.begins_with("_"):
			continue
		var want: Dictionary = ref[key]
		var t0 := Time.get_ticks_msec()
		var tr := Track.new(Track.load_def(key))
		print("    %s: built in %d ms (n = %d)" % [key, Time.get_ticks_msec() - t0, tr.n])
		if tr.n != int(want.n):
			errors.append("%s: n = %d, want %d" % [key, tr.n, want.n])
			continue
		for f in ["step", "L", "h_min", "h_max", "rl_length"]:
			var jf: String = {"h_min": "hMin", "h_max": "hMax", "rl_length": "rlLength"}.get(f, f)
			near("%s.%s" % [key, f], tr.get(f), want[jf])
		near("%s.bounds" % key, tr.bounds, want.bounds)
		if tr.sectors.size() != want.sectors.size():
			errors.append("%s: %d sectors, want %d" % [key, tr.sectors.size(), want.sectors.size()])
		else:
			for i in tr.sectors.size():
				near("%s.sectors[%d]" % [key, i], [float(tr.sectors[i][0]), tr.sectors[i][1]], want.sectors[i])
		for a in ARRS:
			var arr: PackedFloat64Array = tr.get(a)
			var sum := 0.0
			for x in arr:
				sum += absf(x)
			near("%s.sum(%s)" % [key, a], sum, want.sums[a])
			for e in want.arrays[a]:
				# KP picks the larger |k| in a window; exact ties of opposite sign (tiny curvatures, where
				# clamp_d's limit is kilometres) flip on last-bit differences, so compare magnitudes
				if a == "KP":
					near("%s.|KP|[%d]" % [key, e[0]], absf(arr[int(e[0])]), absf(e[1]))
				else:
					near("%s.%s[%d]" % [key, a, e[0]], arr[int(e[0])], e[1])
		for lk in want.lookups:
			var args: Array = lk.args
			var got
			match lk.fn:
				"sample_prof": got = tr.sample(tr.PROF, args[0])
				"sample_rld": got = tr.sample(tr.RLD, args[0])
				"pos": got = tr.pos(args[0], args[1])
				"heading": got = tr.heading(args[0])
				"s_rate": got = tr.s_rate(args[0], args[1])
				"rel": got = tr.rel(args[0])
				"clamp_d": got = tr.clamp_d(args[0], args[1])
				"pit_blend": got = tr.pit_blend(args[0])
				"limits": got = tr.limits(args[0])
				"sector_name": got = tr.sector_name(args[0])
				"project_hint": got = tr.project(args[0], args[1], args[2])
				"project": got = tr.project(args[0], args[1])
			near("%s.%s%s" % [key, lk.fn, args], got, lk.v)
	if checked < 1000:
		errors.append("only %d values checked" % checked)
	print("    %d values checked" % checked)
	completed = true
	return errors
