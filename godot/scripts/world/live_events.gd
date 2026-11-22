## Live events: missions the open world makes up on the real Brzeszcze roads round the player and runs right there,
## Forza Horizon style. Each is a full mission of one of the campaign's kinds (Missions.KINDS), in the same shape as a
## campaign mission on the map (MapMissions.event) and run by the same code (begin / tick here, OpenWorld's
## _start_run, the rivals, the results card), only built on the roads round the car instead of a baked track:
##   sprint    point to point through the town against a StreetRivals field (1.4-5.2 km, mostly paved)
##   drag      402 m or 1000 m from a standstill on a straight, wide main road, four abreast
##   knockout  a 2.4-4.6 km route cut into sectors: the last car is out at each sector line
##   offroad   a race on a route that is mostly gravel and dirt
##   drift     a twisty stretch, solo, scored in drift points (DriftScore) against tiers per km
##   rally     one special stage on loose or twisty roads, from a standing start against the crews' times
## (the old speed zones folded into the drags, which now take the straight main roads, and the trailblazers into the
## sprints: neither fitted a race against a field.)
##
## A board of up to MAX_LIVE events stands within SPAWN_MIN..SPAWN_MAX of the car; each lasts LIFE_H game hours and is
## replaced when it expires or the car leaves it far behind; a cleared one stays up (its best medal shown) for another
## go. Targets are places like a mission's (drift: the bronze tier), the field's difficulty eases after missed tries
## of that kind as a mission's does (WorldProgress.live.fails), and they pay fans by length and difficulty. They never
## award cars or trophies and never count toward the campaign: their stats are WorldProgress.live.
##
## The class is free of the scene (OpenWorld drives it): generate() and the run (begin / tick / abandon) only need a
## TownMap, so tests/test_live_events.gd runs it headless.
class_name LiveEvents
extends RefCounted

const KINDS := ["sprint", "drag", "knockout", "offroad", "drift", "rally"]
const KIND_WEIGHTS := [0.26, 0.16, 0.14, 0.15, 0.14, 0.15]
## Names by mission kind (and, for older callers, by the run's own kind).
const KIND_NAMES := {"sprint": "SPRINT", "drag": "DRAG RACE", "knockout": "KNOCKOUT", "offroad": "OFF-ROAD", "drift": "DRIFT",
	"rally": "RALLY", "race": "RACE", "drift_zone": "DRIFT"}
const COLORS := {"sprint": Color("#ff3d8b"), "drag": Color("#ffd23f"), "knockout": Color("#ff8a3d"), "offroad": Color("#c9a061"),
	"drift": Color("#7dff6a"), "rally": Color("#4ad8ff")}
const RIVALS := {"sprint": Vector2i(5, 7), "drag": Vector2i(3, 3), "knockout": Vector2i(3, 5), "offroad": Vector2i(4, 5),
	"drift": Vector2i(0, 0), "rally": Vector2i(6, 9)} ## the field's size (rally: the crews)
