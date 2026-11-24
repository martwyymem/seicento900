## The field of a drag race on the open-world map (LiveEvents, MapMissions' drag missions): every car abreast on one
## line, each in its own lane for good, down a straight. Each rival's launch is calibrated to the driven car's own
## measured standing-start times (LiveEvents.drag_time) by the event's level (DRAG_BANDS): nothing in a drag for the
## race AI to do, so the drags keep this kinematic field while every other race on the map runs the race sim's bots
## (EventField). Its line is the route moved onto the road's centre (the `profile` LiveEvents.route_profile measures);
## past the finish the cars roll on and park. Scene-free: OpenWorld draws them and pushes them with a two-car circle.
class_name StreetRivals
extends RefCounted

const STEP := 5.0 ## m between profile samples
const PACE_RANGE := Vector2(0.84, 0.95) ## a rival's top speed and grip against the reference driver before the launch is calibrated
const PACE_BANDS := {"easy": Vector2(0.80, 0.91), "medium": Vector2(0.84, 0.95), "hard": Vector2(0.89, 0.99)}
## A drag field: each rival's time over the distance against the car's own measured standing start (drag_time),
## slowest .. fastest. Easy is won by any clean launch, hard needs a near-perfect one.
const DRAG_BANDS := {"easy": Vector2(1.12, 1.04), "medium": Vector2(1.08, 1.02), "hard": Vector2(1.05, 1.005)}
const MAX_RIVALS := 9
const CAR_L := 4.4 ## m nose to tail with a little room: closer than this along the road is side by side
const CAR_W := 1.9 ## m across with a little room: closer than this across is the same line
const EDGE := 0.85 ## m a rival's centre keeps from the road's edge
const LAT_RATE := 1.4 ## m/s a rival moves across the road
const DRAG_PLAYER_LAT := -1.8
const RUNOUT_MAX := 60.0 ## m a car home rolls on past the finish at most (LiveEvents.beyond is this long)
const DRAG_LAUNCH := 1.1 ## a drag rival launches hard: acceleration factor (no waiting for the lights, no wheelspin lost)
const DRAG_LATS := [1.8, -5.4, 5.4, -9.0, 9.0, -12.6, 12.6, -16.2, 16.2] ## the rivals' own lanes on a drag grid (the player has -1.8)

var pts := PackedVector2Array()
var cum := PackedFloat32Array()
var tan := PackedVector2Array() ## smoothed direction at each point (the pose turns through a bend, no snap at a vertex)
var centre := PackedFloat32Array() ## the road's centre across the route at each point (m, left of the direction +)
var half := PackedFloat32Array() ## the road's half width at each point
var grip := PackedFloat32Array() ## the surface's grip against town tarmac at each point (1 tarmac, ~0.7 dirt)
var length := 0.0
var rivals: Array = [] ## {s, v, lat, lane, f, env: PackedFloat32Array, vmax, acc, t_done (-1 racing), out, park, gone}
var t := 0.0
var player_s := 0.0
var player_lat := 0.0 ## the player's offset from the road's centre (as a rival's lat)
var drag_lane := 3.6 ## m between two cars on a drag grid
var runout := 0.0 ## m of road on past the finish (opts.beyond) a car home parks in
var drag := true ## every car on one line at s = 0, each in its own lane for good (always: the only field this is)
var player_out := false ## (a drag knocks nobody out; LiveEvents reads it of any field)
var player_out_pos := 0

