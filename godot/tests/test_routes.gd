## Routes cut from the Brzeszcze open world (tools/plan_route.py, baked by tools/build_street_tracks.py): the loops
## (the S1 Sprint on both S1 carriageways, Brzeszcze Kopalnia round the mine) and the point-to-point rally stages
## baked as loops with a run-off and a return leg (Mały Bór, Kolonia Stawowa, Babudy–Góra, Rajsko–Wilczkowice,
## Lipowiec–Kobylec). Each is a closed, connected loop that never touches itself, whose stage lies inside the open
## world's playable area, has the length and surface its kind asks for and bars its side roads; the co-driver drives
## every rally stage to its finish; no two stages of a rally event share a stretch of road, also across tracks.
extends RefCounted

var completed := false
var errors: Array[String] = []

const GAME := preload("res://scripts/ui/game.gd")

## The routes and what their road must be: "paved" all tarmac; "gravel" >= 60 % loose (gravel and dirt) and >= 40 %
## gravel; "dirt" >= 50 % dirt.
const ROUTES := {"s1_sprint": "paved", "brzeszcze": "paved", "maly_bor": "gravel", "kolonia_stawowa": "gravel",
	"babudy_gora": "gravel", "rajsko_wilczkowice": "dirt", "lipowiec_kobylec": "gravel"}
## Street stages baked in their own frame: their offset into the open world's (bor.json's origin projected, 0.3 m).
const FRAME_OFFSET := {"bor": Vector2(565.45, -2096.63)}

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

## The loop's samples [Vector2] from data/tracks/<key>.json (the open world's frame: same origin and projection).
func _raw(key: String) -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/%s.json" % key))
	return raw if raw is Dictionary else {}