const TARGETS := {"sprint": 3, "drag": 1, "knockout": 2, "offroad": 3, "drift": 3, "rally": 3} ## place to finish in (drift: 3 is bronze)
const DIFFICULTY_WEIGHTS := [0.35, 0.45, 0.20] ## easy, medium, hard (Campaign.LEVELS)
const DIFF_FANS := {"easy": 0.8, "medium": 1.0, "hard": 1.35}
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
const OFF_ROUTE_T := 4.0 ## ... for this long is off the route
const WRONG_WAY_T := 1.5 ## s going backwards along the route at speed before it is called the wrong way
const CP_SPACING := 420.0 ## m between a route's checkpoints
const TIME_OUT := 1.8 ## a drift run fails once it takes this many times three reference runs
const FANS_PER_KM := 1200.0 ## a clear at the target place, medium field, per km (at least 1.5 km's worth)
const DRAG_LENGTHS := [402.0, 402.0, 1000.0]
const DRAG_HALF := 3.1 ## m: a drag's road must be at least this wide either side of its line all the way: three abreast
## (StreetRivals.drag_rivals_fit; four where the road is 3.7 m either side) with every car's body on the tarmac
const START_STRAIGHT := 60.0 ## m after the line over which a route may turn at most ...
const START_TURN := 1.7 ## ... this many rad (a corner, not a U-turn or a zig-zag: the grid stands there)
const DRAG_TURN := 0.4 ## rad: the most a drag's road may bend over its length
const UNPAVED_OFFROAD := 0.45 ## share of an off-road route on gravel or dirt (a sprint or knockout route with more is not made)
const UNPAVED_RALLY := 0.35 ## ... of a rally stage (or a twisty one, RALLY_TWIST)
const RALLY_TWIST := 1.6 ## rad per km
const VERGE := 2.5 ## m beyond the map's road edge a sliding car may run before it counts as off the road (the lanes
## are 3-5 m wide: a race track's 0.8 m (DriftScore.OFF_ROAD) would lose every combo on them)
## Points per km of a drift, bronze / silver / gold: the Babudy drift mission's per km (450/1800/4500 on 2.6 km).
## Measured 2026-11-14 with tests/_live_audit.gd's sliding driver (handbrake taps, counter-steer; STYLE=flick/hard):
## 270-376 points on Babudy, so bronze is a plain sliding run, silver about three times that, gold for the few.
## Raised x1.5 on 2026-11-22 with DriftScore's angle, speed and linked-corner bonuses (a deep, fast, linked run pays
## up to about 2.4x what it did; a tidy one about the same).
const DRIFT_PER_KM := [172.5, 690.0, 1725.0]
## Reference driving per car (CarCatalog key): top speed m/s, standing acceleration m/s², grip m/s², braking m/s².
## Measured with tests/_car_probe.gd and tests/_pace_probe.gd (2026-11-21): Seicento 137 km/h, 0.96 g (anchor);
## Golf IV 171 km/h, 0.86 g, 100-0 in 39.3 m; Logan 162 km/h, 0.84 g, 100-0 in 39.1 m; hypercar 346 km/h;
## V50 2.4i 211 km/h, 0.86 g, 100-0 in 36.5 m (S1 drags 15.95 s / 30.25 s; bot/pace 1.47 town, 1.31 S1 sprint, between the
## Golf's and the hypercar's); i20 1.4 180 km/h, 0.86 g, 100-0 in 38.6 m (S1 drags 17.94 s / 34.07 s; bot/pace 1.46 town,
## 1.26 S1 sprint, between the Golf's and the V50's); Sandero 1.6 174 km/h, 0.84 g, 100-0 in 39.3 m (S1 drags 17.91 s /
## 34.33 s; bot/pace 1.45 town, 1.26 S1 sprint); Focus 1.5 210 km/h, 0.89 g, 100-0 in 37.7 m (S1 drags 16.18 s / 30.74 s;
## bot/pace 1.48 town, 1.32 S1 sprint); Zafira B 1.8 197 km/h, 0.83 g, 100-0 in 38.5 m (S1 drags 17.95 s / 35.70 s;
## bot/pace 1.46 town, 1.29 S1 sprint).
## Acceleration is fitted to each car's measured S1 drag and sprint runs against the Seicento anchor; grip and braking
## are the town tarmac's share of the probe's figures.
const PACE := {"stock": [38.0, 2.4, 8.4, 7.4], "golf4": [47.5, 2.7, 7.6, 6.9], "logan": [45.0, 2.9, 7.4, 6.9], "v50": [58.5, 3.4, 7.6, 7.4], "i20": [50.0, 3.0, 7.5, 7.1], "sandero": [48.3, 3.0, 7.4, 6.9], "focus": [58.3, 3.5, 7.9, 7.2], "zafira": [54.7, 2.8, 7.3, 7.1], "hypercar": [96.0, 9.0, 13.5, 12.0]}
## The car's own standing start on the map's S1 (the drag_kilometre mission's line), full throttle with the automatic
## box (FreeCar), measured with tests/_pace_probe.gd (2026-11-21): seconds over 402 m and 1000 m. A drag field
## (StreetRivals) is calibrated against these (scaled by grip_k via pace_time when wet).
const DRAG_TIMES := {"stock": [21.0, 40.6], "golf4": [19.1, 36.5], "logan": [18.8, 35.9], "v50": [16.0, 30.3], "i20": [17.9, 34.1], "sandero": [17.9, 34.3], "focus": [16.2, 30.7], "zafira": [18.0, 35.7], "hypercar": [9.9, 18.0]}
const TOWN_GRIP := 0.9 ## Physics.SURF_GRIP of the map's asphalt, which PACE was measured on

var map: TownMap
var rng := RandomNumberGenerator.new()
var board: Array = [] ## the live events: mission-shaped dictionaries, see _make
var run: Dictionary = {} ## the event being raced: {ev, state ("countdown", "running", "liaison"), t, cp, drift, car, tiers, rivals...}
var clock_h := 0.0 ## game hours since the board was started (expiry runs on it)
var last_result: Dictionary = {}
var last_begin: Dictionary = {} ## the last run begun: {ev, car} (RESTART runs it again)
var stats: Dictionary = {} ## WorldProgress.live (OpenWorld hands it over): the missed tries per kind ease the field
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
			"sprint", "knockout":
				ev = _make_route(start, k)
			"offroad":
				ev = _make_route(start, k)
			"drag":
				ev = _make_drag(start)
			"drift":
				ev = _make_drift(start)
			"rally":
				ev = _make_rally(start)
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
## Off-road races and rallies start on a gravel or dirt road.
func _road_point(p: Vector2, kind: String) -> Dictionary:
	var min_rank := 6 if kind == "drag" else (3 if kind in ["sprint", "knockout"] else 1)
	if kind == "offroad":
		return _loose_point(p, SPAWN_MIN, SPAWN_MAX)
	var loose := kind == "rally"
	for attempt in (16 if loose else 8):
		var a := rng.randf() * TAU
		var d := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var q := p + Vector2(cos(a), sin(a)) * d
		if not map.in_play(q):
			continue
		var hit := map.nearest_road(q, 120.0 if not loose else 200.0, min_rank)
		if hit.is_empty() or not map.in_play(hit.pos) or _on_deck(hit):
			continue
		if loose and kind == "offroad" and map.road_surface[int(hit.road)] != 2:
			continue
		return hit
	return {}

