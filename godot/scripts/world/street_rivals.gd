## Rivals of a race on the open-world map (LiveEvents, MapMissions): cars on a grid behind and beside the player,
## driving the event's route (no walls, no physics). Their line is the route polyline moved onto the road it runs
## along (the `profile` LiveEvents.route_profile measures: the road's centre and half width, its surface grip), each
## at a lateral offset kept inside the road. Each has a speed profile in the spirit of LiveEvents.pace_time (corner
## speeds from grip, acceleration falling off to the top speed, braking in time) scaled by its own pace factor from
## the event's difficulty band. They follow the car ahead and pull out to pass it (rivals and the player alike),
## coast on past the finish instead of stopping on the line, and rubber-band mildly. A drag field is calibrated to the
## car's own measured standing-start times (LiveEvents.drag_time). Scene-free: OpenWorld draws and collides them.
class_name StreetRivals
extends RefCounted

const STEP := 5.0 ## m between profile samples
const PACE_RANGE := Vector2(0.84, 0.95) ## medium: slowest .. fastest rival against the reference driver (gold is 1/1.04)
const PACE_BANDS := {"easy": Vector2(0.80, 0.91), "medium": Vector2(0.84, 0.95), "hard": Vector2(0.89, 0.99)}
## A drag field: each rival's time over the distance against the car's own measured standing start (drag_time),
## slowest .. fastest. Easy is won by any clean launch, hard needs a near-perfect one.
const DRAG_BANDS := {"easy": Vector2(1.12, 1.04), "medium": Vector2(1.08, 1.02), "hard": Vector2(1.05, 1.005)}
const BAND := 0.03 ## rubber band: at most this fraction faster / slower
const BAND_GAP := 150.0 ## m ahead of / behind the player where the band is fully on
const GRID := [Vector2(0.0, 2.6), Vector2(-7.0, -1.3), Vector2(-7.0, 1.3), Vector2(-14.0, -1.3), Vector2(-14.0, 1.3),
	Vector2(-21.0, -1.3), Vector2(-21.0, 1.3), Vector2(-28.0, -1.3), Vector2(-28.0, 1.3), Vector2(-35.0, -1.3)] ## (along, across) m from the player's spot: 2 abreast, rows 7 m apart
const LANES := [1.2, -1.2, 0.4, -0.4, 1.6, -1.6, 0.8, -0.8, 0.0] ## racing offsets across the road (m)
const MAX_RIVALS := 9
const CAR_L := 4.4 ## m nose to tail with a little room: closer than this along the road is side by side
const CAR_W := 1.9 ## m across with a little room: closer than this across is the same line
const EDGE := 0.85 ## m a rival's centre keeps from the road's edge
const HELD_MAX := 3.0 ## s held up behind a car before a rival noses past it regardless
const LAT_RATE := 1.4 ## m/s a rival moves across the road
const DRAG_PLAYER_LAT := -1.8
const DRAG_LAUNCH := 1.1 ## a drag rival launches hard: acceleration factor (no waiting for the lights, no wheelspin lost)
const DRAG_LATS := [1.8, -5.4, 5.4, -9.0, 9.0, -12.6, 12.6, -16.2, 16.2] ## the rivals' own lanes on a drag grid (the player has -1.8)

var pts := PackedVector2Array()
var cum := PackedFloat32Array()
var tan := PackedVector2Array() ## smoothed direction at each point (the pose turns through a bend, no snap at a vertex)
var centre := PackedFloat32Array() ## the road's centre across the route at each point (m, left of the direction +)
var half := PackedFloat32Array() ## the road's half width at each point
var grip := PackedFloat32Array() ## the surface's grip against town tarmac at each point (1 tarmac, ~0.7 dirt)
var length := 0.0
var rivals: Array = [] ## {s, v, lat, lane, f, env: PackedFloat32Array, vmax, acc, t_done (-1 racing), out}
var t := 0.0
var player_s := 0.0
var player_lat := 0.0 ## the player's offset from the road's centre (as a rival's lat)
var drag_lane := 3.6 ## m between two cars on a drag grid
var drag := false ## every car on one line at s = 0, each in its own lane for good
var knockout := false
var lap_length := 0.0
var player_out := false
var player_out_pos := 0 ## the player's place when knocked out (rivals still running + 1)
var out_order: Array = [] ## who went out, in order: the rival index, or -1 for the player
var _next_lap := 1 ## the next lap boundary (a multiple of lap_length) that knocks a car out