## opts: difficulty
## ("easy" / "medium" / "hard": the pace band), profile (LiveEvents.route_profile of the path at STEP: the road's
## centre, half width and grip; without it the polyline is the road's centre, 4 m either side, tarmac), drag_time
## (s: the car's own standing-start time over the route, which a drag field is calibrated against), beyond (the
## road on past the finish, from the finish: a car home rolls along it and parks inside it; LiveEvents.beyond).
func _init(path: PackedVector2Array, car_key: String, count: int, seed_value: int, opts := {}) -> void:
	pts = LiveEvents.resample(path, STEP)
	var n_route := pts.size()
	var more: PackedVector2Array = opts.get("beyond", PackedVector2Array())
	if n_route > 0 and more.size() >= 2:
		var ext := LiveEvents.resample(more, STEP)
		for i in range(1, ext.size()):
			pts.append(ext[i])
	var n_pts := pts.size()
	cum.resize(n_pts)
	for i in range(1, n_pts):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	length = cum[n_route - 1] if n_route > 0 else 0.0
	# (without opts.beyond nothing is known past the finish: straight on, as far as it takes)
	runout = minf(cum[n_pts - 1] - length, RUNOUT_MAX) if opts.has("beyond") else RUNOUT_MAX
	tan.resize(n_pts)
	for i in n_pts:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n_pts - 1)]
		tan[i] = (b - a).normalized() if a.distance_to(b) > 1e-4 else Vector2.RIGHT
	var prof: Dictionary = opts.get("profile", {})
	centre = prof.get("centre", PackedFloat32Array()) as PackedFloat32Array
	half = prof.get("half", PackedFloat32Array()) as PackedFloat32Array
	grip = prof.get("grip", PackedFloat32Array()) as PackedFloat32Array
	if centre.size() != n_route:
		centre = PackedFloat32Array()
		centre.resize(n_route)
	if half.size() != n_route:
		half = PackedFloat32Array()
		half.resize(n_route)
		half.fill(4.0)
	if grip.size() != n_route:
		grip = PackedFloat32Array()
		grip.resize(n_route)
		grip.fill(1.0)
	# past the finish: the road's own centre and width from opts.beyond_profile (LiveEvents.route_profile of beyond
	# at STEP), else as at the finish
	var bp: Dictionary = opts.get("beyond_profile", {})
	var bh: PackedFloat32Array = bp.get("half", PackedFloat32Array())
	var bc: PackedFloat32Array = bp.get("centre", PackedFloat32Array())
	var h_end := half[n_route - 1] if n_route > 0 else 4.0
	var g_end := grip[n_route - 1] if n_route > 0 else 1.0
	centre = centre.duplicate()
	half = half.duplicate()
	grip = grip.duplicate()
	for i in range(n_route, n_pts):
		var j := i - n_route + 1
		centre.append(bc[j] if j < bc.size() else 0.0)
		half.append(bh[j] if j < bh.size() else h_end)
		grip.append(g_end)
	var diff := String(opts.get("difficulty", "medium"))
	# the player's rival step moves the field off the event's own level (DifficultyProfile.band), never past the
	# reference driver
	var shift := float(opts.get("difficulty_shift", 0.0))
	var band: Vector2 = PACE_BANDS.get(diff, PACE_RANGE)
	if shift != 0.0:
		band = DifficultyProfile.band(PACE_BANDS, diff if PACE_BANDS.has(diff) else "medium", shift)
		band = Vector2(minf(band.x, 0.98), minf(band.y, 1.0))
	var pc: Array = LiveEvents.PACE.get(car_key, LiveEvents.PACE.stock)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := clampi(count, 0, MAX_RIVALS)
	# a drag grid: everyone abreast, as wide apart as the narrowest of the run allows (a two-lane carriageway takes
	# four), the outer cars' centres EDGE in from the tarmac's edge so no body hangs over a kerb (2026-11-21 QA: a
	# 2 m floor put the outer pair of four on a 6.2 m street half over the pavement); drag_rivals_fit is the field
	var road_w := 2.0 * drag_half(half, n_route)
	drag_lane = clampf((road_w - 2.0 * EDGE) / maxf(n, 1), CAR_W, 3.6)
	var dlats := []
	for k in n + 1:
		dlats.append((float(k) - float(n) * 0.5) * drag_lane)
	for k in n:
		var f := lerpf(band.y, band.x, float(k) / maxf(n - 1, 1)) + rng.randf_range(-0.012, 0.012)
		var g := Vector2(0.0, float(dlats[k + 1 if k >= 1 else 0]))
		var lane: float = g.y
		var r := {"s": g.x, "v": 0.0, "lat": g.y, "lane": lane, "f": f, "vmax": float(pc[0]) * f,
			"acc": float(pc[1]) * f, "env": _envelope(float(pc[0]) * f, float(pc[2]) * f * f, float(pc[3]) * f), "t_done": -1.0, "out": false}
		rivals.append(r)
	# names and numbers from the circuit races' field (Drivers.ROSTER), a run of them picked by the seed (no rng drawn,
	# so the field's pace is as before)
	var at := absi(seed_value) % Drivers.ROSTER.size()
	for k in n:
		var who: Dictionary = Drivers.ROSTER[(at + k) % Drivers.ROSTER.size()]
		rivals[k].name = String(who.name)
		rivals[k].number = int(who.number)
	if true:
		_player_lat0 = float(dlats[1]) if n >= 1 else 0.0
		var dt_ref := float(opts.get("drag_time", 0.0))
		if dt_ref > 0.0:
			var db: Vector2 = DRAG_BANDS.get(diff, DRAG_BANDS.medium)
			if shift != 0.0:
				db = DifficultyProfile.band(DRAG_BANDS, diff if DRAG_BANDS.has(diff) else "medium", shift)
				db = Vector2(maxf(db.x, 1.01), maxf(db.y, 1.0))
			for k in n:
				var want := dt_ref * (lerpf(db.y, db.x, float(k) / maxf(n - 1, 1)) + rng.randf_range(-0.004, 0.004))
				_calibrate_drag(rivals[k], want)
				var rk: Dictionary = rivals[k]
				rk.env = _envelope(float(rk.vmax), float(pc[2]) * float(rk.f) * float(rk.f), float(pc[3]) * float(rk.f))