## A point on a gravel or dirt road between lo and hi m from p (the map's loose roads sampled every 50 m, once):
## the nearest_road hit there, or {}.
func _loose_point(p: Vector2, lo: float, hi: float) -> Dictionary:
	if _loose.is_empty():
		for ri in map.road_pts.size():
			if map.road_surface[ri] != 2 or map.road_len[ri] < 120.0:
				continue
			for q in resample(map.road_pts[ri], 50.0):
				if map.in_play(q):
					_loose.append(q)
	var pick := PackedVector2Array()
	for q in _loose:
		var d := q.distance_to(p)
		if d >= lo and d <= hi:
			pick.append(q)
	for attempt in 6:
		if pick.is_empty():
			return {}
		var hit := map.nearest_road(pick[rng.randi() % pick.size()], 6.0, 1)
		if not hit.is_empty() and map.road_surface[int(hit.road)] == 2 and not _on_deck(hit):
			return hit
	return {}

var _loose := PackedVector2Array()

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

## A point-to-point race: a sprint (mostly paved), a knockout (longer, cut into sectors) or an off-road race (mostly
## gravel and dirt, its goal on a loose road too).
func _make_route(start: Dictionary, kind: String) -> Dictionary:
	var lo := 1400.0
	var hi := 5200.0
	var reach := Vector2(1500.0, 3200.0)
	if kind == "knockout":
		lo = 2400.0
		hi = 4600.0
		reach = Vector2(2000.0, 3400.0)
	elif kind == "offroad":
		lo = 1200.0
		hi = 4500.0
		reach = Vector2(1100.0, 2800.0)
	var goal := {}
	if kind == "offroad":
		goal = _loose_point(start.pos, reach.x, reach.y)
	else:
		var a := rng.randf() * TAU
		goal = map.nearest_road((start.pos as Vector2) + Vector2(cos(a), sin(a)) * rng.randf_range(reach.x, reach.y), 150.0, 3)
	if goal.is_empty() or not map.in_play(goal.pos):
		return {}
	var path := map.route(start.pos, goal.pos)
	var length := path_length(path)
	if length < lo or length > hi or length > 2.3 * (start.pos as Vector2).distance_to(goal.pos):
		return {}
	var loose := unpaved_share(map, path)
	if kind == "offroad" and loose < UNPAVED_OFFROAD:
		return {}
	if kind != "offroad" and loose >= UNPAVED_OFFROAD:
		return {} # mostly loose: that is an off-road race
	var ev := _make(kind, path, checkpoints(path, CP_SPACING), "%s ▸ %s" % [_street(start), _street(goal)])
	if ev.is_empty():
		return ev
	if kind == "knockout":
		ev.knockout = true
		ev.sectors = true
		ev.laps = int(ev.rivals) # N rivals: N sector lines, the final sector between the last two
		ev.lap_length = float(ev.length) / float(ev.laps)
	return ev

## A drag: from a standstill DRAG_LENGTHS m along a straight main road wide enough for four abreast (either way
## along the road from the start).
func _make_drag(start: Dictionary) -> Dictionary:
	var want: float = DRAG_LENGTHS[rng.randi() % DRAG_LENGTHS.size()]
	var flip := rng.randf() < 0.5
	for way in 2:
		var dir: Vector2 = start.dir if (way == 0) != flip else -(start.dir as Vector2)
		var end := map.nearest_road((start.pos as Vector2) + dir * (want + 60.0), 40.0, 6)
		if end.is_empty() or not map.in_play(end.pos):
			continue
		var full := map.route(start.pos, end.pos)
		if path_length(full) < want + 20.0:
			continue
		var path := trim(full, want)
		if (start.pos as Vector2).distance_to(path[path.size() - 1]) < want * 0.97 or turning(path) > DRAG_TURN:
			continue
		var wide := true
		var narrow := INF
		for h in (route_profile(map, path, 20.0).half as PackedFloat32Array):
			narrow = minf(narrow, h)
			if h < DRAG_HALF:
				wide = false
				break
		if wide:
			var ev := _make("drag", path, PackedVector2Array([path[path.size() - 1]]), _street(start))
			# three abreast where four would hang over the kerbs (StreetRivals.drag_rivals_fit)
			if not ev.is_empty():
				ev.rivals = mini(int(ev.rivals), StreetRivals.drag_rivals_fit(narrow))
			return ev
	return {}