## opts: grid "drag" (one line, own lanes, see player_grid), knockout (bool) with lap_length (m), difficulty
## ("easy" / "medium" / "hard": the pace band), profile (LiveEvents.route_profile of the path at STEP: the road's
## centre, half width and grip; without it the polyline is the road's centre, 4 m either side, tarmac), drag_time
## (s: the car's own standing-start time over the route, which a drag field is calibrated against).
func _init(path: PackedVector2Array, car_key: String, count: int, seed_value: int, opts := {}) -> void:
	pts = LiveEvents.resample(path, STEP)
	var n_pts := pts.size()
	cum.resize(n_pts)
	for i in range(1, n_pts):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	length = cum[n_pts - 1] if n_pts > 0 else 0.0
	tan.resize(n_pts)
	for i in n_pts:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n_pts - 1)]
		tan[i] = (b - a).normalized() if a.distance_to(b) > 1e-4 else Vector2.RIGHT
	var prof: Dictionary = opts.get("profile", {})
	centre = prof.get("centre", PackedFloat32Array()) as PackedFloat32Array
	half = prof.get("half", PackedFloat32Array()) as PackedFloat32Array
	grip = prof.get("grip", PackedFloat32Array()) as PackedFloat32Array
	if centre.size() != n_pts:
		centre = PackedFloat32Array()
		centre.resize(n_pts)
	if half.size() != n_pts:
		half = PackedFloat32Array()
		half.resize(n_pts)
		half.fill(4.0)
	if grip.size() != n_pts:
		grip = PackedFloat32Array()
		grip.resize(n_pts)
		grip.fill(1.0)
	drag = String(opts.get("grid", "")) == "drag"
	knockout = bool(opts.get("knockout", false))
	lap_length = float(opts.get("lap_length", 0.0))
	var diff := String(opts.get("difficulty", "medium"))
	var band: Vector2 = PACE_BANDS.get(diff, PACE_RANGE)
	var pc: Array = LiveEvents.PACE.get(car_key, LiveEvents.PACE.stock)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := clampi(count, 0, MAX_RIVALS)
	# a drag grid: everyone abreast, as wide apart as the road allows (a two-lane carriageway takes four)
	var road_w := 2.0 * (half[0] if n_pts > 0 else 4.0)
	drag_lane = clampf((road_w - 1.7) / maxf(n, 1), 2.0, 3.6)
	var dlats := []
	for k in n + 1:
		dlats.append((float(k) - float(n) * 0.5) * drag_lane)
	var slots := _grid_slots(n)
	_player_grid = slots[0]
	for k in n:
		var f := lerpf(band.y, band.x, float(k) / maxf(n - 1, 1)) + rng.randf_range(-0.012, 0.012)
		var g: Vector2 = Vector2(0.0, float(dlats[k + 1 if k >= 1 else 0])) if drag else slots[k + 1]
		var lane: float = g.y if drag else float(LANES[k])
		var r := {"s": g.x, "v": 0.0, "lat": g.y, "lane": lane, "f": f, "vmax": float(pc[0]) * f,
			"acc": float(pc[1]) * f, "env": _envelope(float(pc[0]) * f, float(pc[2]) * f * f, float(pc[3]) * f), "t_done": -1.0, "out": false}
		if not drag:
			r.lat = _fit(r.s, r.lat)
			r.lane = _fit(r.s, r.lane)
		rivals.append(r)
	if drag:
		_player_lat0 = float(dlats[1]) if n >= 1 else 0.0
		var dt_ref := float(opts.get("drag_time", 0.0))
		if dt_ref > 0.0:
			var db: Vector2 = DRAG_BANDS.get(diff, DRAG_BANDS.medium)
			for k in n:
				var want := dt_ref * (lerpf(db.y, db.x, float(k) / maxf(n - 1, 1)) + rng.randf_range(-0.004, 0.004))
				_calibrate_drag(rivals[k], want)
				var rk: Dictionary = rivals[k]
				rk.env = _envelope(float(rk.vmax), float(pc[2]) * float(rk.f) * float(rk.f), float(pc[3]) * float(rk.f))

