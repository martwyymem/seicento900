## Live events: the open world's own Forza Horizon style events, generated on the real Brzeszcze roads round the
## player and raced right there in free roam (no track to load, traffic and the train stay on the map). A board of
## up to MAX_LIVE events stands within SPAWN_MIN..SPAWN_MAX of the car at any time; each lasts LIFE_H game hours
## and is replaced by a new one somewhere else when it expires, is cleared or the car leaves it far behind, so the
## map keeps throwing up something new to drive to.
##
## Kinds:
##   sprint       a point-to-point street sprint through checkpoints along a route on the road graph, against the clock
##   speed_zone   a fast, straight stretch of a main road: the average speed through it counts
##   drift_zone   a twisty stretch: drift points (DriftScore) earned between its start and its end
##   trailblazer  a straight-line dash to a far point: any road, field or garden, only the time counts
## Targets are bronze / silver / gold, worked out for the car being driven from a reference lap of the route
## (grip-limited corner speeds, the car's acceleration and braking: pace_time), so the Golf or the hypercar face
## harder clocks than the Seicento.
##
## The class is free of the scene (OpenWorld drives it): generate() and the run (begin / tick / abandon) only need a
## TownMap, so tests/test_live_events.gd runs it headless. Progress (counts and medals) is WorldProgress.live.
class_name LiveEvents
extends RefCounted

const KINDS := ["sprint", "speed_zone", "drift_zone", "trailblazer"]
const KIND_WEIGHTS := [0.36, 0.24, 0.22, 0.18]
const KIND_NAMES := {"sprint": "STREET SPRINT", "speed_zone": "SPEED ZONE", "drift_zone": "DRIFT ZONE", "trailblazer": "TRAILBLAZER"}
const COLORS := {"sprint": Color("#ff3d8b"), "speed_zone": Color("#ffd23f"), "drift_zone": Color("#7dff6a"),
	"trailblazer": Color("#4ad8ff")}
const TIER_NAMES := ["", "BRONZE", "SILVER", "GOLD"]
const TIER_COLORS := [Color("#ff5a4a"), Color("#d08a4a"), Color("#d8dde6"), Color("#ffcc33")]
const MAX_LIVE := 4
const SPAWN_MIN := 280.0 ## m from the car
const SPAWN_MAX := 1500.0
const DESPAWN := 2600.0 ## an event this far from the car is dropped (one nearer takes its place)
const SPACING := 320.0 ## m between two events' starts, and from any stage or mission beacon
const LIFE_H := Vector2(5.0, 9.0) ## game hours an event stays up (OpenWorld.DAY_RATE: 80 s an hour, so 7 to 12 minutes)
const REFILL := 20.0 ## s between attempts to put a new event on the board
const ANNOUNCE := 900.0 ## m: a new event nearer than this is announced
const COUNTDOWN := 3.0
const CHECK_RADIUS := 18.0 ## m round a checkpoint that counts as through it
const GOAL_RADIUS := 25.0 ## m round a trailblazer's goal
const CP_SPACING := 420.0 ## m between a sprint's checkpoints
const TIME_OUT := 1.8 ## a run fails once it takes this many times the bronze time (zones: the reference time)
const FANS_PER_KM := 900.0
const TIER_FANS := [0.0, 1.0, 1.6, 2.5]
## Medal times against the reference run (sprint, trailblazer: s; speed zone: average km/h, higher is better).
const TIME_TIERS := [1.34, 1.16, 1.04] ## bronze, silver, gold: the reference time times this
const SPEED_TIERS := [0.72, 0.85, 0.95] ## ... the reference average times this
const DRIFT_PER_KM := [230.0, 960.0, 2300.0] ## points per km of the zone (Missions' Babudy drift: 600/2500/6000 on 2.6 km)
## Reference driving per car (CarCatalog key): top speed m/s, standing acceleration m/s², grip m/s², braking m/s².
## Measured with tests/_car_probe.gd: Seicento 137 km/h, 0.96 g; Golf IV 171 km/h, 0.86 g; hypercar 346 km/h.
const PACE := {"stock": [38.0, 2.4, 8.4, 7.4], "golf4": [47.5, 3.3, 7.6, 7.2], "hypercar": [96.0, 9.0, 13.5, 12.0]}