var _player_lat0 := DRAG_PLAYER_LAT

## The narrowest half width of a drag's run (the route's first n points; 4 m without a profile).
static func drag_half(halves: PackedFloat32Array, n: int) -> float:
	if halves.is_empty() or n <= 0:
		return 4.0
	var lo := INF
	for i in mini(n, halves.size()):
		lo = minf(lo, halves[i])
	return lo

## How many rivals fit abreast of the player on a drag road `half` m either side of its centre: CAR_W apart, the outer
## centres EDGE in from the edges.
static func drag_rivals_fit(half_w: float) -> int:
	return maxi(1, int(floorf((2.0 * half_w - 2.0 * EDGE) / CAR_W + 0.001)))

## Where the player should be put at the start, (along, across from the road's centre): in its own lane.
func player_grid() -> Vector2:
	return Vector2(0.0, _player_lat0)

## A drag rival's acceleration (and with it its top speed) scaled so that it covers the route in `want` s
## (bisection on a 20 Hz run of the same motion as step()).
func _calibrate_drag(r: Dictionary, want: float) -> void:
	var lo := 0.2
	var hi := 4.0
	for it in 24:
		var mid := 0.5 * (lo + hi)
		if _drag_run(float(r.acc) * mid, float(r.vmax) * maxf(1.0, mid)) > want:
			lo = mid
		else:
			hi = mid
	var k := 0.5 * (lo + hi)
	r.acc = float(r.acc) * k
	r.vmax = float(r.vmax) * maxf(1.0, k)

func _drag_run(acc: float, vmax: float) -> float:
	var s := 0.0
	var v := 0.0
	var tt := 0.0
	var dt := 0.05
	while s < length and tt < 600.0:
		v = minf(v + acc * DRAG_LAUNCH * maxf(0.08, 1.0 - v / vmax) * dt, vmax)
		s += v * dt
		tt += dt
	return tt

## An offset across the road kept inside it at distance s.
func _fit(s: float, lat: float) -> float:
	var lim := maxf(_at(half, s) - EDGE, 0.3)
	return clampf(lat, -lim, lim)

## A profile value at distance s (linear between the samples).
func _at(arr: PackedFloat32Array, s: float) -> float:
	if arr.is_empty():
		return 0.0
	if arr.size() < 2 or cum.size() < 2:
		return arr[0]
	var i := _index(clampf(s, 0.0, length))
	return lerpf(arr[i], arr[mini(i + 1, arr.size() - 1)], clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.01), 0.0, 1.0))

## A drag has no laps or sectors (LiveEvents reads it of any field).
func lap_of(_s: float) -> int:
	return 0

func player_lap() -> int:
	return 0

## True once the race is over for the player: knocked out, or home.
func player_done() -> bool:
	return player_out or (length > 0.0 and player_s >= length)

## Highest speed at each sample that still makes every corner ahead: grip-limited corner speed (on that stretch's
## surface), braked into.
func _envelope(vmax: float, lat: float, brk: float) -> PackedFloat32Array:
	var n := pts.size()
	var env := PackedFloat32Array()
	env.resize(n)
	for i in n:
		var a := pts[maxi(i - 3, 0)]
		var b := pts[i]
		var c := pts[mini(i + 3, n - 1)]
		var turn := absf(wrapf((c - b).angle() - (b - a).angle(), -PI, PI))
		var k := turn / maxf(a.distance_to(b) + b.distance_to(c), 1.0)
		env[i] = minf(vmax, sqrt(lat * grip[i] / maxf(k, 1e-5)))
	for i in range(n - 2, -1, -1):
		env[i] = minf(env[i], sqrt(env[i + 1] * env[i + 1] + 2.0 * brk * grip[i] * (cum[i + 1] - cum[i])))
	return env