## A drift: 500..1100 m along the road it starts on, properly twisty.
func _make_drift(start: Dictionary) -> Dictionary:
	var want := rng.randf_range(500.0, 1100.0)
	var dir: Vector2 = start.dir if rng.randf() < 0.5 else -(start.dir as Vector2)
	var end := map.nearest_road((start.pos as Vector2) + dir * want, 80.0, 1)
	if end.is_empty() or not map.in_play(end.pos):
		return {}
	var path := map.route(start.pos, end.pos)
	var length := path_length(path)
	if length < 0.7 * want or length > 1.6 * want:
		return {}
	if turning(path) / (length / 1000.0) < 2.2:
		return {}
	return _make("drift", path, PackedVector2Array([path[path.size() - 1]]), _street(start))

## A rally: one special stage of 1.5..4 km on loose or twisty roads.
func _make_rally(start: Dictionary) -> Dictionary:
	var a := rng.randf() * TAU
	var goal := map.nearest_road((start.pos as Vector2) + Vector2(cos(a), sin(a)) * rng.randf_range(1300.0, 2800.0), 150.0, 1)
	if goal.is_empty() or not map.in_play(goal.pos):
		return {}
	var path := map.route(start.pos, goal.pos)
	var length := path_length(path)
	if length < 1500.0 or length > 4000.0 or length > 2.3 * (start.pos as Vector2).distance_to(goal.pos):
		return {}
	if unpaved_share(map, path) < UNPAVED_RALLY and turning(path) / (length / 1000.0) < RALLY_TWIST:
		return {}
	var name := _street(start)
	var ev := _make("rally", path, checkpoints(path, CP_SPACING), name)
	if not ev.is_empty():
		ev.stages = [{"name": name, "path": path, "length": float(ev.length), "cps": ev.cps}]
	return ev

## The event in the shape MapMissions.event gives a campaign mission (kind: how the run goes; mkind: the mission
## kind), plus the board's own keys (id, expires, color, base_difficulty).
func _make(mkind: String, path: PackedVector2Array, cps: PackedVector2Array, title: String) -> Dictionary:
	if not on_roads(map, path):
		return {}
	if turning(trim(path, START_STRAIGHT)) > START_TURN:
		return {} # the route doubles back (or zig-zags round a corner) right off the line: no grid fits there
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
	var kind := "race"
	if mkind == "drift":
		kind = "drift_zone"
	elif mkind == "rally":
		kind = "rally"
	var rv: Vector2i = RIVALS[mkind]
	var diff: String = Campaign.LEVELS[_pick_difficulty()]
	return {"id": "live_%d" % _serial, "kind": kind, "mkind": mkind, "title": title, "pos": path[0], "heading": h,
		"path": path, "length": path_length(path), "cps": cps, "cp_z": cp_z, "goal": cps[cps.size() - 1],
		"rivals": rng.randi_range(rv.x, rv.y), "grid": "drag" if mkind == "drag" else "", "knockout": false,
		"lap_length": 0.0, "laps": 1, "target": int(TARGETS[mkind]), "base_difficulty": diff, "difficulty": diff,
		"expires": clock_h + rng.randf_range(LIFE_H.x, LIFE_H.y), "color": COLORS[mkind]}

func _pick_difficulty() -> int:
	var r := rng.randf()
	for i in DIFFICULTY_WEIGHTS.size():
		r -= DIFFICULTY_WEIGHTS[i]
		if r <= 0.0:
			return i
	return 1

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

## Share of a route (every 25 m) on gravel or dirt, or off the map's roads.
static func unpaved_share(town: TownMap, path: PackedVector2Array) -> float:
	var pts := resample(path, 25.0)
	var n := 0
	for p in pts:
		var hit := town.road_at(p.x, p.y, -INF, 2.0)
		if hit.is_empty() or int(hit.surface) == 2:
			n += 1
	return float(n) / maxf(pts.size(), 1)

# ------------------------------------------------------------------------------------------ difficulty, targets

## A live event's field eased after missed tries of its kind, as a mission's is (Missions.as_stage): every
## Campaign.FAILS_PER_EASE misses drop it a level, down to easy. Sets difficulty, eased, fails on the event.
func ease_field(ev: Dictionary) -> void:
	if ev.has("mission"):
		return
	var mk := String(ev.get("mkind", ""))
	var base := String(ev.get("base_difficulty", ev.get("difficulty", "medium")))
	var at := maxi(Campaign.LEVELS.find(base), 0)
	var all = stats.get("fails", {})
	var f := int((all as Dictionary).get(mk, 0)) if all is Dictionary else 0
	var eased := mini(f / Campaign.FAILS_PER_EASE, at) if Missions.eases(mk) else 0
	ev["difficulty"] = Campaign.LEVELS[at - eased]
	ev["eased"] = eased
	ev["fails"] = f

