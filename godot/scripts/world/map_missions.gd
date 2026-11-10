## The campaign missions (Missions) raced on the open-world map itself, Forza Horizon style: no track is loaded, the
## mission's route is taken from its baked track file (data/tracks/<key>.json is in the open world's own metres, the
## routes were planned on the same map) and LiveEvents runs it in free roam with StreetRivals as the field.
##   drag      the first finish_distance m of the S1 from the mission's `at`, four abreast
##   sprint    one lap of the S1 Sprint, 7 rivals
##   offroad   one lap of Kolonia Stawowa, 5 rivals
##   knockout  laps of Bór concatenated, the last car out each time the leader completes a lap
##   drift     the first finish_distance m of Babudy–Góra, solo, the mission's point tiers
##   rally     the event's special stages one after the other, each against the clock from a standing start, the
##             player driving the liaison to the next stage start between them; the rival crews' stage times
##             come from a reference run of each stage (pace_time) times their own pace
## event() gives the dictionary LiveEvents.begin takes (the live events' own keys plus "mission", "rivals",
## "grid", "knockout", "lap_length", "laps", "target", "stages"); outcome() turns the finished run into what
## Missions.record expects.
class_name MapMissions
extends RefCounted

const RALLY_PACE := {"easy": Vector2(1.10, 1.45), "medium": Vector2(1.06, 1.34), "hard": Vector2(1.02, 1.22)} ## rival crews against the reference stage time
const RACE_KINDS := ["drag", "sprint", "offroad", "knockout"]
## Tracks whose line is not on the open world's roads (the old Bór circuit was drawn from OSM forest paths the map
## doesn't have): a knockout there runs on the stand-in, a rally leaves that stage out.
const OFF_MAP := {"bor": "maly_bor"}

static var _tracks := {} ## key -> [pts PackedVector2Array (from the start line), step, closed]

## The route of a track from its start line: every point once, as the race drives it.
static func track_path(key: String) -> PackedVector2Array:
	if _tracks.has(key):
		return _tracks[key]
	var out := PackedVector2Array()
	var def := Track.load_def(key)
	var text := FileAccess.get_file_as_string("res://data/tracks/%s.json" % key)
	var raw = JSON.parse_string(text) if text != "" else null
	if def and raw is Dictionary:
		var pts: Array = raw.pts
		var n := pts.size() / 2
		var step := float(raw.step)
		var off := SimUtil.js_round(def.start_offset / step)
		for k in n:
			var i := posmod(k + off, n)
			out.append(Vector2(float(pts[2 * i]), float(pts[2 * i + 1])))
	_tracks[key] = out
	return out

## The stretch [from, to] m from the start line (to <= from wraps through the line, 0 the whole lap).
static func span_path(key: String, from: float, to: float) -> PackedVector2Array:
	var full := track_path(key)
	var out := PackedVector2Array()
	if full.size() < 2:
		return out
	var L := LiveEvents.path_length(full) + full[full.size() - 1].distance_to(full[0])
	var stop := to if to > from else to + L
	var s := 0.0
	var n := full.size()
	# walk round (twice at most) collecting the points inside the span
	for k in n * 2 + 1:
		var a := full[k % n]
		if s >= from and s <= stop:
			out.append(a)
		if s > stop:
			break
		s += a.distance_to(full[(k + 1) % n])
	return out

## A lap path repeated `laps` times (closed through the start line).
static func laps_path(key: String, laps: int) -> PackedVector2Array:
	var lap := track_path(key)
	var out := PackedVector2Array()
	for l in maxi(laps, 1):
		out.append_array(lap)
	if lap.size() > 0:
		out.append(lap[0])
	return out

static func lap_length(key: String) -> float:
	var lap := track_path(key)
	return LiveEvents.path_length(lap) + (lap[lap.size() - 1].distance_to(lap[0]) if lap.size() > 1 else 0.0)