var map: TownMap
var rng := RandomNumberGenerator.new()
var board: Array = [] ## the live events: dictionaries, see _make
var run: Dictionary = {} ## the event being raced: {ev, state ("countdown", "running"), t, cp, drift, car, tiers}
var clock_h := 0.0 ## game hours since the board was started (expiry runs on it)
var last_result: Dictionary = {}
var _serial := 0
var _refill_t := 0.0

func _init(town: TownMap, seed_value := 0) -> void:
	map = town
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())

# ------------------------------------------------------------------------------------------ the board

## Keeps the board full round the player: drops expired and far events, adds one new event every REFILL s (or all
## of them at once when `fill`). `avoid` are other beacons to stay clear of. Returns the events added.
func update(dt_real: float, dt_hours: float, player: Vector2, avoid: PackedVector2Array, fill := false) -> Array:
	clock_h += dt_hours
	var added := []
	for k in range(board.size() - 1, -1, -1):
		var ev: Dictionary = board[k]
		if is_running() and run.ev == ev:
			continue
		if clock_h >= float(ev.expires) or (ev.pos as Vector2).distance_to(player) > DESPAWN:
			board.remove_at(k)
	_refill_t -= dt_real
	if is_running() or (_refill_t > 0.0 and not fill):
		return added
	_refill_t = REFILL
	var want := MAX_LIVE - board.size() if fill else mini(1, MAX_LIVE - board.size())
	for i in want:
		var ev := generate(player, avoid)
		if not ev.is_empty():
			board.append(ev)
			added.append(ev)
	return added

## One new event somewhere round `player`, clear of the board and of `avoid`: {} after a few failed tries.
func generate(player: Vector2, avoid: PackedVector2Array, kind := "") -> Dictionary:
	for attempt in 10:
		var k := kind if kind != "" else _pick_kind()
		var start := _road_point(player, k)
		if start.is_empty() or not _clear(start.pos, avoid):
			continue
		var ev: Dictionary
		match k:
			"sprint":
				ev = _make_sprint(start)
			"speed_zone":
				ev = _make_zone(start, "speed_zone")
			"drift_zone":
				ev = _make_zone(start, "drift_zone")
			"trailblazer":
				ev = _make_trailblazer(start)
		if not ev.is_empty():
			return ev
	return {}

func _pick_kind() -> String:
	var r := rng.randf()
	for i in KINDS.size():
		r -= KIND_WEIGHTS[i]
		if r <= 0.0:
			return KINDS[i]
	return KINDS[0]

## A road point in the spawn ring round p, on a road good enough for the kind: {road, i, t, pos, dir, dist}.
func _road_point(p: Vector2, kind: String) -> Dictionary:
	var min_rank := 6 if kind == "speed_zone" else (3 if kind == "sprint" else 1)
	for attempt in 8:
		var a := rng.randf() * TAU
		var d := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var q := p + Vector2(cos(a), sin(a)) * d
		if not map.in_play(q):
			continue
		var hit := map.nearest_road(q, 120.0, min_rank)
		if hit.is_empty() or not map.in_play(hit.pos) or _on_deck(hit):
			continue
		return hit
	return {}

func _on_deck(hit: Dictionary) -> bool:
	var z: PackedFloat32Array = map.road_z[hit.road]
	return z.size() > int(hit.i) and z[int(hit.i)] > 0.5 # a beacon on a bridge deck would stand in the air or under it

func _clear(p: Vector2, avoid: PackedVector2Array) -> bool:
	for q in avoid:
		if q.distance_to(p) < SPACING:
			return false
	for ev in board:
		if (ev.pos as Vector2).distance_to(p) < SPACING:
			return false
	return true

func _make_sprint(start: Dictionary) -> Dictionary:
	var a := rng.randf() * TAU
	var goal := map.nearest_road((start.pos as Vector2) + Vector2(cos(a), sin(a)) * rng.randf_range(1500.0, 3200.0), 150.0, 3)
	if goal.is_empty() or not map.in_play(goal.pos):
		return {}
	var path := map.route(start.pos, goal.pos)
	var length := path_length(path)
	if length < 1400.0 or length > 5200.0 or length > 2.3 * (start.pos as Vector2).distance_to(goal.pos):
		return {}
	var cps := checkpoints(path, CP_SPACING)
	var title := "%s ▸ %s" % [_street(start), _street(goal)]
	return _make("sprint", path, cps, title)