func _pts(raw: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p: Array = raw.pts
	for i in p.size() / 2:
		out.append(Vector2(p[2 * i], p[2 * i + 1]))
	return out

## Share of samples i in [i0, i1) whose road surface is in kinds (raw.surfaces: [[first sample, surface]]).
func _surface_share(raw: Dictionary, i0: int, i1: int, kinds: Array) -> float:
	var secs: Array = raw.get("surfaces", [])
	if secs.is_empty():
		return -1.0
	var hit := 0
	for i in range(i0, i1):
		var sf := ""
		for s in secs:
			if int(s[0]) <= i:
				sf = s[1]
		if sf in kinds:
			hit += 1
	return float(hit) / maxf(1.0, i1 - i0)

## A loop with a repeated junction comes back to within a road's width of itself far along the lap; a grade-separated
## crossing (the S1 Sprint under its own overbridge) is fine when the two levels are 5.5 m or more apart (RaceWorld.
## _crossings() draws the bridge from 4 m; its deck hangs 1.6 m under the upper road).
func _touches(pts: PackedVector2Array, elev: Array, step: float, width: float) -> String:
	var n := pts.size()
	var cell := 8.0
	var grid := {}
	for i in n:
		var k := Vector2i(floori(pts[i].x / cell), floori(pts[i].y / cell))
		if not grid.has(k):
			grid[k] = PackedInt32Array()
		grid[k].append(i)
	for i in n:
		var k := Vector2i(floori(pts[i].x / cell), floori(pts[i].y / cell))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for j in grid.get(k + Vector2i(dx, dy), PackedInt32Array()):
					var apart := absi(i - j)
					if mini(apart, n - apart) * step < 150.0 or pts[i].distance_to(pts[j]) > width:
						continue
					# (RaceWorld hangs a 1.6 m deck under the upper road: 5.5 m keeps ~3.9 m over the car and camera)
					if absf(float(elev[i]) - float(elev[j])) >= 5.5:
						continue
					return "samples %d and %d (%.1f m apart)" % [i, j, pts[i].distance_to(pts[j])]
	return ""

func run() -> Array:
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/brzeszcze.json"))
	var play := PackedVector2Array()
	for i in (world.play as Array).size() / 2:
		play.append(Vector2(world.play[2 * i], world.play[2 * i + 1]))
	check("the open world has a play polygon", play.size() >= 3)

	for key in ROUTES:
		var kind: String = ROUTES[key]
		var def := Track.load_def(key)
		check("%s has a street-stage TrackDef" % key, def != null and def.street_stage)
		if def == null:
			continue
		var raw := _raw(key)
		var pts := _pts(raw)
		var n := pts.size()
		var step: float = raw.step
		# connected: no gap between samples, and the loop closes
		var worst := 0.0
		for i in n:
			worst = maxf(worst, pts[i].distance_to(pts[(i + 1) % n]))
		check("%s is connected and closes" % key, worst <= 1.5 * step, "(largest gap %.2f m, step %.2f)" % [worst, step])
		var touch := _touches(pts, raw.elev, step, def.width * 0.5)
		check("%s never meets itself (no repeated junction)" % key, touch == "", touch)
		var env = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/%s_env.json" % key))
		check("%s bars its side roads" % key, env is Dictionary and not (env.get("road_blockages", []) as Array).is_empty())
		# no wild jump in the road's height (the overbridge lift eases in), and every bridge drawn over it
		# (trackside_furniture: a 7 m deck with abutments) crosses it: one running along it walls the road in
		var steep := 0.0
		for i in n:
			steep = maxf(steep, absf(float(raw.elev[(i + 1) % n]) - float(raw.elev[i])) / step)
		check("%s: no grade over 20%% (2026-10-31: Mały Bór 14.5%% onto a pond dyke, the S1 bridge ramp 11%%)" % key, steep < 0.2, "(%.1f%%)" % (steep * 100.0))
		if env is Dictionary:
			for b in env.get("bridges", []):
				var at := Vector2(b[1], b[2])
				var best := 0
				for i in n:
					if pts[i].distance_squared_to(at) < pts[best].distance_squared_to(at):
						best = i
				var t := (pts[(best + 1) % n] - pts[best - 1]).normalized()
				var sin_a := absf(t.cross(Vector2(b[3], b[4]).normalized()))
				check("%s: a bridge over the road crosses it" % key, sin_a > 0.5, "(at %.0f, %.0f: sin %.2f)" % [at.x, at.y, sin_a])
		var L := n * step
		var i0 := 0
		var i1 := n
		if def.point_to_point:
			var sp: Array = raw.get("stage", [])
			check("%s has its stage span baked" % key, sp.size() == 2 and float(sp[1]) > float(sp[0]))
			if sp.size() != 2:
				continue
			i0 = int(float(sp[0]) / step)
			i1 = int(float(sp[1]) / step)
			var len_ := float(sp[1]) - float(sp[0])
			check("%s: the stage is 2-12 km" % key, len_ > 2000.0 and len_ < 12000.0, "(%.0f m)" % len_)
			# the start line and the pit-lane fields sit in the run-off past the finish, clear of the stage
			# (the lane, ramps included, runs from pit_entry to pit_exit, m from the start line)
			check("%s: the pit lane lies in the run-off" % key, def.pit_exit < float(sp[0]) and L + def.pit_entry > float(sp[1]), "(stage %.0f-%.0f of %.0f, pits %.0f..%.0f)" % [sp[0], sp[1], L, def.pit_entry, def.pit_exit])
			check("%s: rally only, not in the race pickers" % key, not key in GAME.TRACK_KEYS)
		else:
			check("%s: the lap is 5-15 km" % key, L > 5000.0 and L < 15000.0, "(%.0f m)" % L)
			check("%s is offered in the race pickers" % key, key in GAME.TRACK_KEYS)
			check("%s has race defaults" % key, GAME.TRACK_DEFAULTS.has(key))
		match kind:
			"paved":
				var paved := _surface_share(raw, i0, i1, ["paved"])
				check("%s is all tarmac" % key, paved == 1.0, "(%.0f%%)" % (paved * 100.0))
			"gravel":
				var loose := _surface_share(raw, i0, i1, ["gravel", "dirt"])
				var gravel := _surface_share(raw, i0, i1, ["gravel"])
				check("%s: the stage is at least 60%% gravel and dirt" % key, loose >= 0.6, "(%.0f%%)" % (loose * 100.0))
				check("%s: the stage is at least 40%% gravel" % key, gravel >= 0.4, "(%.0f%%)" % (gravel * 100.0))
			"dirt":
				var dirt := _surface_share(raw, i0, i1, ["dirt"])
				check("%s: the stage is at least 50%% dirt" % key, dirt >= 0.5, "(%.0f%%)" % (dirt * 100.0))
		var outside := 0
		for i in range(i0, i1):
			if not Geometry2D.is_point_in_polygon(pts[i], play):
				outside += 1
		check("%s: every stage sample is inside the playable area" % key, outside == 0, "(%d outside)" % outside)

	# the sprint: a full stage of the Polish Tour; no race picker offers a point-to-point stage
	check("the S1 Sprint is in the Polish Tour", "s1_sprint" in GAME.SEASON_PRESETS[1].tracks)
	for k in GAME.TRACK_KEYS:
		var d := Track.load_def(k)
		check("%s in the race pickers is not point-to-point" % k, d != null and not d.point_to_point)

	# no two stages of an event share a stretch of road, also on different tracks of the same map (test_rally checks
	# spans on one track): stage samples within 4 m of another stage's, more than 30 m of them (a crossing is less)
	for e in Rally.EVENTS:
		var lines := []
		for sd in e.stages:
			lines.append(_stage_line(sd))
		for a in lines.size():
			for b in range(a + 1, lines.size()):
				if e.stages[a].track == e.stages[b].track or lines[a].is_empty() or lines[b].is_empty():
					continue
				var shared := _shared(lines[a], lines[b], 4.0)
				check("%s: %s and %s share no road" % [e.key, e.stages[a].name, e.stages[b].name], shared * 2.0 <= 30.0, "(%d samples within 4 m)" % shared)

	# every point-to-point stage in the rally: its span comes from the baked data, and the co-driver drives it to the
	# finish on its event's surface (dry, noon), where the stage ends: no cool-down round the return leg
	Brain.use_disk = false
	LapRecords.use_disk = false
	var done := {}
	for e in Rally.EVENTS:
		for sd in e.stages:
			if not sd.get("baked", false) or done.has(sd.track):
				continue
			done[sd.track] = true
			var sp := Rally.span(sd)
			var b: Array = _raw(sd.track).stage
			check("%s: the span is the baked one" % sd.name, is_equal_approx(sp.x, float(b[0])) and is_equal_approx(sp.y, float(b[1])))
			var st := RaceSettings.new()
			Rally.configure_stage(st, sd)
			check("%s: configure_stage takes the baked span" % sd.name, is_equal_approx(st.stage_from, sp.x) and is_equal_approx(st.stage_to, sp.y))
			var run: Dictionary = sd.duplicate()
			run.merge({"weather": "dry", "hour": 12.0}, true)
			var rs := RaceSettings.new()
			Rally.configure_stage(rs, run)
			var race := Race.new(rs, null, 9)
			race.set_autopilot(true)
			var idle := Race.PlayerInput.new()
			var ticks := 0
			while race.phase != "finished" and ticks < 120 * 600:
				race.step(1.0 / 120.0, idle)
				ticks += 1
			var p := race.player
			var len_ := sp.y - sp.x
			check("the co-driver finishes %s" % sd.name, race.stage.time != null and not p.dnf, "(phase %s, s %.0f)" % [race.phase, p.s])
			if race.stage.time != null:
				var kmh: float = len_ / race.stage.time * 3.6
				print("    %s co-driver, %s, dry: %.1f s (%.2f km, %.0f km/h)" % [sd.name, sd.surface, race.stage.time, len_ / 1000.0, kmh])
				check("%s: the co-driver averages 35-110 km/h" % sd.name, kmh > 35.0 and kmh < 110.0, "(%.0f km/h)" % kmh)
			check("%s: the race ends at the stage finish" % sd.name, race.phase == "finished" and p.lap == 0 and absf(p.s - sp.y) < 60.0,
				"(lap %d, s %.0f, finish %.0f)" % [p.lap, p.s, sp.y])
			race.dispose()
	check("every new rally stage is in an event", done.has("kolonia_stawowa") and done.has("babudy_gora") and done.has("rajsko_wilczkowice") and done.has("lipowiec_kobylec") and done.has("maly_bor"))
	completed = true
	return errors

## A stage's samples in the open world's frame ([] for a track on another map).
func _stage_line(sd: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var key: String = sd.track
	var raw := _raw(key)
	var local := ROUTES.has(key) or key == "goliath"
	if raw.is_empty() or not (local or FRAME_OFFSET.has(key)):
		return out
	var pts := _pts(raw)
	var n := pts.size()
	var step: float = raw.step
	var sp := Rally.span(sd)
	var i0 := int(sp.x / step)
	var count := int(Rally.stage_length(sd, n * step) / step)
	var off: Vector2 = FRAME_OFFSET.get(key, Vector2.ZERO)
	for k in count:
		out.append(pts[(i0 + k) % n] + off)
	return out

## How many samples of a lie within r of a sample of b.
func _shared(a: PackedVector2Array, b: PackedVector2Array, r: float) -> int:
	var grid := {}
	for q in b:
		var c := Vector2i(floori(q.x / 8.0), floori(q.y / 8.0))
		if not grid.has(c):
			grid[c] = PackedVector2Array()
		grid[c].append(q)
	var hit := 0
	for p in a:
		var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		var near := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for q in grid.get(c + Vector2i(dx, dy), PackedVector2Array()):
					if p.distance_to(q) < r:
						near = true
		if near:
			hit += 1
	return hit