## The mission as a LiveEvents event, or {} when its route is not on the map.
static func event(index: int) -> Dictionary:
	if not Missions.is_mission(index):
		return {}
	var m := Missions.as_stage(index)
	var def: Dictionary = Missions.get_def(index)
	var kind := String(m.kind)
	var path := PackedVector2Array()
	var stages := []
	var ev := {"id": "mission_%s" % m.id, "mission": index, "mkind": kind, "title": String(def.title),
		"color": Missions.COLOR, "rivals": 0, "grid": "", "knockout": false, "lap_length": 0.0, "laps": 1,
		"target": int(m.target_pos), "difficulty": String(m.difficulty), "expires": INF}
	match kind:
		"drag":
			var at := float(def.get("at", 0.0))
			path = span_path(String(m.track), at, at + float(m.finish_distance))
			ev.kind = "race"
			ev.rivals = int(m.opponents)
			ev.grid = "drag"
		"drift":
			path = span_path(String(m.track), 0.0, float(m.finish_distance))
			ev.kind = "drift_zone"
			ev.mission_tiers = m.tiers
		"knockout":
			# one lap cut into `laps` sectors: the last car is out at each sector line, the final one decides it
			var key := String(OFF_MAP.get(String(m.track), m.track))
			path = laps_path(key, 1)
			ev.kind = "race"
			ev.rivals = int(m.opponents)
			ev.knockout = true
			ev.laps = int(m.laps)
			ev.sectors = true
			ev.lap_length = lap_length(key) / maxf(int(m.laps), 1)
		"rally":
			var re := Rally.event(String(m.rally))
			for sd in re.get("stages", []):
				if OFF_MAP.has(String(sd.track)):
					continue
				var sp := Rally.span(sd)
				var sp_path := span_path(String(sd.track), sp.x, sp.y)
				if sp_path.size() < 2:
					return {}
				stages.append({"name": String(sd.name), "path": sp_path, "length": LiveEvents.path_length(sp_path),
					"cps": LiveEvents.checkpoints(sp_path, LiveEvents.CP_SPACING)})
			if stages.is_empty():
				return {}
			path = stages[0].path
			ev.kind = "rally"
			ev.rivals = int(m.opponents)
			ev.stages = stages
		_: # sprint, offroad: one lap
			path = laps_path(String(m.track), int(m.laps))
			ev.kind = "race"
			ev.rivals = int(m.opponents)
			ev.laps = int(m.laps)
	if path.size() < 2:
		return {}
	ev.path = path
	ev.length = LiveEvents.path_length(path)
	ev.cps = LiveEvents.checkpoints(path, LiveEvents.CP_SPACING) if kind != "drag" else PackedVector2Array([path[path.size() - 1]])
	ev.goal = (ev.cps as PackedVector2Array)[(ev.cps as PackedVector2Array).size() - 1]
	ev.pos = path[0]
	ev.heading = (path[mini(3, path.size() - 1)] - path[0]).angle()
	return ev

## The rally crews' stage times: [[t stage 0, t stage 1, ...] per rival].
static func rally_times(ev: Dictionary, car_key: String, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var band: Vector2 = RALLY_PACE.get(String(ev.get("difficulty", "medium")), RALLY_PACE.medium)
	var out := []
	var n := int(ev.rivals)
	for k in n:
		var f := lerpf(band.x, band.y, float(k) / maxf(n - 1, 1))
		var times := []
		for st in ev.stages:
			times.append(LiveEvents.pace_time(st.path, car_key) * f * rng.randf_range(0.985, 1.015))
		out.append(times)
	return out

## What Missions.record takes, from a finished (or failed) LiveEvents run's result.
static func outcome(res: Dictionary) -> Dictionary:
	var ev: Dictionary = res.get("ev", {})
	var kind := String(ev.get("mkind", ""))
	var target := int(ev.get("target", 3))
	if kind == "drift":
		var tier := int(res.get("tier", 0))
		var sc := int(res.get("score", 0))
		return {"kind": kind, "success": tier >= 1, "tier": tier, "score": sc, "pos": 4 - tier if tier >= 1 else 999,
			"time": null, "line": String(res.get("line", ""))}
	var pos := int(res.get("pos", 999))
	var ok := bool(res.get("finished", false)) and pos <= target
	if kind == "knockout" and bool(res.get("knocked", false)):
		ok = pos <= target
	return {"kind": kind, "success": ok, "pos": pos, "time": res.get("time"), "tier": 0, "score": 0,
		"line": String(res.get("line", ""))}