var _player_lat0 := DRAG_PLAYER_LAT

## Where the player should be put at the start, (along, across from the road's centre): the default grid has it
## at the route's start, a drag grid in its own lane.
func player_grid() -> Vector2:
	return Vector2(0.0, _player_lat0) if drag else _player_grid

var _player_grid := Vector2.ZERO

## The grid on the route itself (never behind its start, where the road may bend away): rows ROW m apart running
## forward to the front row, two abreast where the road takes two cars side by side, single file where it doesn't.
## Slot 0 is the player's (pole), then the rivals': [(along, across)].
func _grid_slots(n: int) -> Array:
	const ROW := 7.0
	var lim := INF # the narrowest the road gets over the grid's length
	for i in range(0, mini(int(ROW * (n + 1) / STEP) + 1, half.size())):
		lim = minf(lim, maxf(half[i] - EDGE, 0.3))
	if not is_finite(lim):
		lim = 0.3
	var two := lim >= 1.25
	var a := clampf(lim, 1.25, 1.5)
	var rows := ceili((n + 1) / 2.0) if two else n + 1
	var out := []
	for j in n + 1:
		var row := j / 2 if two else j
		var s := float(rows - 1 - row) * ROW
		var lat := (a if j % 2 == 1 else -a) if two else 0.0
		out.append(Vector2(s, _fit(s, lat)))
	return out

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

## Lap (0 for the first) a distance along the route lies in; always 0 outside a knockout.
func lap_of(s: float) -> int:
	if not knockout or lap_length <= 0.0:
		return 0
	var laps := maxi(int(ceilf(length / lap_length - 0.001)), 1)
	return clampi(int(maxf(s, 0.0) / lap_length), 0, laps - 1)

func player_lap() -> int:
	return lap_of(player_s)

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
## direction is +). The direction and the across turn smoothly through a bend; before the start and past the end
## the route runs straight on.
func pose(s: float, lat: float) -> Array:
	if pts.size() < 2:
		return [pts[0] if pts.size() > 0 else Vector2.ZERO, Vector2.RIGHT]
	if s < 0.0 or s > length:
		var at_end := s > length
		var d0: Vector2 = tan[tan.size() - 1] if at_end else tan[0]
		var base: Vector2 = pts[pts.size() - 1] if at_end else pts[0]
		var c0: float = centre[centre.size() - 1] if at_end else centre[0]
		var p0 := base + d0 * (s - length if at_end else s)
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
			# home: it rolls on past the line, easing off towards the edge of the road, and stops out of the way
			v = move_toward(v, 0.0, 3.5 * dt)
			r.v = v
			r.s = s + v * dt
			var edge := maxf(_at(half, length) - EDGE, 0.3) * (1.0 if float(r.lat) >= 0.0 else -1.0)
			r.lat = move_toward(float(r.lat), edge, LAT_RATE * 0.5 * dt)
			continue
		var gap := s - player_s
		var band := 1.0 if drag else 1.0 - BAND * clampf(gap / BAND_GAP, -1.0, 1.0)
		var env: PackedFloat32Array = r.env
		var i := _index(s)
		var cap := lerpf(env[i], env[i + 1], clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.01), 0.0, 1.0)) * band
		if not drag:
			cap = _traffic(k, r, cap, pv, dt)
		var a := float(r.acc) * (DRAG_LAUNCH if drag else 1.0) * band * maxf(0.08, 1.0 - v / (float(r.vmax) * band))
		v = minf(v + a * dt, cap) if v < cap else move_toward(v, cap, 9.0 * dt)
		r.v = maxf(v, 0.0)
		r.s = s + float(r.v) * dt
		if not drag:
			_no_overlap(k, r, s, float(r.lat))
			r.lane = _fit(float(r.s), float(r.lane))
			# never snapped across (no jump), and no faster than a car at that speed can move over
			var lat0 := float(r.lat)
			r.lat = move_toward(lat0, float(r.lane), minf(LAT_RATE * 2.0, 0.5 + 0.25 * float(r.v)) * dt)
			_no_overlap(k, r, float(r.s), lat0)

		if float(r.s) >= length:
			r.t_done = t
	if not drag:
		separate(dt)
	if knockout and lap_length > 0.0:
		_knock_out()

