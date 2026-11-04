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
		if c_key == "tokyo":
			# the Shuto C1 inner loop from OpenStreetMap (tools/street_routes/tokyo.json): viaducts, the Ginza trench and
			# the tunnels under the palace moats, plus the Hamarikyu Spiral, a helix the real road doesn't have
			if not c_def.street_stage or not c_def.viaduct:
				errors.append("tokyo: must be a street stage on viaducts")
			if c_tr.L < 13800.0 or c_tr.L > 14800.0:
				errors.append("tokyo: the C1 inner loop and the spiral are about 14.3 km, got %.0f m" % c_tr.L)
			if c_tr.tunnels.size() < 3:
				errors.append("tokyo: the Kitanomaru, palace and Ginza tunnels are missing (%d spans)" % c_tr.tunnels.size())
			var t_names := []
			for c in c_def.corners:
				t_names.append(c.name)
			for jct in ["Edobashi JCT", "Takebashi JCT", "Miyakezaka JCT", "Tanimachi JCT", "Hamazakibashi JCT", "Hamarikyu Spiral"]:
				if jct not in t_names:
					errors.append("tokyo: corner names should include %s" % jct)
			# the spiral: stretches of the lap stacked over one another, every one clear of the deck below, and a car
			# followed round it by its hint stays on its own ring
			var spiral_s := -1.0
			for c in c_def.corners:
				if c.name == "Hamarikyu Spiral":
					spiral_s = c.distance
			var stacked := 0
			var tight := INF
			var first := int((spiral_s - 150.0) / c_tr.step)
			var last := int((spiral_s + 800.0) / c_tr.step)
			for i in range(first, last):
				for j in range(i + 75, last):
					if Vector2(c_tr.X[i] - c_tr.X[j], c_tr.Y[i] - c_tr.Y[j]).length() < c_tr.width:
						stacked += 1
						tight = minf(tight, absf(c_tr.H[i] - c_tr.H[j]))
			if stacked < 100:
				errors.append("tokyo: no spiral (only %d stacked samples)" % stacked)
			if tight < 6.5:
				errors.append("tokyo: stacked stretches only %.1f m apart" % tight)
			var walk := spiral_s
			while walk < spiral_s + 650.0:
				var p := c_tr.pos(walk, 1.5)
				var got := c_tr.project(p[0], p[1], walk - 1.0)
				if absf(c_tr.rel(got[0] - walk)) > 3.0:
					errors.append("tokyo: projection jumped rings at %.0f m (to %.0f m)" % [walk, got[0]])
					break
				walk += 1.0
		if c_key == "oswiecim":
			# a real street stage (tools/street_routes/oswiecim.json): the old town and both Soła bridges, from OSM
			if not c_def.street_stage or c_def.grandstands or c_def.kerb_style != "none":
				errors.append("oswiecim: must be a street stage without grandstands or kerbs")
			if c_tr.L < 2900.0 or c_tr.L > 3400.0:
				errors.append("oswiecim: the real loop is about 3.1 km, got %.0f m" % c_tr.L)
			var o_names := []
			for c in c_def.corners:
				o_names.append(c.name)
				for banned in ["auschwitz", "birkenau", "obóz", "oboz", "muzeum", "memorial"]:
					if banned in c.name.to_lower():
						errors.append("oswiecim: no corner may be named after the memorial (%s)" % c.name)
			for street in ["ul. Legionów", "Most Piastowski (Soła)", "Rynek Główny", "ul. Jagiełły", "Most Jagielloński (Soła)"]:
				if street not in o_names:
					errors.append("oswiecim: corner names should include %s" % street)
			if c_def.cobbles.size() != 1 or c_def.cobbles[0].x < 850.0 or c_def.cobbles[0].y > 1200.0:
				errors.append("oswiecim: the setts of Plebańska and the Rynek should be the one cobbled stretch")
			# keep clear of the Auschwitz I memorial: its fenced grounds (OSM way 29572443) in the track's frame
			var fence := Rect2(Vector2(-1036.8, 829.1), Vector2(350.4, 364.7))
			var closest := 1e9
			for i in c_tr.n:
				var p := Vector2(c_tr.X[i], c_tr.Y[i])
				closest = minf(closest, p.distance_to(p.clamp(fence.position, fence.end)))
			if closest < 650.0:
				errors.append("oswiecim: the loop comes %.0f m from the memorial grounds (keep 650 m)" % closest)
			var o_env = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/oswiecim_env.json"))
			if typeof(o_env) != TYPE_DICTIONARY:
				errors.append("oswiecim: oswiecim_env.json failed to load")
			else:
				if not (o_env.get("bridges", []) as Array).is_empty():
					errors.append("oswiecim: the loop's own Soła bridges must not be drawn as bridges over it")
				if (o_env.get("road_blockages", []) as Array).size() < 20:
					errors.append("oswiecim: expected a barrier across each side road")
				if (o_env.get("buildings", []) as Array).size() < 1000:
					errors.append("oswiecim: expected the real buildings of the town")
				for b in o_env.get("buildings", []):
					if fence.has_point(Vector2(b[3], b[4])):
						errors.append("oswiecim: no memorial buildings in the scenery")
						break
			checked += 4
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
			"pszczyna": [3500.0, 3900.0, ["ul. Wojska Polskiego (Zamek)", "ul. Żorska (Zagroda Żubrów)", "Brama Parkowa", "Nawrót pod Zamkiem", "Mosty na Stawach", "ul. Chopina (Park Zamkowy)", "ul. Katowicka", "Rynek", "Brama Wybrańców"], 30, 1000],
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
				# landmark models only for real buildings drawn on their own OSM footprint (build_surroundings.py LANDMARKS)
				var lm_ok := true
				for lm in s_env.get("landmarks", []):
					lm_ok = lm_ok and (String(lm[0]) in ["Barbakan", "FloriaGate", "PszczynaCastle", "WilamowiceChurch"]
						or String(lm[0]) in SURROUNDINGS_GD.LANDMARK_PROPS) # (or a route's extra_landmarks: Pszczyna's wisents)
				if not (s_env.get("stands", []) as Array).is_empty() or not lm_ok:
					errors.append("%s: no grandstands, and no landmark models but real buildings, on a street stage" % c_key)
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
		if c_key == "pszczyna":
			_check_pszczyna_park(c_tr, c_def, errors)
			checked += 5

	if checked < 1000:
		errors.append("only %d values checked" % checked)
	print("    %d values checked" % checked)
	completed = true
	return errors

