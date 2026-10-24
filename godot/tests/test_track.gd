## Compares Track (geometry, racing line, profile, lookups) and SimUtil.Rng against js/track.js
## (reference from tools/parity/track_ref.js).
extends RefCounted

var completed := false

const TOL := 1e-9
## TrackDef values the Godot game has retuned away from js/track.js; the parity check builds with the reference's.
const JS_VALUES := {"indy": {"banking": 9.2}}
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
		var def := Track.load_def(key)
		if key in JS_VALUES:
			def = def.duplicate()
			for f in JS_VALUES[key]:
				def.set(f, JS_VALUES[key][f])
		var tr := Track.new(def)
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
	# Verify Pillar 3 original city tracks
	for c_key in ["tokyo", "bielsko", "krakow", "oswiecim", "wilamowice", "brzeszcze", "pszczyna", "bor"]:
		var t0_city := Time.get_ticks_msec()
		var c_def := Track.load_def(c_key)
		if c_def == null:
			errors.append("%s: TrackDef is null" % c_key)
			continue
		var c_tr := Track.new(c_def)
		if c_tr == null or c_tr.n < 1000:
			errors.append("%s: failed to build track or n < 1000" % c_key)
			continue
		checked += 1
		print("    %s: built in %d ms (n = %d, L = %.1f m)" % [c_key, Time.get_ticks_msec() - t0_city, c_tr.n, c_tr.L])
		if c_key == "bor":
			# a real street stage (tools/build_street_tracks.py, tools/street_routes/bor.json): ul. Bór, Strażacka,
			# Borska and Lachowicka in Brzeszcze-Bór, from OpenStreetMap
			if not c_def.street_stage:
				errors.append("bor: must be a street stage (no circuit furniture)")
			if c_def.grandstands != false or c_def.stand_tiers != 0 or c_def.floodlight_spacing != 0.0:
				errors.append("bor: no grandstands or floodlights on a public road")
			if c_def.kerb_style != "none" or c_def.kerb_width != 0.0:
				errors.append("bor: kerb_style must be none and kerb_width 0.0")
			if absf(c_def.runoff - 1.8) > 0.01 or c_def.runoff_surface != "grass" or c_def.runoff_paved != 0.0:
				errors.append("bor: runoff must be 1.8 grass with 0.0 paved")
			if c_tr.L < 3000.0 or c_tr.L > 3600.0:
				errors.append("bor: the real loop is about 3.3 km, got %.0f m" % c_tr.L)
			var c_names := []
			for c in c_def.corners:
				c_names.append(c.name)
			for street in ["ul. Bór", "ul. Strażacka", "ul. Borska", "ul. Lachowicka"]:
				if street not in c_names:
					errors.append("bor: corner names should include %s" % street)
			var env_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/bor_env.json"))
			if typeof(env_data) != TYPE_DICTIONARY:
				errors.append("bor: bor_env.json failed to load")
			else:
				var blockages: Array = env_data.get("road_blockages", [])
				if blockages.size() < 9:
					errors.append("bor: expected a barrier across each side road, got %d" % blockages.size())
				for b in blockages:
					var near := c_tr.project(float(b[0]), float(b[1]))
					if near[2] < c_tr.half + c_def.runoff or near[2] > c_tr.half + c_def.runoff + 12.0:
						errors.append("bor: road blockage %s should stand just off the stage (%.1f m)" % [b, near[2]])
						break
				if not (env_data.get("stands", []) as Array).is_empty() or not (env_data.get("landmarks", []) as Array).is_empty():
					errors.append("bor: no grandstands or landmark models in Bór")
				var b_list: Array = env_data.get("buildings", [])
				if b_list.size() < 100:
					errors.append("bor: expected the real buildings of Bór from OpenStreetMap, got %d" % b_list.size())
				if (env_data.get("water", []) as Array).size() < 5:
					errors.append("bor: expected the fishponds")
			checked += 5
		# the other real street stages (tools/street_routes/<key>.json): length range, streets, side-road barriers
		var streets := {
			"bielsko": [4800.0, 5300.0, ["al. Armii Krajowej", "ul. Karbowa", "ul. Karpacka", "ul. Gościnna", "Rondo PTTK"], 40, 1000],
			"wilamowice": [7000.0, 7500.0, ["ul. Paderewskiego", "ul. Kęcka", "ul. Krakowska", "ul. Jana Pawła II", "ul. Latosińskiego", "ul. Jana III Sobieskiego"], 40, 1000],
			"pszczyna": [3500.0, 3900.0, ["ul. Wojska Polskiego (Zamek)", "ul. Żorska", "ul. Szymanowskiego", "ul. Katowicka", "Rynek", "Brama Wybrańców"], 30, 1000],
			"krakow": [3450.0, 3850.0, ["ul. Basztowa (Barbakan)", "ul. Dunajewskiego", "ul. Podwale", "ul. Straszewskiego", "ul. Podzamcze (Wawel)", "ul. św. Gertrudy", "ul. Westerplatte"], 30, 2000],
		}
		if streets.has(c_key):
			var exp: Array = streets[c_key]
			if not c_def.street_stage or c_def.grandstands or c_def.stand_tiers != 0 or c_def.floodlight_spacing != 0.0 \
					or c_def.kerb_style != "none" or c_def.kerb_width != 0.0:
				errors.append("%s: a street stage has no grandstands, floodlights or kerbs" % c_key)
			if c_tr.L < exp[0] or c_tr.L > exp[1]:
				errors.append("%s: the real loop is %.0f-%.0f m, got %.0f m" % [c_key, exp[0], exp[1], c_tr.L])
			var s_names := []
			for c in c_def.corners:
				s_names.append(c.name)
			for street in exp[2]:
				if street not in s_names:
					errors.append("%s: corner names should include %s" % [c_key, street])
			var s_env = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/%s_env.json" % c_key))
			if typeof(s_env) != TYPE_DICTIONARY:
				errors.append("%s: %s_env.json failed to load" % [c_key, c_key])
			else:
				var s_blocks: Array = s_env.get("road_blockages", [])
				if s_blocks.size() < exp[3]:
					errors.append("%s: expected a barrier across each side road, got %d" % [c_key, s_blocks.size()])
				for b in s_blocks:
					var near := c_tr.project(float(b[0]), float(b[1]))
					if near[2] < c_tr.half + c_def.runoff or near[2] > c_tr.half + c_def.runoff + 12.0:
						errors.append("%s: road blockage %s should stand just off the stage (%.1f m)" % [c_key, b, near[2]])
						break
				if not (s_env.get("stands", []) as Array).is_empty() or not (s_env.get("landmarks", []) as Array).is_empty():
					errors.append("%s: no grandstands or landmark models on a street stage" % c_key)
				if (s_env.get("buildings", []) as Array).size() < exp[4]:
					errors.append("%s: expected the real buildings from OpenStreetMap" % c_key)
			# the pit lane stays clear of every side-road barrier
			for b in (s_env.get("road_blockages", []) if typeof(s_env) == TYPE_DICTIONARY else []):
				var near := c_tr.project(float(b[0]), float(b[1]))
				var rel := wrapf(near[0], -c_tr.L / 2, c_tr.L / 2)
				if rel > c_def.pit_entry and rel < c_def.pit_exit and signf(near[1]) == signf(c_def.pit_offset):
					errors.append("%s: road blockage %s stands in the pit lane" % [c_key, b])
					break
			checked += 5

	if checked < 1000:
		errors.append("only %d values checked" % checked)
	print("    %d values checked" % checked)
	completed = true
	return errors