## A zone: from the start along the road it stands on for 500..1100 m. Speed zones must be nearly straight, drift
## zones properly twisty.
func _make_zone(start: Dictionary, kind: String) -> Dictionary:
	var want := rng.randf_range(500.0, 1100.0)
	var dir: Vector2 = start.dir if rng.randf() < 0.5 else -(start.dir as Vector2)
	var end := map.nearest_road((start.pos as Vector2) + dir * want, 80.0, 6 if kind == "speed_zone" else 1)
	if end.is_empty() or not map.in_play(end.pos):
		return {}
	var path := map.route(start.pos, end.pos)
	var length := path_length(path)
	if length < 0.7 * want or length > 1.6 * want:
		return {}
	var straight := (start.pos as Vector2).distance_to(end.pos) / maxf(length, 1.0)
	var twist := turning(path) / (length / 1000.0)
	if kind == "speed_zone" and straight < 0.88:
		return {}
	if kind == "drift_zone" and twist < 2.2:
		return {}
	var cps := PackedVector2Array([path[path.size() - 1]])
	return _make(kind, path, cps, _street(start))

## A trailblazer: 1.1..2.8 km as the crow flies to a point on a road, any way there.
func _make_trailblazer(start: Dictionary) -> Dictionary:
	var a := rng.randf() * TAU
	var goal := map.nearest_road((start.pos as Vector2) + Vector2(cos(a), sin(a)) * rng.randf_range(1100.0, 2800.0), 150.0, 1)
	if goal.is_empty() or not map.in_play(goal.pos):
		return {}
	var path := map.route(start.pos, goal.pos) # the reference: by road (a shortcut is how gold is won)
	if path.size() < 2:
		return {}
	return _make("trailblazer", path, PackedVector2Array([goal.pos]), "to %s" % _street(goal))

func _make(kind: String, path: PackedVector2Array, cps: PackedVector2Array, title: String) -> Dictionary:
	_serial += 1
	var h := (path[mini(3, path.size() - 1)] - path[0]).angle() if path.size() > 1 else 0.0
	var cp_z := PackedFloat32Array()
	for p in cps:
		var hit := map.nearest_road(p, 30.0)
		if not hit.is_empty() and hit.has("height"):
			cp_z.append(float(hit.height))
		else:
			cp_z.append(map.ground(p.x, p.y))
	return {"id": "live_%d" % _serial, "kind": kind, "title": title, "pos": path[0], "heading": h, "path": path,
		"length": path_length(path), "cps": cps, "cp_z": cp_z, "goal": cps[cps.size() - 1],
		"expires": clock_h + rng.randf_range(LIFE_H.x, LIFE_H.y), "color": COLORS[kind]}

## The street a point is on, or for a nameless lane the nearest named street round it ("off Lipowa").
func _street(hit: Dictionary) -> String:
	var n := _name_of(int(hit.road))
	if n != "":
		return n
	for r in [60.0, 140.0, 260.0]:
		for k in 8:
			var a := k * TAU / 8.0
			var near := map.nearest_road((hit.pos as Vector2) + Vector2(cos(a), sin(a)) * r, r * 0.6)
			if not near.is_empty() and _name_of(int(near.road)) != "":
				return "off %s" % _name_of(int(near.road))
	return "the %s road" % ("dirt" if map.road_surface[int(hit.road)] == 2 else "back")

func _name_of(ri: int) -> String:
	return String(map.road_name[ri]) if ri < map.road_name.size() else ""

# ------------------------------------------------------------------------------------------ targets

## The medal targets [bronze, silver, gold] of an event for a car (CarCatalog key).
func tiers_for(ev: Dictionary, car_key: String) -> Array:
	if ev.has("mission_tiers"):
		return ev.mission_tiers
	var ref := pace_time(ev.path, car_key)
	match String(ev.kind):
		"speed_zone":
			var v := float(ev.length) / ref * 3.6
			return [v * SPEED_TIERS[0], v * SPEED_TIERS[1], v * SPEED_TIERS[2]]
		"drift_zone":
			var km := float(ev.length) / 1000.0
			return [DRIFT_PER_KM[0] * km, DRIFT_PER_KM[1] * km, DRIFT_PER_KM[2] * km]
	return [ref * TIME_TIERS[0], ref * TIME_TIERS[1], ref * TIME_TIERS[2]]

