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
## (grip-limited corner speeds on the route's own surfaces, the car's acceleration and braking: pace_time), so the
## Golf or the hypercar face harder clocks than the Seicento.
##
## The run plays as Forza Horizon's do. A race or a sprint starts from the card (the car is put on the line, 3 s
## countdown); the PR stunts (speed zone, drift zone, trailblazer) start by simply driving through their start gate
## at speed, no stop and no countdown, against targets for a flying start. Checkpoints are gates across the road
## (crossing the line anywhere inside its width counts); the run follows the car's progress along the route and
## says so when a checkpoint is missed, the car goes the wrong way or leaves the route, and reset_to_checkpoint()
## puts the car back at the last gate it went through. A cleared event stays on the board (its best medal shown)
## for another go until it expires.
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
const CHECK_RADIUS := 10.0 ## m round a checkpoint that counts as through it even without crossing its gate's line
const GATE_HALF_MIN := 9.0 ## m: a checkpoint gate reaches at least this far either side of the route
const GATE_MARGIN := 4.0 ## m beyond the road's edge a gate reaches
const MISS_PAST := 45.0 ## m the car may run on past a checkpoint's gate before it counts as missed
const OFF_ROUTE := 40.0 ## m from the route ...
const OFF_ROUTE_T := 4.0 ## ... for this long is off the route (a trailblazer has no route to keep to)
const WRONG_WAY_T := 1.5 ## s going backwards along the route at speed before it is called the wrong way
const ROLL_MIN := 5.0 ## m/s through a stunt's start gate starts it (18 km/h)
const RUNUP := 160.0 ## m back down the road where ENTER at a stunt puts the car for its run at the gate
const STUNTS := ["speed_zone", "drift_zone", "trailblazer"] ## started by driving through, flying start
const ROLL_ENTRY := 0.7 ## a stunt's reference driver crosses the start at this share of the top speed (corners allowing)
const GOAL_RADIUS := 25.0 ## m round a trailblazer's goal
const CP_SPACING := 420.0 ## m between a sprint's checkpoints
const TIME_OUT := 1.8 ## a run fails once it takes this many times the bronze time (zones: the reference time)
const FANS_PER_KM := 900.0
const TIER_FANS := [0.0, 1.0, 1.6, 2.5]
## Medal times against the reference run (sprint, trailblazer: s; speed zone: average km/h, higher is better).
const TIME_TIERS := [1.34, 1.16, 1.04] ## bronze, silver, gold: the reference time times this
const SPEED_TIERS := [0.72, 0.85, 0.95] ## ... the reference average times this
const VERGE := 2.5 ## m beyond the map's road edge a sliding car may run before it counts as off the road (the lanes
## are 3-5 m wide: a race track's 0.8 m (DriftScore.OFF_ROAD) would lose every combo on them)
## Points per km of a drift zone, bronze / silver / gold: the Babudy drift mission's per km (300/1200/3000 on 2.6 km).
## Measured 2026-11-14 with tests/_live_audit.gd's sliding driver (handbrake taps, counter-steer; STYLE=flick/hard):
## 270-376 points on Babudy, so bronze is a plain sliding run, silver about three times that, gold for the few.
const DRIFT_PER_KM := [115.0, 460.0, 1150.0]
## Reference driving per car (CarCatalog key): top speed m/s, standing acceleration m/s², grip m/s², braking m/s².
## Measured with tests/_car_probe.gd: Seicento 137 km/h, 0.96 g; Golf IV 171 km/h, 0.86 g; hypercar 346 km/h.
const PACE := {"stock": [38.0, 2.4, 8.4, 7.4], "golf4": [47.5, 3.3, 7.6, 7.2], "hypercar": [96.0, 9.0, 13.5, 10.7]}
## The car's own standing start on the map's S1, full throttle with the automatic box (FreeCar, tests/_live_audit.gd,
## 2026-11-13): seconds over 402 m and 1000 m. A drag field (StreetRivals) is calibrated against these.
const DRAG_TIMES := {"stock": [21.0, 40.7], "golf4": [19.3, 37.6], "hypercar": [10.1, 20.0]}
const TOWN_GRIP := 0.9 ## Physics.SURF_GRIP of the map's asphalt, which PACE was measured on