## The sample segment s lies on (by the summed distances: the samples are STEP apart along the path, a little less
## as the crow flies through a bend, so s / STEP drifts over a long route).
func _index(s: float) -> int:
	return clampi(cum.bsearch(s, true) - 1, 0, maxi(pts.size() - 2, 0))

## [map position, direction] at distance s along the route and `lat` m across the road's centre there (left of the
## direction is +). The direction and the across turn smoothly through a bend; past the finish it follows the road
## on (opts.beyond); before the start and past that the route runs straight on.
func pose(s: float, lat: float) -> Array:
	if pts.size() < 2:
		return [pts[0] if pts.size() > 0 else Vector2.ZERO, Vector2.RIGHT]
	var last := cum[cum.size() - 1]
	if s < 0.0 or s > last:
		var at_end := s > last
		var d0: Vector2 = tan[tan.size() - 1] if at_end else tan[0]
		var base: Vector2 = pts[pts.size() - 1] if at_end else pts[0]
		var c0: float = centre[centre.size() - 1] if at_end else centre[0]
		var p0 := base + d0 * (s - last if at_end else s)
		return [p0 + Vector2(-d0.y, d0.x) * (lat + c0), d0]
	var i := _index(s)
	var u := clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.01), 0.0, 1.0)
	var d := tan[i].lerp(tan[i + 1], u).normalized()
	if d == Vector2.ZERO:
		d = (pts[i + 1] - pts[i]).normalized()
	var p := pts[i].lerp(pts[i + 1], u)
	return [p + Vector2(-d.y, d.x) * (lat + lerpf(centre[i], centre[i + 1], u)), d]

## Distance along the route nearest to p, searched near the last known one (or over the whole route when lost).
func project(p: Vector2, near_s: float) -> float:
	var lo := _index(near_s - 60.0)
	var hi := mini(_index(near_s + 160.0) + 1, pts.size() - 1)
	var best := INF
	var bs := near_s
	for pass_i in 2:
		for i in range(lo, hi):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := q.distance_squared_to(p)
			if d < best:
				best = d
				bs = cum[i] + pts[i].distance_to(q)
		if best < 1600.0:
			break
		lo = 0
		hi = pts.size() - 1
	return bs

## One step: the player at p doing pv m/s (its progress is followed for the positions and the band, and its car
## is in the rivals' way like any other).
func step(dt: float, p: Vector2, pv: float) -> void:
	if pts.size() < 2 or dt <= 0.0:
		return
	t += dt
	player_v = pv
	player_s = project(p, player_s)
	var ps: Array = pose(player_s, 0.0)
	var pd: Vector2 = ps[1]
	player_lat = (p - (ps[0] as Vector2)).dot(Vector2(-pd.y, pd.x))
	for k in rivals.size():
		var r: Dictionary = rivals[k]
		if bool(r.out):
			continue
		var s: float = r.s
		var v: float = r.v
		if float(r.t_done) >= 0.0:
			# home: it rolls on past the line, easing off towards its side of the road, and parks out of the way
			# inside the road there is straight on past the finish (harder on the brakes when that is short), the
			# cars home before it parked further on, two abreast
			var slot := int(r.get("park", 0))
			# (single file, each on its own side; with no room left past the line it turns off out of sight: gone,
			# which OpenWorld no longer draws)
			var stop := length + runout - 2.0 - float(slot) * (CAR_L + 0.6)
			if stop < length + 1.0:
				stop = length + 1.0
				r.gone = true
			var side := maxf(half[_index(stop)] - EDGE, 0.3)
			var room := maxf(stop - s, 0.5)
			v = move_toward(v, 0.0, maxf(3.5, v * v / (2.0 * room)) * dt)
			r.v = v
			r.s = minf(s + v * dt, maxf(stop, s))
			r.lat = move_toward(float(r.lat), side * (1.0 if slot % 2 == 0 else -1.0), LAT_RATE * 0.5 * dt)
			continue
		var env: PackedFloat32Array = r.env
		var i := _index(s)
		var cap := lerpf(env[i], env[i + 1], clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.01), 0.0, 1.0))
		var a := float(r.acc) * DRAG_LAUNCH * maxf(0.08, 1.0 - v / float(r.vmax))
		v = minf(v + a * dt, cap) if v < cap else move_toward(v, cap, 9.0 * dt)
		r.v = maxf(v, 0.0)
		r.s = s + float(r.v) * dt
		if float(r.s) >= length:
			r.t_done = t
			r.park = finished_count() - 1 # (counts itself)