## Seconds a tidy, quick driver in this car takes along the path from a standing start: corners at the car's grip,
## full throttle between them (acceleration falling off towards the top speed), braking in time.
static func pace_time(path: PackedVector2Array, car_key: String) -> float:
	var pc: Array = PACE.get(car_key, PACE.stock)
	var vmax: float = pc[0]
	var acc: float = pc[1]
	var lat: float = pc[2]
	var brk: float = pc[3]
	var pts := resample(path, 5.0)
	var n := pts.size()
	if n < 3:
		return 1.0
	var cap := PackedFloat32Array()
	cap.resize(n)
	for i in n:
		var a := pts[maxi(i - 3, 0)]
		var b := pts[i]
		var c := pts[mini(i + 3, n - 1)]
		var turn := absf(wrapf((c - b).angle() - (b - a).angle(), -PI, PI))
		var span := maxf(a.distance_to(b) + b.distance_to(c), 1.0)
		var k := turn / span # 1/m
		cap[i] = minf(vmax, sqrt(lat / maxf(k, 1e-5)))
	var v := PackedFloat32Array()
	v.resize(n)
	v[0] = 0.0
	for i in range(1, n):
		var ds := pts[i - 1].distance_to(pts[i])
		var a_here := acc * maxf(0.08, 1.0 - v[i - 1] / vmax)
		v[i] = minf(cap[i], sqrt(v[i - 1] * v[i - 1] + 2.0 * a_here * ds))
	for i in range(n - 2, -1, -1):
		var ds := pts[i].distance_to(pts[i + 1])
		v[i] = minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * brk * ds))
	var t := 0.0
	for i in range(1, n):
		t += pts[i - 1].distance_to(pts[i]) / maxf(0.5 * (v[i - 1] + v[i]), 0.5)
	return t

# ------------------------------------------------------------------------------------------ the run

## The board's event with this id, or {}.
func find(id: String) -> Dictionary:
	for ev in board:
		if String(ev.id) == id:
			return ev
	return {}

func is_running() -> bool:
	return not run.is_empty()

## In the countdown: the car is held on the line.
func holding() -> bool:
	return is_running() and run.state == "countdown"

func begin(ev: Dictionary, car_key: String) -> void:
	run = {"ev": ev, "state": "countdown", "t": -COUNTDOWN, "cp": 0, "car": car_key, "tiers": tiers_for(ev, car_key),
		"drift": DriftScore.new() if ev.kind == "drift_zone" else null, "speed_sum": 0.0, "cps": ev.cps,
		"rivals": null, "stage": 0, "stage_times": [], "rally": []}
	var seed_value := rng.randi()
	if ev.kind == "race" and int(ev.get("rivals", 0)) > 0:
		run.rivals = StreetRivals.new(ev.path, car_key, int(ev.rivals), seed_value, {"grid": String(ev.get("grid", "")),
			"knockout": bool(ev.get("knockout", false)), "lap_length": float(ev.get("lap_length", 0.0))})
	elif ev.kind == "rally":
		run.rally = MapMissions.rally_times(ev, car_key, seed_value)
	last_result = {}

## A race's field (StreetRivals) while it runs, or null.
func rivals() -> StreetRivals:
	return run.get("rivals") as StreetRivals if is_running() else null

## Where the player stands on the grid: [map position, heading] (beside the line for a drag race).
func grid_pose(ev: Dictionary) -> Array:
	var h := float(ev.heading)
	var p: Vector2 = ev.pos
	if is_running() and run.rivals:
		var g := (run.rivals as StreetRivals).player_grid()
		var ps: Array = (run.rivals as StreetRivals).pose(g.x, g.y)
		p = ps[0]
		h = (ps[1] as Vector2).angle()
	return [p, h]

func abandon() -> void:
	run = {}