## A rival's move from (s0 along, lat0 across) to where it is now undone as far as it would run into another
## rival: it stops at the tail of the car ahead on its line, and it doesn't move across into a car alongside.
func _no_overlap(k: int, r: Dictionary, s0: float, lat0: float) -> void:
	for j in rivals.size():
		if j == k or bool(rivals[j].out):
			continue
		var o: Dictionary = rivals[j]
		var ds := float(o.s) - float(r.s)
		if absf(ds) >= CAR_L or absf(float(o.lat) - float(r.lat)) >= CAR_W:
			continue
		if absf(float(o.lat) - lat0) >= CAR_W:
			r.lat = lat0 # the move across ran into it
			r.lane = lat0
		elif float(o.s) > s0:
			r.s = maxf(s0, float(o.s) - CAR_L) # caught up with it: on its tail
			r.v = minf(float(r.v), float(o.v))

## Contact between rivals: no two running cars overlap. Side by side where the road takes both they are eased apart
## across it; where it doesn't, the car behind drops back to the one ahead's tail and its pace.
func separate(dt := 0.1) -> void:
	var live_k := []
	for k in rivals.size():
		if not bool(rivals[k].out):
			live_k.append(k)
	for pass_i in 2:
		for a in live_k.size():
			for b in range(a + 1, live_k.size()):
				var ra: Dictionary = rivals[live_k[a]]
				var rb: Dictionary = rivals[live_k[b]]
				var ds := float(rb.s) - float(ra.s)
				var dl := float(rb.lat) - float(ra.lat)
				if absf(ds) >= CAR_L or absf(dl) >= CAR_W:
					continue
				var front := rb if ds >= 0.0 else ra
				var back := ra if ds >= 0.0 else rb
				var s_mid := 0.5 * (float(ra.s) + float(rb.s))
				var lim := maxf(_at(half, s_mid) - EDGE, 0.3)
				var dir := 1.0 if dl >= 0.0 else -1.0 # b goes this way across, a the other
				var fits := 2.0 * lim >= CAR_W + 0.05
				if fits and absf(ds) > 1.0:
					# eased apart across the road (as fast as a car steers: no jump), each towards its own side
					var step_l := minf(LAT_RATE, 0.3 + 0.15 * minf(float(ra.v), float(rb.v))) * dt
					ra.lat = clampf(float(ra.lat) - dir * step_l, -lim, lim)
					rb.lat = clampf(float(rb.lat) + dir * step_l, -lim, lim)
					ra.lane = ra.lat
					rb.lane = rb.lat
				else:
					# no room: the one behind backs off (eased, no jump) and slows below the one ahead's pace
					var overlap := CAR_L - (float(front.s) - float(back.s))
					back.s = float(back.s) - minf(overlap, 2.5 * dt)
					back.v = minf(float(back.v), float(front.v) * 0.9)