var map: TownMap
var rng := RandomNumberGenerator.new()
var board: Array = [] ## the live events: dictionaries, see _make
var run: Dictionary = {} ## the event being raced: {ev, state ("countdown", "running"), t, cp, drift, car, tiers}
var clock_h := 0.0 ## game hours since the board was started (expiry runs on it)
var last_result: Dictionary = {}
var last_begin: Dictionary = {} ## the last run begun: {ev, car} (RESTART runs it again)
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
	for attempt in 16:
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
	if kind != "trailblazer" and not on_roads(map, path):
		return {}
	_serial += 1
	# the start's heading along the first 10 m (the first few points of a route can sit on a junction's corner)
	var head := resample(path, 5.0)
	var h := (head[mini(2, head.size() - 1)] - path[0]).angle() if path.size() > 1 else 0.0
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

## The medal targets [bronze, silver, gold] of an event for a car (CarCatalog key). `rolling`: from a flying start
## (a stunt driven into), otherwise from a standstill on the line.
func tiers_for(ev: Dictionary, car_key: String, rolling := false) -> Array:
	if ev.has("mission_tiers"):
		return ev.mission_tiers
	var g := grip_of(ev)
	var ref := pace_time(ev.path, car_key, entry_speed(ev.path, car_key, g) if rolling else 0.0, g)
	match String(ev.kind):
		"speed_zone":
			var v := float(ev.length) / ref * 3.6
			return [v * SPEED_TIERS[0], v * SPEED_TIERS[1], v * SPEED_TIERS[2]]
		"drift_zone":
			var km := float(ev.length) / 1000.0
			return [DRIFT_PER_KM[0] * km, DRIFT_PER_KM[1] * km, DRIFT_PER_KM[2] * km]
	return [ref * TIME_TIERS[0], ref * TIME_TIERS[1], ref * TIME_TIERS[2]]

## Whether an event is a PR stunt (started by driving through its gate).
## Whether a route keeps to the drawn roads (every 10 m within OFF_ROADS_MAX of a road's edge). The road graph's
## routes can cut a rounded corner or follow a way that is not drawn; an event there would put its line, its gates
## and its drift zone's verge off the tarmac, so generate() tries another.
const OFF_ROADS_MAX := 2.5
static func on_roads(town: TownMap, path: PackedVector2Array) -> bool:
	if town == null:
		return true
	for p in resample(path, 10.0):
		if town.road_at(p.x, p.y, -INF, OFF_ROADS_MAX).is_empty():
			return false
	return true

static func off_road(town: TownMap, p: Vector2, z: float) -> bool:
	return town.road_at(p.x, p.y, z, VERGE).is_empty()

static func is_stunt(ev: Dictionary) -> bool:
	return String(ev.get("kind", "")) in STUNTS and not ev.has("mission")

## The speed the reference driver crosses a stunt's start at: ROLL_ENTRY of the top speed, or less where the route
## bends right away.
static func entry_speed(path: PackedVector2Array, car_key: String, grip_k := 1.0) -> float:
	var pc: Array = PACE.get(car_key, PACE.stock)
	var pts := resample(path, 5.0)
	var v := float(pc[0]) * ROLL_ENTRY
	for i in range(1, mini(pts.size() - 1, 12)):
		var turn := absf(wrapf((pts[i + 1] - pts[i]).angle() - (pts[i] - pts[i - 1]).angle(), -PI, PI))
		v = minf(v, sqrt(float(pc[2]) * grip_k / maxf(turn / 10.0, 1e-5)))
	return v

## The surface grip of an event's route against town tarmac (1; dirt lanes ~0.75), averaged: the reference driver's
## corners and braking scale with it. Measured on the map once per event.
func grip_of(ev: Dictionary) -> float:
	if ev.has("grip"):
		return float(ev.grip)
	var prof := profile(ev, 25.0)
	var g := 0.0
	var gp: PackedFloat32Array = prof.grip
	for x in gp:
		g += x
	ev["grip"] = g / maxf(gp.size(), 1) if gp.size() > 0 else 1.0
	return float(ev.grip)

## The road under an event's route every `step` m (cached on the event): the road's centre across the route (m, left
## of the direction +), its half width, and its surface's grip against town tarmac. Where the route runs off the
## map's roads (or the nearest road is a different one alongside) the route itself is the centre, 4 m either side.
func profile(ev: Dictionary, step: float) -> Dictionary:
	var key := "_profile_%d" % int(step)
	if ev.has(key):
		return ev[key]
	var prof := route_profile(map, ev.path, step)
	ev[key] = prof
	return prof