## One frame of the run: p the car's map position, v its speed m/s, slip its slip angle (rad), off whether it is
## off the road, crash whether it hit something hard, z the car's vertical height.
## Returns "" or what happened: "go", "cp", "done", "fail".
func tick(dt: float, p: Vector2, v: float, slip: float, off: bool, crash: bool, z := -INF) -> String:
	if not is_running():
		return ""
	var ev: Dictionary = run.ev
	run.t = float(run.t) + dt
	if run.state == "liaison": # a rally between stages: drive to the next start, no clock
		run.t = 0.0
		if p.distance_to(next_target()) < 12.0 and v < 6.0:
			run.state = "countdown"
			run.t = -COUNTDOWN
			return "stage"
		return ""
	if run.state == "countdown":
		if float(run.t) >= 0.0:
			run.state = "running"
			run.t = 0.0
			return "go"
		return ""
	var rv := run.rivals as StreetRivals
	if rv:
		rv.step(dt, p, v)
		if rv.player_out:
			_finish_race(rv.player_out_pos, true)
			return "done"
		if bool(ev.get("knockout", false)) and rv.rivals.filter(func(r): return not bool(r.get("out", false))).is_empty():
			_finish_race(1, false)
			return "done"
	if run.drift:
		(run.drift as DriftScore).step(v, slip, off, crash, dt, float(run.t))
	var cps: PackedVector2Array = run.cps
	var cp_z: PackedFloat32Array = ev.get("cp_z", PackedFloat32Array())
	var cp := int(run.cp)
	var reach := GOAL_RADIUS if ev.kind == "trailblazer" else CHECK_RADIUS
	var z_ok := true
	if is_finite(z) and cp < cp_z.size():
		z_ok = absf(z - cp_z[cp]) <= 4.0
	if z_ok and p.distance_to(cps[cp]) < reach:
		cp += 1
		run.cp = cp
		if cp >= cps.size():
			if ev.kind == "rally":
				return _rally_stage_done()
			if ev.kind == "race":
				_finish_race(rv.position() if rv else 1, false)
			else:
				_finish()
			return "done"
		return "cp"
	if float(run.t) > _time_limit():
		last_result = {"ev": ev, "success": false, "tier": 0, "score": 0.0, "fans": 0, "line": "Out of time"}
		run = {}
		return "fail"
	return ""

func _time_limit() -> float:
	var tiers: Array = run.tiers
	match String(run.ev.kind):
		"race":
			return pace_time(run.ev.path, String(run.car)) * 2.5 + 30.0
		"rally":
			var st: Dictionary = run.ev.stages[int(run.stage)]
			return pace_time(st.path, String(run.car)) * 2.5 + 30.0
		"speed_zone":
			return float(run.ev.length) / (float(tiers[0]) / 3.6) * TIME_OUT
		"drift_zone":
			return pace_time(run.ev.path, String(run.car)) * 3.0 * TIME_OUT
	return float(tiers[0]) * TIME_OUT

func _finish() -> void:
	var ev: Dictionary = run.ev
	var tiers: Array = run.tiers
	var t := float(run.t)
	var score := t
	var tier := 0
	var line := ""
	match String(ev.kind):
		"speed_zone":
			score = float(ev.length) / maxf(t, 0.01) * 3.6
			tier = _tier_high(score, tiers)
			line = "%.1f km/h average" % score
		"drift_zone":
			var d := run.drift as DriftScore
			d.bank(t)
			score = d.score
			tier = _tier_high(score, tiers)
			line = "%s drift points" % OpenWorldHud._thousands(int(score))
		_:
			tier = 3 if t <= float(tiers[2]) else (2 if t <= float(tiers[1]) else (1 if t <= float(tiers[0]) else 0))
			line = clock_text(t)
	var fans := int(FANS_PER_KM * clampf(float(ev.length) / 1000.0, 0.5, 5.0) * TIER_FANS[tier] / 10.0) * 10
	last_result = {"ev": ev, "success": tier > 0, "tier": tier, "score": score, "fans": fans, "line": line,
		"next": _next_text(score, tier, tiers, String(ev.kind))}
	run = {}
	if tier > 0:
		board.erase(ev) # cleared: it makes room for a new one

## A race over: the player's place (knocked: out of a knockout in that place).
func _finish_race(pos: int, knocked: bool) -> void:
	var ev: Dictionary = run.ev
	var t := float(run.t)
	var rv := run.rivals as StreetRivals
	var field := rv.field() if rv else 1
	if rv and bool(ev.get("knockout", false)):
		field = rv.rivals.size() + 1
	var line := "P%d of %d" % [pos, field]
	if knocked:
		line += ", knocked out in %s %d" % ["sector" if ev.get("sectors", false) else "lap", rv.player_lap() + 1 if rv else 1]
	else:
		line += " · %s" % clock_text(t)
	last_result = {"ev": ev, "success": pos <= int(ev.get("target", 3)), "tier": 0, "score": 0.0, "fans": 0, "line": line,
		"pos": pos, "finished": not knocked, "knocked": knocked, "time": t if not knocked else null}
	run = {}