## A drift's point tiers [bronze, silver, gold] (a mission's own, or per km); [] for a race.
func tiers_for(ev: Dictionary, _car_key := "stock") -> Array:
	if ev.has("mission_tiers"):
		return ev.mission_tiers
	if String(ev.kind) == "drift_zone":
		var km := float(ev.length) / 1000.0
		return [DRIFT_PER_KM[0] * km, DRIFT_PER_KM[1] * km, DRIFT_PER_KM[2] * km]
	return []

## What the event asks for: as Missions.target_text words a mission's.
func target_text(ev: Dictionary, car_key := "stock") -> String:
	var target := int(ev.get("target", 3))
	match String(ev.get("mkind", "")):
		"drift":
			var t := tiers_for(ev, car_key)
			return "Score %s for bronze (silver %s, gold %s)" % [OpenWorldHud._thousands(int(t[0])),
				OpenWorldHud._thousands(int(t[1])), OpenWorldHud._thousands(int(t[2]))]
		"knockout":
			return "Win the knockout" if target == 1 else "Survive to the final (top %d)" % target
		"rally":
			return "Top %d overall" % target
	return "Win" if target == 1 else "Finish P%d or better" % target

## Fans a result pays: FANS_PER_KM over the route (at least 1.5 km's worth, at most 5) times the field's difficulty,
## a quarter more for each place better than the target (as FanLevels.stage_reward), a share for a miss, a quarter
## for an event cleared before.
static func reward(ev: Dictionary, pos: int, success: bool, first_clear: bool) -> int:
	var base := FANS_PER_KM * clampf(float(ev.get("length", 0.0)) / 1000.0, 1.5, 5.0) * float(DIFF_FANS.get(String(ev.get("difficulty", "medium")), 1.0))
	if not success:
		return int(base * FanLevels.FAIL_SHARE / 10.0) * 10
	var beat := clampf(float(int(ev.get("target", 3)) - pos), 0.0, 3.0)
	var pay := base * (1.0 + 0.25 * beat)
	return int((pay if first_clear else pay * FanLevels.REPEAT_SHARE) / 10.0) * 10

## A finished (or failed) live run settled: the outcome as MapMissions.outcome reads it, the medal (P1 gold, P2
## silver, P3 bronze within the target; a drift's own tier), the fans; the event keeps its best for the beacon and the
## card. Nothing here touches the campaign.
func settle(res: Dictionary) -> Dictionary:
	var ev: Dictionary = res.get("ev", {})
	var out := MapMissions.outcome(res)
	var success := bool(out.success)
	var pos := int(out.pos)
	var tier := clampi(4 - pos, 1, 3) if success else 0
	var first := success and int(ev.get("best_tier", 0)) == 0
	if success:
		ev["best_tier"] = maxi(int(ev.get("best_tier", 0)), tier)
	if String(ev.get("mkind", "")) == "drift":
		ev["best"] = maxf(float(ev.get("best", 0.0)), float(res.get("score", 0.0)))
	elif pos < 999:
		ev["best_pos"] = mini(int(ev.get("best_pos", 999)), pos)
	return {"success": success, "tier": tier, "pos": pos, "fans": reward(ev, pos, success, first), "first_clear": first,
		"line": String(out.line)}

## A new campaign: the events on the board forget their medals (best tier, place and score).
func forget_medals() -> void:
	for ev in board:
		for k in ["best_tier", "best_pos", "best"]:
			ev.erase(k)

## Whether a route keeps to the drawn roads (every 10 m within OFF_ROADS_MAX of a road's edge). The road graph's
## routes can cut a rounded corner or follow a way that is not drawn; an event there would put its line, its gates
## and its drift's verge off the tarmac, so generate() tries another.
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

## The car's own standing-start time over `dist` m (DRAG_TIMES, a power law between and beyond the two marks),
## scaled by the pace model's grip factor (`pace_time` on a straight of `dist` m at `grip_k` vs dry tarmac).
static func drag_time(car_key: String, dist: float, grip_k := 1.0) -> float:
	var dt: Array = DRAG_TIMES.get(car_key, DRAG_TIMES.stock)
	var k := log(float(dt[1]) / float(dt[0])) / log(1000.0 / 402.0)
	var base := float(dt[0]) * pow(maxf(dist, 1.0) / 402.0, k)
	if grip_k >= 0.9999:
		return base
	var straight := PackedVector2Array([Vector2.ZERO, Vector2(maxf(dist, 10.0), 0.0)])
	var t_dry := pace_time(straight, car_key, 0.0, 1.0)
	var t_wet := pace_time(straight, car_key, 0.0, grip_k)
	return base * (t_wet / maxf(t_dry, 0.01))

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