## The cars round a rival (the other rivals and the player): one close ahead on its line holds it to its speed
## while it pulls out to pass on the side with room; one alongside, overlapping, pushes it across. Returns the
## speed cap.
func _traffic(k: int, r: Dictionary, cap: float, pv: float, dt: float) -> float:
	var s: float = r.s
	var lat: float = r.lat
	var others := []
	for j in rivals.size():
		if j != k and not bool(rivals[j].out):
			others.append([float(rivals[j].s), float(rivals[j].lat), float(rivals[j].v), false])
	if not player_out:
		others.append([player_s, player_lat, pv, true])
	var lim := maxf(_at(half, s) - EDGE, 0.3)
	var held := false
	for o in others:
		var ds: float = float(o[0]) - s
		var dl: float = float(o[1]) - lat
		if absf(dl) >= CAR_W:
			continue
		if ds > 0.0 and ds < CAR_L + 7.0:
			# on its line ahead: pick the side with room to pass (on a lane too narrow for two, the wider side, to
			# squeeze by) and follow, closing gently on a slower car. Held up long behind the player it noses on past
			# (a shove, OpenWorld's contact: a crawling player never blocks the whole field); behind another rival it
			# waits for room (separate() keeps two rivals from ever overlapping)
			var left := float(o[1]) + CAR_W + 0.2
			var right := float(o[1]) - CAR_W - 0.2
			var room_l := left <= lim
			var room_r := right >= -lim
			if room_l and (not room_r or absf(left - lat) <= absf(right - lat)):
				r.lane = left
			elif room_r:
				r.lane = right
			else:
				r.lane = lim if lim - float(o[1]) >= float(o[1]) + lim else -lim
			if not bool(o[3]) or float(r.get("held", 0.0)) < HELD_MAX or float(o[2]) > float(r.v) + 3.0:
				cap = minf(cap, float(o[2]) + maxf(ds - CAR_L, 0.0) * 0.6)
				held = true
		elif absf(ds) <= CAR_L:
			# alongside and overlapping: shoved apart across the road
			var away := -1.0 if dl > 0.0 else 1.0
			r.lane = _fit(s, lat + away * CAR_W)
			if ds > 0.0 and (not bool(o[3]) or float(r.get("held", 0.0)) < HELD_MAX):
				cap = minf(cap, float(o[2]))
				held = true
	var h := float(r.get("held", 0.0))
	if held and cap < float(r.v) + 2.0:
		h += dt
		if h >= HELD_MAX:
			h = HELD_MAX + 4.0 # a few seconds to get by before it would wait again
	else:
		h = maxf(h - dt, 0.0)
	r.held = h
	return cap

## Each time the leader (the player or a running rival) crosses a new multiple of the lap, short of the end of
## the last lap, the last running car is out.
func _knock_out() -> void:
	var lead := 0.0 if player_out else player_s
	for r in rivals:
		if not bool(r.out):
			lead = maxf(lead, float(r.s))
	while _next_lap * lap_length < length - 1.0 and lead >= _next_lap * lap_length:
		_next_lap += 1
		var alive := 0
		for r in rivals:
			if not bool(r.out):
				alive += 1
		if alive + (0 if player_out else 1) <= 1:
			break
		var low := INF if player_out else player_s
		var who := -2 if player_out else -1
		for k in rivals.size():
			var r: Dictionary = rivals[k]
			if bool(r.out) or float(r.t_done) >= 0.0:
				continue
			if float(r.s) < low:
				low = float(r.s)
				who = k
		if who == -2:
			break
		out_order.append(who)
		if who == -1:
			player_out = true
			player_out_pos = alive + 1
		else:
			rivals[who].out = true
			rivals[who].v = 0.0

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

func field() -> int:
	if player_out:
		return rivals.size() + 1
	var n := 1
	for r in rivals:
		if not bool(r.out):
			n += 1
	return n

## The fastest rival time home so far, or -1.
func best_time() -> float:
	var b := -1.0
	for r in rivals:
		if float(r.t_done) >= 0.0 and (b < 0.0 or float(r.t_done) < b):
			b = float(r.t_done)
	return b