## A knock from the player's car: pushed `across` m sideways and slowed by dv m/s.
func knock(k: int, across: float, dv: float) -> void:
	var r: Dictionary = rivals[k]
	r.lat = _fit(float(r.s), float(r.lat) + across)
	r.lane = r.lat
	r.v = maxf(0.0, float(r.v) - dv)

func finished_count() -> int:
	return rivals.filter(func(r): return float(r.t_done) >= 0.0).size()

## The player's place in the field right now (1 = leading): rivals home already or further along count ahead; rivals
## that are out don't count while the player runs (once out, it keeps the place it went out in).
func position() -> int:
	if player_out:
		return player_out_pos
	var ahead := 0
	for r in rivals:
		if bool(r.out):
			continue
		if float(r.t_done) >= 0.0 or float(r.s) > player_s:
			ahead += 1
	return ahead + 1

## The gap the HUD shows: to the car directly ahead ("GAP 1.4 s"), or leading, over the car behind ("LEAD 2.0 s"),
## in seconds at the player's speed (at least 8 m/s). "" with nobody else running.
func gap_text() -> String:
	if player_out:
		return ""
	var ahead := INF
	var behind := INF
	for r in rivals:
		if bool(r.out):
			continue
		var d := float(r.s) - player_s
		if float(r.t_done) >= 0.0:
			continue
		if d > 0.0:
			ahead = minf(ahead, d)
		else:
			behind = minf(behind, -d)
	var v := maxf(player_v, 8.0)
	if position() > 1:
		return "GAP %.1f s" % (ahead / v) if is_finite(ahead) else ""
	return "LEAD %.1f s" % (behind / v) if is_finite(behind) else ""

var player_v := 0.0

func field() -> int:
	if player_out:
		return rivals.size() + 1
	var n := 1
	for r in rivals:
		if not bool(r.out):
			n += 1
	return n

## The running order for the HUD's timing list, first to last: {name, number, player, gap ("" for the leader, "+1.4"
## seconds to the car ahead, a time once home), out, done}. The player sits where position() has it.
func standings() -> Array:
	var live_rows: Array = []
	for k in rivals.size():
		var r: Dictionary = rivals[k]
		if not bool(r.out):
			live_rows.append(k)
	live_rows.sort_custom(func(a, b):
		var ra: Dictionary = rivals[a]
		var rb: Dictionary = rivals[b]
		var da := float(ra.t_done) >= 0.0
		var db := float(rb.t_done) >= 0.0
		if da != db:
			return da
		if da:
			return float(ra.t_done) < float(rb.t_done)
		return float(ra.s) > float(rb.s))
	var rows: Array = []
	for k in live_rows:
		var r: Dictionary = rivals[k]
		rows.append({"name": String(r.get("name", "Rival %d" % (k + 1))), "number": int(r.get("number", 0)), "player": false,
			"s": float(r.s), "t_done": float(r.t_done), "out": false})
	var me := {"name": "YOU", "number": 0, "player": true, "s": player_s, "t_done": -1.0, "out": player_out}
	if not player_out:
		rows.insert(clampi(position() - 1, 0, rows.size()), me)
	var v := maxf(player_v, 8.0)
	for i in rows.size():
		var row: Dictionary = rows[i]
		row.done = float(row.t_done) >= 0.0
		if bool(row.done):
			row.gap = LiveEvents.clock_text(float(row.t_done))
		elif i == 0:
			row.gap = ""
		else:
			var ahead: Dictionary = rows[i - 1]
			var d := float(ahead.s) - float(row.s) if not bool(ahead.done) else maxf(length - float(row.s), 0.0)
			row.gap = "+%.1f" % maxf(d / v, 0.0)
	return rows

## The fastest rival time home so far, or -1.
func best_time() -> float:
	var b := -1.0
	for r in rivals:
		if float(r.t_done) >= 0.0 and (b < 0.0 or float(r.t_done) < b):
			b = float(r.t_done)
	return b