static func route_profile(town: TownMap, path: PackedVector2Array, step: float) -> Dictionary:
	var pts := resample(path, step)
	var n := pts.size()
	var centre := PackedFloat32Array()
	var half := PackedFloat32Array()
	var grip := PackedFloat32Array()
	centre.resize(n)
	half.resize(n)
	grip.resize(n)
	for i in n:
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-d.y, d.x)
		half[i] = 4.0
		grip[i] = 1.0
		if town == null:
			continue
		var hit := town.road_at(pts[i].x, pts[i].y, -INF, 6.0)
		if hit.is_empty():
			grip[i] = Physics.SURF_GRIP[Physics.SURF_DIRT] / TOWN_GRIP # off the map's roads: a track through the woods
			continue
		var h := float(hit.half)
		var dir: Vector2 = town.road_pts[int(hit.road)][mini(int(hit.i) + 1, town.road_pts[int(hit.road)].size() - 1)] - town.road_pts[int(hit.road)][int(hit.i)]
		if absf(dir.normalized().dot(d)) < 0.7: # a crossing street, not the one the route runs along
			continue
		half[i] = clampf(h, 1.5, 12.0)
		var c := -float(hit.dist) * signf(dir.dot(d)) # the route's offset from the centreline, turned into across-the-route
		centre[i] = c if absf(c) <= h + 1.0 else 0.0
		var surf := Physics.SURF_TRACK
		match int(hit.surface):
			2: surf = Physics.SURF_GRAVEL_ROAD if int(hit.get("gravel", 0)) else Physics.SURF_DIRT
			1: surf = Physics.SURF_ASPHALT
		grip[i] = minf(1.0, Physics.SURF_GRIP[surf] / TOWN_GRIP)
	# smoothed (a junction or a slip road alongside should not throw the line or the width about)
	return {"centre": _smooth(centre, 5), "half": _smooth(half, 5), "grip": grip}