## Starts an event (a live one or a campaign mission from MapMissions.event): the field on the grid, the countdown.
## Targets, drag calibration, rally crew times and time-outs are fixed to the weather grip (`ev.mu`) at the start;
## weather changes mid-run do not re-scale them.
func begin(ev: Dictionary, car_key: String) -> void:
	ease_field(ev)
	var start_mu := clampf(float(ev.get("mu", 1.0)), 0.1, 1.0)
	run = {"ev": ev, "state": "countdown", "t": -COUNTDOWN, "cp": 0, "car": car_key, "mu": start_mu,
		"tiers": tiers_for(ev, car_key), "drift": DriftScore.new() if ev.kind == "drift_zone" else null, "cps": ev.cps,
		"rivals": null, "stage": 0, "stage_times": [], "rally": [], "notice": "", "wrong_t": 0.0, "off_t": 0.0,
		"lost_t": 0.0, "resets": 0}
	var seed_value := rng.randi()
	if ev.kind == "race" and int(ev.get("rivals", 0)) > 0:
		var ro := {"grid": String(ev.get("grid", "")), "knockout": bool(ev.get("knockout", false)),
			"lap_length": float(ev.get("lap_length", 0.0)), "difficulty": String(ev.get("difficulty", "medium")),
			"profile": _weather_profile(profile(ev, StreetRivals.STEP), start_mu)}
		if String(ev.get("grid", "")) == "drag":
			ro["drag_time"] = drag_time(car_key, float(ev.length), grip_of(ev) * start_mu)
		ro["beyond"] = beyond(ev)
		if ro.beyond.size() >= 2:
			ro["beyond_profile"] = _weather_profile(route_profile(map, ro.beyond, StreetRivals.STEP), start_mu)
		run.rivals = StreetRivals.new(ev.path, car_key, int(ev.rivals), seed_value, ro)
	elif ev.kind == "rally":
		var grips := []
		for st in ev.stages:
			if not st.has("grip"):
				st["grip"] = grip_of({"path": st.path})
			grips.append(float(st.grip) * start_mu) # a mission's or free roam's start weather
		run.rally = MapMissions.rally_times(ev, car_key, seed_value, grips)
	if ev.kind == "rally":
		_arm(ev.stages[0].path, ev.stages[0].cps)
	else:
		_arm(ev.path, ev.cps)
	last_begin = {"ev": ev, "car": car_key}
	last_result = {}

## A route profile with its grip scaled by the weather's (a mission's mu): the cached profile is left as it is.
static func _weather_profile(prof: Dictionary, mu: float) -> Dictionary:
	if is_equal_approx(mu, 1.0) or not prof.has("grip"):
		return prof
	var out := prof.duplicate()
	var g: PackedFloat32Array = (prof.grip as PackedFloat32Array).duplicate()
	for i in g.size():
		g[i] *= mu
	out["grip"] = g
	return out

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

## The road on past an event's finish (cached on the event), StreetRivals.RUNOUT_MAX m of it from the finish: a lap
## carries on round from its start, a route along the map's roads straight on from its end (none where the road
## ends or turns back there). The field rolls on along it and parks instead of running off through a junction.
func beyond(ev: Dictionary) -> PackedVector2Array:
	if ev.has("_beyond"):
		return ev._beyond
	var path: PackedVector2Array = ev.path
	var out := PackedVector2Array()
	if path.size() >= 2:
		var end := path[path.size() - 1]
		var d := (end - path[maxi(path.size() - 4, 0)]).normalized()
		if end.distance_to(path[0]) < 15.0: # a lap: round again from the line
			out = trim(path, StreetRivals.RUNOUT_MAX)
			out[0] = end
		elif map != null:
			var r := map.route(end, end + d * (StreetRivals.RUNOUT_MAX + 30.0))
			if r.size() >= 2 and path_length(r) > 10.0 and (r[mini(2, r.size() - 1)] - r[0]).normalized().dot(d) > 0.3:
				out = trim(r, StreetRivals.RUNOUT_MAX)
				out[0] = end
		# only as far as it stays on the drawn roads (the router's last hop to a point off them does not)
		var on := 0.0
		for q in resample(out, 2.0):
			if map != null and map.road_at(q.x, q.y, -INF, 0.3).is_empty():
				break
			on += 2.0
		out = trim(out, on - 2.0) if on >= 10.0 else PackedVector2Array()
	ev["_beyond"] = out
	return out

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
	if z_ok and (p.distance_to(cps[cp]) < CHECK_RADIUS or crossed(run.gates[cp], prev, p, run.notice == "missed")):
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
		last_result = {"ev": ev, "success": false, "tier": 0, "score": 0.0, "line": "Out of time", "failed": true}
		if ev.kind in ["race", "rally"]:
			last_result.merge({"pos": 999, "finished": false, "knocked": false, "time": null})
		run = {}
		return "fail"
	return said