const SURROUNDINGS_GD := preload("res://scripts/ui/surroundings.gd")

## Park Zamkowy (OSM way 172576408, leisure=park) simplified to 6 m, in Pszczyna's track metres (x east, y south).
const PSZCZYNA_PARK := [108, 339, 114, 321, 108, 298, 210, 254, 197, 227, 261, 200, 263, 177, 296, 180, 359, 225, 416, 253,
	421, 129, 551, -239, 470, -240, 409, -207, 359, -223, 335, -257, 243, -189, 147, -196, 73, -146, 45, -150, -36, -191,
	-97, -246, -118, -225, -158, -251, -290, -130, -276, -1, -231, 23, -245, 66, -341, 158, -383, 178, -285, 410, -232, 481,
	-205, 491, -116, 453, -44, 449, -43, 430, -10, 432, -4, 450, 98, 444, 123, 428, 133, 409, 102, 425, 90, 413, 67, 414,
	66, 399, 41, 400, 42, 417, 26, 418, 24, 372, 87, 371, 92, 349]
## The Pokazowa Zagroda Żubrów (OSM way 977929799), the wisent show enclosure west of ul. Żorska.
const PSZCZYNA_ZUBRY := [-657, 383, -603, 335, -591, 305, -575, 264, -565, 240, -538, 245, -465, 341, -404, 417, -403, 435,
	-429, 469, -473, 510, -496, 518, -552, 521, -620, 513, -649, 509, -663, 507, -673, 498, -681, 497, -689, 500, -741, 488,
	-752, 483, -756, 462, -730, 431, -706, 409, -682, 420, -663, 406, -671, 392]

static func _poly(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(0, flat.size(), 2):
		out.append(Vector2(flat[k], flat[k + 1]))
	return out

## Pszczyna's lap goes through the castle park (the user's ask): over a kilometre of it inside the Park Zamkowy
## outline, lined with the wooden rails; and the wisent herd stands in its real enclosure, off the road but in
## sight of it.
func _check_pszczyna_park(tr: Track, def: TrackDef, errors: Array) -> void:
	var park := _poly(PSZCZYNA_PARK)
	# the longest unbroken run inside the outline (ul. Chopina skims its northern edge, a sample or two)
	var first := 0.0
	var last := -1.0
	var run_from := -1.0
	for i in tr.n + 1:
		var in_park := i < tr.n and Geometry2D.is_point_in_polygon(Vector2(tr.X[i], tr.Y[i]), park)
		if in_park and run_from < 0.0:
			run_from = i * tr.step
		elif not in_park and run_from >= 0.0:
			if (i - 1) * tr.step - run_from > last - first:
				first = run_from
				last = (i - 1) * tr.step
			run_from = -1.0
	if last - first < 1100.0:
		errors.append("pszczyna: the lap should run over 1.1 km through Park Zamkowy in one stretch, got %.0f m" % maxf(0.0, last - first))
	var railed := false
	for z in def.wooden_rails:
		railed = railed or (z.x <= first + 10.0 and z.y >= last - 10.0)
	if not railed:
		errors.append("pszczyna: wooden rails should line the park alleys (%.0f-%.0f m)" % [first, last])
	var env = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/pszczyna_env.json"))
	var zubry := _poly(PSZCZYNA_ZUBRY)
	var herd := {}
	for lm in (env.get("landmarks", []) if typeof(env) == TYPE_DICTIONARY else []):
		var part := String(lm[0])
		if not part.begins_with("Wisent"):
			continue
		var at := Vector2(lm[1], lm[2])
		var near := tr.project(at.x, at.y)
		if not Geometry2D.is_point_in_polygon(at, zubry):
			errors.append("pszczyna: %s at %s should stand inside the wisent enclosure" % [part, at])
		elif near[2] < 60.0 or near[2] > 250.0:
			errors.append("pszczyna: %s should be off the road but in sight of it, %.0f m away" % [part, near[2]])
		herd[part] = true
	for part in ["WisentBull", "WisentCow", "WisentCowLying", "WisentCalf"]:
		if not herd.has(part):
			errors.append("pszczyna: the wisent herd should include a %s" % part)
	if not SURROUNDINGS_GD.landmark_meshes().has("WisentBull"):
		errors.append("pszczyna: wisents.glb should load with the landmarks")
