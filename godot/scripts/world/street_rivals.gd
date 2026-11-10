## Rivals of a live STREET RACE (LiveEvents): 3-5 cars on a small grid behind and beside the player, driving the
## event's route polyline (no walls, no physics: they follow the route at a lateral offset). Each has a speed
## profile in the spirit of LiveEvents.pace_time (corner speeds from grip, acceleration falling off to the top
## speed, braking in time) scaled by its own pace factor, so their finishing times fall between the gold and the
## bronze reference. Rubber-banding is mild (a few percent). Scene-free: OpenWorld draws and collides them.
class_name StreetRivals
extends RefCounted

const STEP := 5.0 ## m between profile samples
const PACE_RANGE := Vector2(0.84, 0.95) ## slowest .. fastest rival against the reference driver (gold is 1/1.04)
const BAND := 0.03 ## rubber band: at most this fraction faster / slower
const BAND_GAP := 150.0 ## m ahead of / behind the player where the band is fully on
const GRID := [Vector2(0.0, 2.6), Vector2(-7.0, -1.3), Vector2(-7.0, 1.3), Vector2(-14.0, -1.3), Vector2(-14.0, 1.3),
	Vector2(-21.0, -1.3), Vector2(-21.0, 1.3), Vector2(-28.0, -1.3), Vector2(-28.0, 1.3), Vector2(-35.0, -1.3)] ## (along, across) m from the player's spot: 2 abreast, rows 7 m apart
const LANES := [1.2, -1.2, 0.4, -0.4, 1.6, -1.6, 0.8, -0.8, 0.0] ## racing offsets across the road (m)
const MAX_RIVALS := 9
const DRAG_PLAYER_LAT := -1.8
const DRAG_LAUNCH := 1.1 ## a drag rival launches hard: acceleration factor (no waiting for the lights, no wheelspin lost)
const DRAG_LATS := [1.8, -5.4, 5.4, -9.0, 9.0, -12.6, 12.6, -16.2, 16.2] ## the rivals' own lanes on a drag grid (the player has -1.8)

var pts := PackedVector2Array()
var cum := PackedFloat32Array()
var length := 0.0
var rivals: Array = [] ## {s, v, lat, lane, f, env: PackedFloat32Array, vmax, acc, t_done (-1 racing), out}
var t := 0.0
var player_s := 0.0
var drag := false ## every car on one line at s = 0, each in its own lane for good
var knockout := false
var lap_length := 0.0
var player_out := false
var player_out_pos := 0 ## the player's place when knocked out (rivals still running + 1)
var out_order: Array = [] ## who went out, in order: the rival index, or -1 for the player
var _next_lap := 1 ## the next lap boundary (a multiple of lap_length) that knocks a car out

## opts: grid "drag" (one line, own lanes, see player_grid), knockout (bool) with lap_length (m).
func _init(path: PackedVector2Array, car_key: String, count: int, seed_value: int, opts := {}) -> void:
	pts = LiveEvents.resample(path, STEP)
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + pts[i - 1].distance_to(pts[i])
	length = cum[cum.size() - 1] if cum.size() > 0 else 0.0
	drag = String(opts.get("grid", "")) == "drag"
	knockout = bool(opts.get("knockout", false))
	lap_length = float(opts.get("lap_length", 0.0))
	var pc: Array = LiveEvents.PACE.get(car_key, LiveEvents.PACE.stock)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := clampi(count, 0, MAX_RIVALS)
	for k in n:
		var f := lerpf(PACE_RANGE.y, PACE_RANGE.x, float(k) / maxf(n - 1, 1)) + rng.randf_range(-0.012, 0.012)
		var g: Vector2 = Vector2(0.0, float(DRAG_LATS[k])) if drag else GRID[k]
		var lane: float = g.y if drag else float(LANES[k])
		rivals.append({"s": g.x, "v": 0.0, "lat": g.y, "lane": lane, "f": f, "vmax": float(pc[0]) * f,
			"acc": float(pc[1]) * f, "env": _envelope(float(pc[0]) * f, float(pc[2]) * f * f, float(pc[3]) * f), "t_done": -1.0, "out": false})

## Where the player should be put at the start, (along, across): the default grid has it at the route's start,
## a drag grid in its own lane.
func player_grid() -> Vector2:
	return Vector2(0.0, DRAG_PLAYER_LAT) if drag else Vector2.ZERO

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

## Highest speed at each sample that still makes every corner ahead: grip-limited corner speed, braked into.
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
		env[i] = minf(vmax, sqrt(lat / maxf(k, 1e-5)))
	for i in range(n - 2, -1, -1):
		env[i] = minf(env[i], sqrt(env[i + 1] * env[i + 1] + 2.0 * brk * (cum[i + 1] - cum[i])))
	return env

func _index(s: float) -> int:
	return clampi(int(s / STEP), 0, maxi(pts.size() - 2, 0))

## [map position, direction] at distance s along the route and `lat` m across it (left of the direction is +).
func pose(s: float, lat: float) -> Array:
	if pts.size() < 2:
		return [pts[0] if pts.size() > 0 else Vector2.ZERO, Vector2.RIGHT]
	var i := _index(maxf(s, 0.0))
	var d := (pts[i + 1] - pts[i]).normalized()
	var p := pts[0] + (pts[1] - pts[0]).normalized() * s if s < 0.0 else pts[i].lerp(pts[i + 1], clampf((s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.01), 0.0, 1.0))
	return [p + Vector2(-d.y, d.x) * lat, d]

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

## One step: the player at p doing pv m/s (its progress is followed for the positions and the band).
func step(dt: float, p: Vector2, pv: float) -> void:
	if pts.size() < 2 or dt <= 0.0:
		return
	t += dt
	player_s = project(p, player_s)
	for r in rivals:
		if bool(r.out) or float(r.t_done) >= 0.0:
			continue
		var s: float = r.s
		var v: float = r.v
		var gap := s - player_s
		var band := 1.0 - BAND * clampf(gap / BAND_GAP, -1.0, 1.0)
		var env: PackedFloat32Array = r.env
		var i := _index(s)
		var cap := lerpf(env[i], env[i + 1], clampf((s - cum[i]) / STEP, 0.0, 1.0)) * band
		# don't drive through the car ahead on the same line: follow it and drift across (a drag runs in its lane)
		if not drag:
			for o in rivals:
				if o == r or bool(o.out) or float(o.t_done) >= 0.0:
					continue
				if float(o.s) > s and float(o.s) - s < 7.0 and absf(float(o.lat) - float(r.lat)) < 1.8:
					cap = minf(cap, float(o.v) + 0.5)
					r.lane = clampf(float(r.lane) + (1.0 if float(r.lat) >= float(o.lat) else -1.0) * dt, -2.0, 2.0)
		var a := float(r.acc) * (DRAG_LAUNCH if drag else 1.0) * band * maxf(0.08, 1.0 - v / (float(r.vmax) * band))
		v = minf(v + a * dt, cap) if v < cap else move_toward(v, cap, 9.0 * dt)
		r.v = v
		r.s = s + v * dt
		if not drag:
			r.lat = move_toward(float(r.lat), float(r.lane), 0.6 * dt)
		if float(r.s) >= length:
			r.t_done = t
	if knockout and lap_length > 0.0:
		_knock_out()

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
	r.lat = clampf(float(r.lat) + across, -3.0, 3.0)
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