## The car's progress along the route and the notices it earns: a checkpoint run past (missed), going backwards
## at speed (wrong way), far off the route for a while (off route). Returns "warn" when a new notice comes up.
func _follow(dt: float, p: Vector2, v: float) -> String:
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
	var mu := float(run.get("mu", 1.0))
	match String(run.ev.kind):
		"rally":
			var st: Dictionary = run.ev.stages[int(run.stage)]
			return pace_time(st.path, String(run.car), 0.0, float(st.get("grip", 1.0)) * mu) * 2.5 + 30.0
		"drift_zone":
			return pace_time(run.ev.path, String(run.car), 0.0, grip_of(run.ev) * mu) * 3.0 * TIME_OUT
	return pace_time(run.ev.path, String(run.car), 0.0, grip_of(run.ev) * mu) * 2.5 + 30.0

## A drift over: its score against the tiers.
func _finish() -> void:
	var ev: Dictionary = run.ev
	var tiers: Array = run.tiers
	var t := float(run.t)
	var d := run.drift as DriftScore
	var score := 0.0
	if d:
		d.bank(t)
		score = d.score
	var tier := _tier_high(score, tiers) if tiers.size() >= 3 else 0
	last_result = {"ev": ev, "success": tier > 0, "tier": tier, "score": score,
		"line": "%s drift points" % OpenWorldHud._thousands(int(score)), "next": _next_text(score, tier, tiers), "time": t}
	run = {}

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
	last_result = {"ev": ev, "success": pos <= int(ev.get("target", 3)), "tier": 0, "score": 0.0, "line": line,
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
	last_result = {"ev": ev, "success": pos <= int(ev.get("target", 3)), "tier": 0, "score": 0.0,
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

static func _next_text(score: float, tier: int, tiers: Array) -> String:
	if tier >= 3 or tiers.size() < 3:
		return ""
	return "%s points short of %s" % [OpenWorldHud._thousands(int(float(tiers[tier]) - score)), TIER_NAMES[tier + 1].to_lower()]

# ------------------------------------------------------------------------------------------ text

static func clock_text(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]

## The stars line of a drift: "★ 540  ★★ 2,160  ★★★ 5,400".
static func stars_text(tiers: Array) -> String:
	var parts := PackedStringArray()
	for k in 3:
		parts.append("%s %s" % ["★".repeat(k + 1), OpenWorldHud._thousands(int(tiers[k]))])
	return "  ".join(parts)

## The mission kind's name ("DRAG RACE") of an event.
static func kind_name(ev: Dictionary) -> String:
	return String(KIND_NAMES.get(String(ev.get("mkind", ev.get("kind", ""))), "EVENT"))

const BLURB := {
	"sprint": "Somebody chalked a start line on the road. Point to point through the town against the local crews, every checkpoint gate in order, the roads closed while it runs.",
	"drag": "A straight bit of main road, four cars abreast and somebody's cousin with a torch for the lights. Nothing to it but the launch and the gears.",
	"knockout": "A run across town cut into sectors: each time the leader crosses a sector line the last car is out. Never be last at a line.",
	"offroad": "The lads with the mud tyres found a way across on the gravel and the field tracks. Wheel to wheel on the loose stuff.",
	"drift": "The lads are filming this bit. Come in sideways and keep it there to the end; a crash or the verge loses the combo.",
	"rally": "A special stage on the back roads, one car at a time against the clock; the crews' times are already on the board.",
}

## The length as Missions.length_text words a mission's.
static func length_text(ev: Dictionary) -> String:
	var km := float(ev.length) / 1000.0
	match String(ev.get("mkind", "")):
		"drag":
			return "%d m standing start" % int(round(float(ev.length)))
		"drift":
			return "%.1f km solo" % km
		"knockout":
			return "%.1f km, %d sectors, one car out per sector" % [km, int(ev.laps)]
		"rally":
			return "one %.1f km special stage" % km
	return "%.1f km point to point" % km

func surface_text(ev: Dictionary) -> String:
	if not ev.has("_loose"):
		ev["_loose"] = unpaved_share(map, ev.path) if map else 0.0
	var share := float(ev._loose)
	return "Tarmac" if share < 0.1 else ("Mostly gravel and dirt" if share >= 0.5 else "Tarmac and gravel")

static func field_text(ev: Dictionary) -> String:
	var n := int(ev.get("rivals", 0))
	var field := "solo" if n == 0 else "%d %s (%s)" % [n, "crews" if String(ev.get("mkind", "")) == "rally" else "rivals",
		String(ev.get("difficulty", "medium")).capitalize()]
	if int(ev.get("eased", 0)) > 0:
		field += ", eased after %d tries" % int(ev.get("fails", 0))
	return field

## The briefing card, laid out as a campaign mission's (Missions.card): [subtitle, title, body, hint].
func card(ev: Dictionary, car_key: String, fans_level := 0) -> Array:
	ease_field(ev)
	var mins := int(maxf(0.0, float(ev.expires) - clock_h) * 80.0 / 60.0)
	var best := ""
	if String(ev.get("mkind", "")) == "drift" and float(ev.get("best", 0.0)) > 0.0:
		best = " · Best %s" % OpenWorldHud._thousands(int(ev.best))
	elif int(ev.get("best_pos", 999)) < 999:
		best = " · Best P%d" % int(ev.best_pos)
	if int(ev.get("best_tier", 0)) > 0:
		best += " %s" % "★".repeat(int(ev.best_tier))
	var body := "%s\n\n%s · %s · %s · live for about %d more min\nTarget: %s%s\nTargets fixed to start weather · up to %s fans on a first clear (fan level %d)" % [
		BLURB.get(String(ev.get("mkind", "")), ""), length_text(ev), surface_text(ev), field_text(ev), maxi(mins, 1),
		target_text(ev, car_key), best, OpenWorldHud._thousands(reward(ev, 1, true, true)), fans_level]
	return ["LIVE %s MISSION" % kind_name(ev), String(ev.title), body, "ENTER / B  ▸  START EVENT HERE ON THE MAP"]

const NOTICES := {"missed": "MISSED CHECKPOINT · turn back, or R to reset", "wrong_way": "WRONG WAY",
	"off_route": "OFF ROUTE · follow the GPS, or R to reset"}

## The HUD's two lines while running: [title, line]. A notice (missed checkpoint, wrong way, off route) takes the
## second line.
func hud_lines(p: Vector2) -> Array:
	if not is_running():
		return ["", ""]
	var ev: Dictionary = run.ev
	var name := kind_name(ev)
	if run.state == "liaison":
		var st: Dictionary = ev.stages[int(run.stage)]
		return ["LIAISON · P%d" % rally_place(), "to SS%d %s · %d m · stop on the line" % [int(run.stage) + 1, st.name,
			int(p.distance_to(next_target()))]]
	if run.state == "countdown":
		return ["%d" % ceili(-float(run.t)), name] # the count in the big line
	var t := float(run.t)
	var cps: PackedVector2Array = run.cps
	var pr := progress()
	var dist := "%.1f / %.1f km" % [pr.x / 1000.0, pr.y / 1000.0] if pr.y >= 1500.0 else "%d m to go" % maxi(int(pr.y - pr.x), 0)
	var title := "%s  %s" % [name, clock_text(t)]
	var line := dist
	match String(ev.kind):
		"race":
			var rv := run.rivals as StreetRivals
			var gap := rv.gap_text() if rv else ""
			title = "%s  P%d/%d  %s" % [name, rv.position() if rv else 1, rv.field() if rv else 1, clock_text(t)]
			line = "CP %d/%d · %s" % [mini(int(run.cp) + 1, cps.size()), cps.size(), dist] if cps.size() > 1 else dist
			if rv and bool(ev.get("knockout", false)):
				line = "%s %d/%d · %d cars left · %s" % ["SECTOR" if ev.get("sectors", false) else "LAP",
					mini(rv.player_lap() + 1, int(ev.laps)), int(ev.laps), rv.field(), dist]
			if gap != "":
				line += " · %s" % gap
		"rally":
			var st: Dictionary = ev.stages[int(run.stage)]
			title = "SS%d %s  %s" % [int(run.stage) + 1, String(st.name).to_upper(), clock_text(t)]
			line = "CP %d/%d · %s · P%d overall so far" % [int(run.cp) + 1, cps.size(), dist, rally_place()]
		"drift_zone":
			var d := run.drift as DriftScore
			var tiers: Array = run.tiers
			title = "%s  %s  ×%.1f  %s" % [name, OpenWorldHud._thousands(d.total()), d.mult, "★".repeat(_tier_high(d.total(), tiers))]
			line = "%s · %s" % [stars_text(tiers), dist]
	if String(run.notice) != "":
		line = String(NOTICES.get(run.notice, ""))
	return [title, line]

## Where the GPS should point while running: the next checkpoint (or the next stage's start).
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

## The path's first `dist` m (cut inside its last segment).
static func trim(path: PackedVector2Array, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.is_empty():
		return out
	out.append(path[0])
	var s := 0.0
	for i in range(1, path.size()):
		var l := path[i - 1].distance_to(path[i])
		if s + l >= dist:
			out.append(path[i - 1].lerp(path[i], (dist - s) / maxf(l, 1e-6)))
			return out
		s += l
		out.append(path[i])
	return out

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