static func _smooth(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := a.size()
	var out := a.duplicate()
	for i in n:
		var acc := 0.0
		var w := 0
		for j in range(maxi(i - r, 0), mini(i + r + 1, n)):
			acc += a[j]
			w += 1
		out[i] = acc / maxf(w, 1)
	return out

## Seconds a tidy, quick driver in this car takes along the path from `v0` m/s (0: a standing start): corners at the
## car's grip (times `grip_k` for the surface), full throttle between them (acceleration falling off towards the
## top speed), braking in time.
static func pace_time(path: PackedVector2Array, car_key: String, v0 := 0.0, grip_k := 1.0) -> float:
	var pc: Array = PACE.get(car_key, PACE.stock)
	var vmax: float = pc[0]
	var acc: float = pc[1] * lerpf(0.75, 1.0, clampf(grip_k, 0.0, 1.0))
	var lat: float = pc[2] * grip_k
	var brk: float = pc[3] * grip_k
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
	v[0] = minf(v0, cap[0])
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

## The car's own standing-start time over `dist` m (DRAG_TIMES, a power law between and beyond the two marks).
static func drag_time(car_key: String, dist: float) -> float:
	var dt: Array = DRAG_TIMES.get(car_key, DRAG_TIMES.stock)
	var k := log(float(dt[1]) / float(dt[0])) / log(1000.0 / 402.0)
	return float(dt[0]) * pow(maxf(dist, 1.0) / 402.0, k)

# ------------------------------------------------------------------------------------------ the run

const TRACK_STEP := 2.0 ## m between the samples the car's progress along the route is followed on

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

## Starts an event. opts: rolling (a stunt driven into at speed: no countdown, the flying-start targets), at (the
## car's map position as it starts).
func begin(ev: Dictionary, car_key: String, opts := {}) -> void:
	var rolling := bool(opts.get("rolling", false)) and is_stunt(ev)
	run = {"ev": ev, "state": "running" if rolling else "countdown", "t": 0.0 if rolling else -COUNTDOWN, "cp": 0,
		"car": car_key, "tiers": tiers_for(ev, car_key, rolling), "rolling": rolling,
		"drift": DriftScore.new() if ev.kind == "drift_zone" else null, "speed_sum": 0.0, "cps": ev.cps,
		"rivals": null, "stage": 0, "stage_times": [], "rally": [], "notice": "", "wrong_t": 0.0, "off_t": 0.0,
		"lost_t": 0.0, "resets": 0}
	var seed_value := rng.randi()
	if ev.kind == "race" and int(ev.get("rivals", 0)) > 0:
		var ro := {"grid": String(ev.get("grid", "")), "knockout": bool(ev.get("knockout", false)),
			"lap_length": float(ev.get("lap_length", 0.0)), "difficulty": String(ev.get("difficulty", "medium")),
			"profile": profile(ev, StreetRivals.STEP)}
		if String(ev.get("grid", "")) == "drag":
			ro["drag_time"] = drag_time(car_key, float(ev.length))
		run.rivals = StreetRivals.new(ev.path, car_key, int(ev.rivals), seed_value, ro)
	elif ev.kind == "rally":
		var grips := []
		for st in ev.stages:
			if not st.has("grip"):
				st["grip"] = grip_of({"path": st.path})
			grips.append(float(st.grip))
		run.rally = MapMissions.rally_times(ev, car_key, seed_value, grips)
	if ev.kind == "rally":
		_arm(ev.stages[0].path, ev.stages[0].cps)
	else:
		_arm(ev.path, ev.cps)
	if opts.has("at"):
		run.prev = opts.at
	last_begin = {"ev": ev, "car": car_key}
	last_result = {}

## The run's route followed from its start: the samples, the distance along it of each checkpoint and each
## checkpoint's gate {pos, dir, half}.
func _arm(path: PackedVector2Array, cps: PackedVector2Array) -> void:
	var pts := resample(path, TRACK_STEP)
	var n := pts.size()
	run.track = pts
	run.s = 0.0
	run.prev = pts[0] if n > 0 else Vector2.ZERO
	run.cps = cps
	var cp_s := PackedFloat32Array()
	var gates := []
	var from := 0
	for k in cps.size():
		var c := cps[k]
		var bi := n - 1
		if k < cps.size() - 1:
			# the nearest sample a little way on from the last checkpoint (a route may come back past an earlier spot)
			var best := INF
			for i in range(from, mini(from + int(CP_SPACING * 1.8 / TRACK_STEP), n)):
				var d := pts[i].distance_squared_to(c)
				if d < best:
					best = d
					bi = i
		from = bi
		cp_s.append(bi * TRACK_STEP)
		# the road's direction over 24 m: a kink in the route line at the gate (the old circuits zig-zag a little) must not turn it round
		var dir := (pts[mini(bi + 6, n - 1)] - pts[maxi(bi - 6, 0)]).normalized() if n > 1 else Vector2.RIGHT
		gates.append({"pos": c, "dir": dir, "half": _gate_half(c)})
	run.cp_s = cp_s
	run.gates = gates

func _gate_half(c: Vector2) -> float:
	if map == null:
		return GATE_HALF_MIN
	var hit := map.road_at(c.x, c.y, -INF, 3.0)
	return maxf(GATE_HALF_MIN, float(hit.half) + GATE_MARGIN) if not hit.is_empty() else GATE_HALF_MIN

## Whether the move a -> b crossed a gate's line inside its width (forwards, or either way when `any_way`).
static func crossed(gate: Dictionary, a: Vector2, b: Vector2, any_way := false) -> bool:
	var d: Vector2 = gate.dir
	if not any_way and (b - a).dot(d) <= 0.0:
		return false
	var c: Vector2 = gate.pos
	var across := Vector2(-d.y, d.x) * float(gate.half)
	return Geometry2D.segment_intersects_segment(a, b, c - across, c + across) != null

## The gates the world shows: the next one and the one after it ({} past the end).
func gates_ahead() -> Array:
	if not is_running() or run.state == "liaison" or not run.has("gates"):
		return [{}, {}]
	var gates: Array = run.gates
	var cp := int(run.cp)
	return [gates[cp] if cp < gates.size() else {}, gates[cp + 1] if cp + 1 < gates.size() else {}]

## A race's field (StreetRivals) while it runs, or null.
func rivals() -> StreetRivals:
	return run.get("rivals") as StreetRivals if is_running() else null

## Where the player stands on the grid: [map position, heading] (in its own lane for a drag race), on the road.
func grid_pose(ev: Dictionary) -> Array:
	var h := float(ev.heading)
	var p: Vector2 = ev.pos
	if is_running() and run.rivals:
		var g := (run.rivals as StreetRivals).player_grid()
		var ps: Array = (run.rivals as StreetRivals).pose(g.x, g.y)
		p = ps[0]
		h = (ps[1] as Vector2).angle()
	return [_on_road(p), h]

## A point moved onto the nearest road when it lies off it (the older circuits run a few metres off the map's lines).
func _on_road(p: Vector2) -> Vector2:
	if map == null or not map.road_at(p.x, p.y, -INF, 0.0).is_empty():
		return p
	var near := map.nearest_road(p, 15.0)
	return near.pos if not near.is_empty() else p

func abandon() -> void:
	run = {}

## Where reset_to_checkpoint() puts the car: [map position, heading] at the last gate the car went through (the
## start before the first), on the road, facing on along the route. [] outside a run or in a liaison.
func reset_pose() -> Array:
	if not is_running() or run.state == "liaison":
		return []
	var cp := int(run.cp)
	if cp == 0 and run.rivals:
		return grid_pose(run.ev)
	var pts: PackedVector2Array = run.track
	var s := 0.0 if cp == 0 else float((run.cp_s as PackedFloat32Array)[cp - 1])
	var i := clampi(int(s / TRACK_STEP), 0, maxi(pts.size() - 2, 0))
	var d := (pts[mini(i + 4, pts.size() - 1)] - pts[i]).normalized()
	return [_on_road(pts[i]), d.angle()]

## The car back at the last gate (Forza's reset): the notices cleared, a drift combo lost. Returns reset_pose().
func reset_to_checkpoint() -> Array:
	var pose := reset_pose()
	if pose.is_empty():
		return pose
	var cp := int(run.cp)
	run.s = 0.0 if cp == 0 else float((run.cp_s as PackedFloat32Array)[cp - 1])
	run.prev = pose[0]
	run.notice = ""
	run.wrong_t = 0.0
	run.off_t = 0.0
	run.resets = int(run.resets) + 1
	if run.drift:
		(run.drift as DriftScore).step(0.0, 0.0, false, true, 0.0, float(run.t))
	return pose

## The PR stunt on the board whose start gate the car just drove through (a -> b at v m/s, the right way), or {}.
func drive_through(a: Vector2, b: Vector2, v: float) -> Dictionary:
	if is_running() or v < ROLL_MIN:
		return {}
	for ev in board:
		if not is_stunt(ev) or (ev.pos as Vector2).distance_to(b) > 40.0:
			continue
		if crossed(start_gate(ev), a, b):
			return ev
	return {}

## A stunt's start gate {pos, dir, half} (cached on the event).
func start_gate(ev: Dictionary) -> Dictionary:
	if not ev.has("gate"):
		ev["gate"] = {"pos": ev.pos, "dir": Vector2.from_angle(float(ev.heading)), "half": _gate_half(ev.pos)}
	return ev.gate

## Where ENTER at a stunt puts the car for its run at the gate: [map position, heading] on the road RUNUP m (or less)
## back from the start, the road there leading into the gate; [] when there is no such road (a dead end behind it).
func runup_pose(ev: Dictionary) -> Array:
	if map == null:
		return []
	var d := Vector2.from_angle(float(ev.heading))
	for back in [RUNUP, RUNUP * 0.6, RUNUP * 0.35]:
		var hit := map.nearest_road((ev.pos as Vector2) - d * back, 25.0)
		if hit.is_empty() or not map.in_play(hit.pos) or _on_deck(hit):
			continue
		var r := map.route(hit.pos, ev.pos)
		if r.size() < 2 or path_length(r) > back * 1.6 + 30.0:
			continue
		if (r[r.size() - 1] - r[maxi(r.size() - 4, 0)]).normalized().dot(d) < 0.7:
			continue
		return [hit.pos as Vector2, (r[mini(3, r.size() - 1)] - r[0]).angle()]
	return []

## One frame of the run: p the car's map position, v its speed m/s, slip its slip angle (rad), off whether it is
## off the road, crash whether it hit something hard, z the car's vertical height.
## Returns "" or what happened: "go", "cp", "warn" (a new notice: missed checkpoint, wrong way, off the route),
## "stage_done", "stage", "done", "fail".
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
			run.prev = p
			return "stage"
		return ""
	if run.state == "countdown":
		run.prev = p
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
	var prev: Vector2 = run.prev
	run.prev = p
	var said := _follow(dt, p, v)
	var cps: PackedVector2Array = run.cps
	var cp_z: PackedFloat32Array = ev.get("cp_z", PackedFloat32Array()) if ev.kind != "rally" else PackedFloat32Array()
	var cp := int(run.cp)
	var z_ok := true
	if is_finite(z) and cp < cp_z.size():
		z_ok = absf(z - cp_z[cp]) <= 4.0
	var through := false
	if z_ok:
		if ev.kind == "trailblazer":
			through = p.distance_to(cps[cp]) < GOAL_RADIUS
		else:
			through = p.distance_to(cps[cp]) < CHECK_RADIUS or crossed(run.gates[cp], prev, p, run.notice == "missed")
	if through:
		cp += 1
		run.cp = cp
		if run.notice == "missed":
			run.notice = ""
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
		last_result = {"ev": ev, "success": false, "tier": 0, "score": 0.0, "fans": 0, "line": "Out of time", "failed": true}
		if ev.kind in ["race", "rally"]:
			last_result.merge({"pos": 999, "finished": false, "knocked": false, "time": null})
		run = {}
		return "fail"
	return said

## The car's progress along the route and the notices it earns: a checkpoint run past (missed), going backwards
## at speed (wrong way), far off the route for a while (off route). Returns "warn" when a new notice comes up.
func _follow(dt: float, p: Vector2, v: float) -> String:
	if String(run.ev.kind) == "trailblazer":
		return ""
	var pts: PackedVector2Array = run.track
	if pts.size() < 2:
		return ""
	var s0 := float(run.s)
	var cp := int(run.cp)
	var cp_s: PackedFloat32Array = run.cp_s
	var last_s := 0.0 if cp == 0 else cp_s[cp - 1]
	var r := _project(pts, p, maxf(s0 - 40.0, last_s - 100.0), s0 + 100.0)
	run.lost_t = float(run.lost_t) - dt
	if r.y > 30.0 and float(run.lost_t) <= 0.0:
		# lost (a shortcut, a spin, a reset): look again over the stretch round the next checkpoint
		run.lost_t = 0.5
		var hi := (cp_s[cp] if cp < cp_s.size() else s0) + 300.0
		var r2 := _project(pts, p, last_s - 100.0, hi)
		if r2.y < r.y:
			r = r2
	run.s = r.x
	var dist := r.y
	var ds := float(run.s) - s0
	if v > 4.0 and ds < -0.4 * v * dt:
		run.wrong_t = float(run.wrong_t) + dt
	elif ds > 0.0 or v < 1.0:
		run.wrong_t = 0.0
	run.off_t = float(run.off_t) + dt if dist > OFF_ROUTE else 0.0
	var missed := cp < cp_s.size() - 1 and float(run.s) > cp_s[cp] + MISS_PAST and dist < OFF_ROUTE
	var notice := "missed" if missed or run.notice == "missed" else ("wrong_way" if float(run.wrong_t) >= WRONG_WAY_T \
		else ("off_route" if float(run.off_t) >= OFF_ROUTE_T else ""))
	if notice != String(run.notice):
		run.notice = notice
		if notice != "":
			return "warn"
	return ""

## [distance along, distance from] the route samples between s_lo and s_hi nearest to p.
static func _project(pts: PackedVector2Array, p: Vector2, s_lo: float, s_hi: float) -> Vector2:
	var lo := clampi(int(s_lo / TRACK_STEP), 0, pts.size() - 2)
	var hi := clampi(int(s_hi / TRACK_STEP) + 1, lo + 1, pts.size() - 1)
	var best := INF
	var bs := 0.0
	for i in range(lo, hi):
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			bs = i * TRACK_STEP + pts[i].distance_to(q)
	return Vector2(bs, sqrt(best))

## How far along the run's route the car has come and how long it is, m.
func progress() -> Vector2:
	if not is_running() or not run.has("track"):
		return Vector2.ZERO
	return Vector2(float(run.s), maxf((run.track as PackedVector2Array).size() - 1, 0) * TRACK_STEP)

func _time_limit() -> float:
	var tiers: Array = run.tiers
	match String(run.ev.kind):
		"race":
			return pace_time(run.ev.path, String(run.car), 0.0, grip_of(run.ev)) * 2.5 + 30.0
		"rally":
			var st: Dictionary = run.ev.stages[int(run.stage)]
			return pace_time(st.path, String(run.car), 0.0, float(st.get("grip", 1.0))) * 2.5 + 30.0
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
	var higher := true
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
			higher = false
			tier = 3 if t <= float(tiers[2]) else (2 if t <= float(tiers[1]) else (1 if t <= float(tiers[0]) else 0))
			line = clock_text(t)
	# the personal best and the best medal stay on the event (it stays up for another go)
	var had := ev.has("best")
	var new_best := not had or (score > float(ev.best) if higher else score < float(ev.best))
	if new_best:
		ev["best"] = score
	var before := int(ev.get("best_tier", 0))
	ev["best_tier"] = maxi(before, tier)
	# fans: a medal better than the one already won pays the difference; a repeat of it pays a tenth
	var per := FANS_PER_KM * clampf(float(ev.length) / 1000.0, 0.5, 5.0) / 10.0
	var fans := 0
	if tier > before:
		fans = int(per * (TIER_FANS[tier] - TIER_FANS[before])) * 10
	elif tier > 0:
		fans = int(per * TIER_FANS[tier] * 0.1) * 10
	last_result = {"ev": ev, "success": tier > 0, "tier": tier, "score": score, "fans": fans, "line": line,
		"next": _next_text(score, tier, tiers, String(ev.kind)), "new_best": new_best and had, "first": not had,
		"best_line": _score_text(String(ev.kind), float(ev.best)), "rolling": bool(run.rolling), "time": t}
	run = {}

static func _score_text(kind: String, score: float) -> String:
	match kind:
		"speed_zone":
			return "%.1f km/h" % score
		"drift_zone":
			return "%s points" % OpenWorldHud._thousands(int(score))
	return clock_text(score)

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
		run.t = 0.0
		run.notice = ""
		_arm(ev.stages[k].path, ev.stages[k].cps)
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

## Where a rally stage starts: [map position on the road, heading].
func stage_pose(k: int) -> Array:
	var path: PackedVector2Array = run.ev.stages[k].path
	return [_on_road(path[0]), (path[mini(3, path.size() - 1)] - path[0]).angle()]

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

## The stars line: "★ 54  ★★ 64  ★★★ 71" (km/h, points or times).
static func stars_text(kind: String, tiers: Array) -> String:
	var parts := PackedStringArray()
	for k in 3:
		var v := float(tiers[k])
		var txt := "%.0f" % v if kind == "speed_zone" else (OpenWorldHud._thousands(int(v)) if kind == "drift_zone" else clock_text(v))
		parts.append("%s %s" % ["★".repeat(k + 1), txt])
	return "  ".join(parts)

func target_text(ev: Dictionary, car_key: String) -> String:
	var t := tiers_for(ev, car_key, is_stunt(ev))
	match String(ev.kind):
		"speed_zone":
			return "Average %.0f km/h for bronze (silver %.0f, gold %.0f)" % t
		"drift_zone":
			return "Score %s for bronze (silver %s, gold %s)" % [OpenWorldHud._thousands(int(t[0])),
				OpenWorldHud._thousands(int(t[1])), OpenWorldHud._thousands(int(t[2]))]
	return "Bronze %s · silver %s · gold %s" % [clock_text(t[0]), clock_text(t[1]), clock_text(t[2])]

const BLURB := {
	"sprint": "Somebody chalked a start line on the road. Point to point through the town, every checkpoint gate in order, traffic and all.",
	"speed_zone": "A long, quick stretch. Hit the start gate flat out and carry the most speed you can to the end: the average counts.",
	"drift_zone": "The lads are filming this bit. Come in sideways and keep it there to the end of the zone; a crash or the verge loses the combo.",
	"trailblazer": "The goal is there and the clock starts at the gate. Roads, fields, gardens: whichever way is quickest.",
}

## The briefing card: [subtitle, title, body, hint].
func card(ev: Dictionary, car_key: String) -> Array:
	var mins := int(maxf(0.0, float(ev.expires) - clock_h) * 80.0 / 60.0)
	var length := "%.1f km" % (float(ev.length) / 1000.0) if ev.kind != "trailblazer" else \
		"%.1f km as the crow flies" % ((ev.pos as Vector2).distance_to(ev.goal) / 1000.0)
	var extra := " · %d checkpoints" % (ev.cps as PackedVector2Array).size() if ev.kind == "sprint" else ""
	var best := ""
	if ev.has("best"):
		best = "\nYour best: %s%s" % [_score_text(String(ev.kind), float(ev.best)),
			(" · %s" % TIER_NAMES[int(ev.best_tier)]) if int(ev.get("best_tier", 0)) > 0 else ""]
	var body := "%s\n\n%s%s · live for about %d more min\n%s%s" % [BLURB[ev.kind], length, extra, maxi(mins, 1),
		target_text(ev, car_key), best]
	var hint := "DRIVE THROUGH THE GATE TO START  ·  ENTER / B  ▸  RUN-UP" if is_stunt(ev) else "ENTER / B  ▸  START EVENT"
	return ["LIVE EVENT · %s" % KIND_NAMES[ev.kind], String(ev.title), body, hint]

const NOTICES := {"missed": "MISSED CHECKPOINT · turn back, or R to reset", "wrong_way": "WRONG WAY",
	"off_route": "OFF ROUTE · follow the GPS, or R to reset"}

## The HUD's two lines while running: [title, line]. A notice (missed checkpoint, wrong way, off route) takes the
## second line.
func hud_lines(p: Vector2) -> Array:
	if not is_running():
		return ["", ""]
	var ev: Dictionary = run.ev
	var name := String(Missions.KIND_NAMES.get(ev.get("mkind", ""), "")) if ev.has("mission") else String(KIND_NAMES.get(ev.kind, ""))
	if run.state == "liaison":
		var st: Dictionary = ev.stages[int(run.stage)]
		return ["LIAISON · P%d" % rally_place(), "to SS%d %s · %d m · stop on the line" % [int(run.stage) + 1, st.name,
			int(p.distance_to(next_target()))]]
	if run.state == "countdown":
		return ["%d" % ceili(-float(run.t)), name] # the count in the big line
	var tiers: Array = run.tiers
	var t := float(run.t)
	var cps: PackedVector2Array = run.cps
	var pr := progress()
	var dist := "%.1f / %.1f km" % [pr.x / 1000.0, pr.y / 1000.0] if pr.y >= 1500.0 else "%d m to go" % maxi(int(pr.y - pr.x), 0)
	var title := ""
	var line := ""
	match String(ev.kind):
		"race":
			var rv := run.rivals as StreetRivals
			title = "%s  P%d/%d  %s" % [name, rv.position() if rv else 1, rv.field() if rv else 1, clock_text(t)]
			line = "CP %d/%d · %s" % [mini(int(run.cp) + 1, cps.size()), cps.size(), dist] if cps.size() > 1 else dist
			if rv and bool(ev.get("knockout", false)):
				line = "%s %d/%d · %d cars left · %s" % ["SECTOR" if ev.get("sectors", false) else "LAP",
					mini(rv.player_lap() + 1, int(ev.laps)), int(ev.laps), rv.field(), dist]
		"rally":
			var st: Dictionary = ev.stages[int(run.stage)]
			title = "SS%d %s  %s" % [int(run.stage) + 1, String(st.name).to_upper(), clock_text(t)]
			line = "CP %d/%d · %s · P%d overall so far" % [int(run.cp) + 1, cps.size(), dist, rally_place()]
		"speed_zone":
			var avg := pr.x / maxf(t, 0.1) * 3.6
			title = "SPEED ZONE  %s  %s" % ["%.0f km/h" % avg if t >= 1.5 else "--- km/h", "★".repeat(_tier_high(avg, tiers)) if t >= 1.5 else ""]
			line = "%s · %s" % [stars_text("speed_zone", tiers), dist]
		"drift_zone":
			var d := run.drift as DriftScore
			title = "%s  %s  ×%.1f  %s" % ["DRIFT ZONE" if not ev.has("mission") else name, OpenWorldHud._thousands(d.total()),
				d.mult, "★".repeat(_tier_high(d.total(), tiers))]
			line = "%s · %s" % [stars_text("drift_zone", tiers), dist]
		"trailblazer":
			var got := 3 if t <= float(tiers[2]) else (2 if t <= float(tiers[1]) else (1 if t <= float(tiers[0]) else 0))
			title = "TRAILBLAZER  %s  %s" % [clock_text(t), "★".repeat(got)]
			line = "%d m to the goal · %s" % [int(p.distance_to(ev.goal)), stars_text("trailblazer", tiers)]
		_:
			title = "%s  %s" % [name, clock_text(t)]
			line = "CP %d/%d · %s · %s" % [mini(int(run.cp) + 1, cps.size()), cps.size(), dist, stars_text("sprint", tiers)]
	if String(run.notice) != "":
		line = String(NOTICES.get(run.notice, ""))
	return [title, line]

## Where the GPS should point while running: the next checkpoint (or the goal, or the next stage's start).
func next_target() -> Vector2:
	if not is_running():
		return Vector2.ZERO
	if run.state == "liaison":
		return stage_pose(int(run.stage))[0]
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