## A rally stage done: on to the liaison, or the event's result after the last stage.
func _rally_stage_done() -> String:
	var ev: Dictionary = run.ev
	(run.stage_times as Array).append(float(run.t))
	var k := int(run.stage) + 1
	if k < (ev.stages as Array).size():
		run.stage = k
		run.state = "liaison"
		run.cp = 0
		run.cps = (ev.stages[k] as Dictionary).cps
		run.t = 0.0
		return "stage_done"
	var mine := 0.0
	for x in run.stage_times:
		mine += float(x)
	var pos := 1
	var best := INF
	for times in run.rally:
		var tot := 0.0
		for x in times:
			tot += float(x)
		best = minf(best, tot)
		if tot < mine:
			pos += 1
	var line := "P%d overall of %d · %s" % [pos, (run.rally as Array).size() + 1, clock_text(mine)]
	if pos > 1 and is_finite(best):
		line += " (+%.1f s)" % (mine - best)
	last_result = {"ev": ev, "success": pos <= int(ev.get("target", 3)), "tier": 0, "score": 0.0, "fans": 0,
		"line": line, "pos": pos, "finished": true, "knocked": false, "time": mine}
	run = {}
	return "done"

## The rally's standings after the stages driven so far: the player's place.
func rally_place() -> int:
	var n := (run.stage_times as Array).size()
	var mine := 0.0
	for x in run.stage_times:
		mine += float(x)
	var pos := 1
	for times in run.rally:
		var tot := 0.0
		for j in n:
			tot += float(times[j])
		if tot < mine:
			pos += 1
	return pos

static func _tier_high(score: float, tiers: Array) -> int:
	return 3 if score >= float(tiers[2]) else (2 if score >= float(tiers[1]) else (1 if score >= float(tiers[0]) else 0))

static func _next_text(score: float, tier: int, tiers: Array, kind: String) -> String:
	if tier >= 3:
		return ""
	var want := float(tiers[tier])
	match kind:
		"speed_zone":
			return "%.1f km/h short of %s" % [want - score, TIER_NAMES[tier + 1].to_lower()]
		"drift_zone":
			return "%s points short of %s" % [OpenWorldHud._thousands(int(want - score)), TIER_NAMES[tier + 1].to_lower()]
	return "%.2f s off %s" % [score - want, TIER_NAMES[tier + 1].to_lower()]

# ------------------------------------------------------------------------------------------ text

static func clock_text(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]

func target_text(ev: Dictionary, car_key: String) -> String:
	var t := tiers_for(ev, car_key)
	match String(ev.kind):
		"speed_zone":
			return "Average %.0f km/h for bronze (silver %.0f, gold %.0f)" % t
		"drift_zone":
			return "Score %s for bronze (silver %s, gold %s)" % [OpenWorldHud._thousands(int(t[0])),
				OpenWorldHud._thousands(int(t[1])), OpenWorldHud._thousands(int(t[2]))]
	return "Bronze %s · silver %s · gold %s" % [clock_text(t[0]), clock_text(t[1]), clock_text(t[2])]

const BLURB := {
	"sprint": "Somebody chalked a start line on the road. Point to point through the town, every checkpoint in order, traffic and all.",
	"speed_zone": "A long, quick stretch. Carry the most speed you can from one end to the other: the average counts.",
	"drift_zone": "The lads are filming this bit. Keep it sideways from the start to the end of the zone; a crash or the verge loses the combo.",
	"trailblazer": "The goal is there and so is the clock. Roads, fields, gardens: whichever way is quickest.",
}

## The briefing card: [subtitle, title, body, hint].
func card(ev: Dictionary, car_key: String) -> Array:
	var mins := int(maxf(0.0, float(ev.expires) - clock_h) * 80.0 / 60.0)
	var length := "%.1f km" % (float(ev.length) / 1000.0) if ev.kind != "trailblazer" else \
		"%.1f km as the crow flies" % ((ev.pos as Vector2).distance_to(ev.goal) / 1000.0)
	var extra := " · %d checkpoints" % (ev.cps as PackedVector2Array).size() if ev.kind == "sprint" else ""
	var body := "%s\n\n%s%s · live for about %d more min\n%s" % [BLURB[ev.kind], length, extra, maxi(mins, 1),
		target_text(ev, car_key)]
	return ["LIVE EVENT · %s" % KIND_NAMES[ev.kind], String(ev.title), body, "ENTER / B  ▸  START EVENT"]

## The HUD's two lines while running: [title, line].
func hud_lines(p: Vector2) -> Array:
	if not is_running():
		return ["", ""]
	var ev: Dictionary = run.ev
	var name := String(Missions.KIND_NAMES.get(ev.get("mkind", ""), "")) if ev.has("mission") else String(KIND_NAMES.get(ev.kind, ""))
	if run.state == "liaison":
		var st: Dictionary = ev.stages[int(run.stage)]
		return ["LIAISON · P%d" % rally_place(), "to SS%d %s · %d m" % [int(run.stage) + 1, st.name, int(p.distance_to(next_target()))]]
	if run.state == "countdown":
		return [name, "%d" % ceili(-float(run.t))]
	var tiers: Array = run.tiers
	var t := float(run.t)
	var cps: PackedVector2Array = run.cps
	match String(ev.kind):
		"race":
			var rv := run.rivals as StreetRivals
			var line := "checkpoint %d/%d" % [int(run.cp) + 1, cps.size()]
			if rv and bool(ev.get("knockout", false)):
				line = "%s %d/%d · %d cars left" % ["sector" if ev.get("sectors", false) else "lap",
					mini(rv.player_lap() + 1, int(ev.laps)), int(ev.laps), rv.field()]
			return ["%s  P%d/%d  %s" % [name, rv.position() if rv else 1, rv.field() if rv else 1, clock_text(t)], line]
		"rally":
			var st: Dictionary = ev.stages[int(run.stage)]
			return ["SS%d %s  %s" % [int(run.stage) + 1, String(st.name).to_upper(), clock_text(t)],
				"checkpoint %d/%d · P%d overall so far" % [int(run.cp) + 1, cps.size(), rally_place()]]
		"speed_zone":
			return ["SPEED ZONE  %s" % clock_text(t), "gold %.0f km/h average" % float(tiers[2])]
		"drift_zone":
			var d := run.drift as DriftScore
			return ["%s  %s" % ["DRIFT" if not ev.has("mission") else name, OpenWorldHud._thousands(d.total())], "×%.1f · gold %s" % [d.mult, OpenWorldHud._thousands(int(tiers[2]))]]
		"trailblazer":
			return ["TRAILBLAZER  %s" % clock_text(t), "%d m to go · gold %s" % [int(p.distance_to(ev.goal)), clock_text(tiers[2])]]
	return ["%s  %s" % [name, clock_text(t)], "checkpoint %d/%d · gold %s" % [int(run.cp) + 1,
		cps.size(), clock_text(tiers[2])]]

## Where the GPS should point while running: the next checkpoint (or the goal).
func next_target() -> Vector2:
	if not is_running():
		return Vector2.ZERO
	if run.state == "liaison":
		return (run.ev.stages[int(run.stage)].path as PackedVector2Array)[0]
	var cps: PackedVector2Array = run.cps
	return cps[mini(int(run.cp), cps.size() - 1)]

# ------------------------------------------------------------------------------------------ geometry

static func path_length(path: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, path.size()):
		l += path[i - 1].distance_to(path[i])
	return l

## Total heading change along the path (rad), measured on a 10 m resample so polyline noise doesn't count.
static func turning(path: PackedVector2Array) -> float:
	var pts := resample(path, 10.0)
	var sum := 0.0
	for i in range(1, pts.size() - 1):
		sum += absf(wrapf((pts[i + 1] - pts[i]).angle() - (pts[i] - pts[i - 1]).angle(), -PI, PI))
	return sum

static func resample(path: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.size() < 2:
		return path
	out.append(path[0])
	var carry := 0.0
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var l := a.distance_to(b)
		if l < 1e-6:
			continue
		var s := step - carry
		while s <= l:
			out.append(a.lerp(b, s / l))
			s += step
		carry = l - (s - step)
	if out[out.size() - 1].distance_to(path[path.size() - 1]) > 0.5:
		out.append(path[path.size() - 1])
	return out

## Points every `spacing` m along the path, the last one at its end.
static func checkpoints(path: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var pts := resample(path, spacing)
	var out := PackedVector2Array()
	for i in range(1, pts.size()):
		out.append(pts[i])
	if out.size() >= 2 and out[out.size() - 1].distance_to(out[out.size() - 2]) < spacing * 0.4:
		out.remove_at(out.size() - 2)
	return out
