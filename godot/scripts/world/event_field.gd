## The field of a race on the open-world map (a live sprint, off-road race or knockout, a campaign mission's sprint,
## off-road race or knockout): the race sim itself (Race) on a track made from the event's route (EventTrack), its
## bots the circuits' drivers (Drivers.ROSTER: skill, aggression, mistakes, set-ups) on the full car physics, with
## the race's traffic, overtaking, side-by-side room, slipstream and car-to-car contact (Race.collide: oriented boxes,
## rigid-body impulses). The player's open-world car (FreeCar) is in that race as an external car (Race.external_player):
## the bots see it, race it and touch it, and the contact the race gives it is handed back to the FreeCar; the open
## world keeps its own collision with buildings, fences and the rest. No rubber banding: each bot's pace is its own,
## wherever the player is. Knockouts drop the last running car each time the leader crosses a sector line, as
## StreetRivals did. A drag race keeps StreetRivals (a standing start in lanes: nothing for the race AI to do).
##
## Scene-free like LiveEvents (OpenWorld draws the cars): step() runs the race at 120 Hz from whatever frame time it
## gets, and `rivals` mirrors the bots in the shape StreetRivals had ({s, lat, v, out, gone, done, name, number}).
class_name EventField
extends RefCounted

const DT := 1.0 / 120.0
## The bots' pace on the map's roads by the event's level: a scale on the race's own skill (Race.DIFFICULTY, moved by
## the player's rival step), so a field finishes about where the old StreetRivals bands had it against the reference
## driver (LiveEvents.pace_time): measured with tests/_event_field_probe.gd (2026-11-24).
const PACE := {"easy": 0.95, "medium": 1.02, "hard": 1.08}
const MAX_SKILL := 1.1 ## the most a bot's skill (its share of the speed profile) is scaled to, at the top rival step
const MAX_RIVALS := 9
const GRID_ROW := 7.0 ## m between grid rows
const EDGE := 0.85 ## m a grid slot's centre keeps from the road's edge
const PARK_BACK := 3.0 ## m short of the end of the road past the finish that the first car home parks

var et: EventTrack
var race: Race
var track: Track
var bots: Array[RaceCar] = []
var me: RaceCar ## the race's mirror of the player's car
var rivals: Array = [] ## per bot, refreshed each step: {s (m from the start), lat, v, out, gone, done, t_done, name, number}
var length := 0.0 ## the route, start to finish (m)
var t := 0.0 ## s since the start
var knockout := false
var lap_length := 0.0
var player_out := false
var player_out_pos := 0
var out_order: Array = [] ## who went out, in order: the bot index, or -1 for the player
var player_s := 0.0 ## the player's distance from the start (m), on the race's line
var player_v := 0.0
var player_hits: Array = [] ## [[Vector2 contact point, closing m/s]] the race's contacts with the player, for the host
var contacts := 0 ## contacts with the player so far
var bot_contacts := 0 ## contact ticks between two bots so far (a scrape alongside is one a tick)
var bot_knocks := 0 ## of those, the knocks: a closing speed of KNOCK m/s or more
var bot_knock_s := PackedFloat32Array() ## where along the route each knock was (m from the start), for the probes
const KNOCK := 1.5
var difficulty := "medium"
var pace_k := 1.0
var _next_lap := 1
var _acc := 0.0
var _input := Race.PlayerInput.new()
var _gone := {} ## bot index -> parked out of sight (no room past the finish)
var _player_grid := Vector2.ZERO

## path: the event's route; car_key: the player's car (CarCatalog), which the whole field drives; count: rivals.
## opts: map (TownMap, required), beyond (LiveEvents.beyond), difficulty, difficulty_shift, knockout, lap_length,
## mu (the weather's grip, FreeCar.mu), car_model (the player's CarModel; else CarCatalog.model(car_key)), z0 (the
## start's height), key.
func _init(path: PackedVector2Array, car_key: String, count: int, seed_value: int, opts := {}) -> void:
	var map: TownMap = opts.get("map")
	var beyond: PackedVector2Array = opts.get("beyond", PackedVector2Array())
	var key := String(opts.get("key", "event_%d" % absi(seed_value)))
	et = EventTrack.new(map, path, beyond, key, float(opts.get("z0", -INF)))
	track = et.track
	length = et.finish_s - et.start_s
	knockout = bool(opts.get("knockout", false))
	lap_length = float(opts.get("lap_length", 0.0))
	difficulty = String(opts.get("difficulty", "medium"))
	var shift := float(opts.get("difficulty_shift", 0.0))
	var n := clampi(count, 0, MAX_RIVALS)
	var cm: CarModel = opts.get("car_model", null)
	if cm == null:
		cm = CarCatalog.model(car_key) if CarCatalog.is_key(car_key) else CarModel.new()
	var st := RaceSettings.new()
	st.track = key
	st.mode = "race"
	st.format = "laps"
	st.laps = 1
	st.opponents = n
	st.difficulty = difficulty if difficulty in ["easy", "medium", "hard"] else "medium"
	st.difficulty_shift = shift
	st.real_drivers = true
	st.collisions = true
	st.draft = true
	st.race_control = false
	st.safety_car = false
	st.ai_learning = "off"
	st.bot_physics = "on"
	st.dynamic_running = false
	st.pits_enabled = false
	st.mandatory_stop = false
	st.two_compounds = false
	st.refuel = false
	st.weather = "dry"
	st.starting_tyre = "M"
	st.wear_mult = 0.0
	st.fuel_mult = 0.0
	st.auto_rejoin = false
	st.damage_mode = "cosmetic"
	st.grid = "pole"
	st.car_class = car_key if CarCatalog.is_key(car_key) else "stock"
	st.finish_distance = et.finish_s
	st.loose_spans = true
	# the strategy model's lap calibration is a few dozen simulated laps: an event needs none of it (no pits, no fuel
	# plan, no timed race), so the track gets a stand-in (Race reads T0, fuel per lap, the mixes and the pit loss)
	var cal := _stand_in_cal(cm)
	track.cal = cal
	track.cal_alt[cm.spec.get_instance_id()] = cal
	Race._track_cache[key] = track
	race = Race.new(st, null, seed_value & 0x7fffffff, {"car_model": cm})
	Race._track_cache.erase(key)
	race.external_player = true
	race.collide_finished = true
	race.hear_impacts = true
	race.lights_out_at = 0.0
	race.grip_mul = clampf(float(opts.get("mu", 1.0)), 0.1, 1.2)
	race.stop_at = et.park_s - PARK_BACK
	race.diff_params = race.diff_params.duplicate()
	race.diff_params["band"] = 0.0 # no rubber banding (the user, 2026-11-24)
	me = race.player
	var band_k: float = DifficultyProfile.band(PACE, difficulty if PACE.has(difficulty) else "medium", shift)
	pace_k = band_k
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for c in race.cars:
		if c.is_player:
			continue
		bots.append(c)
	# the grid: on the route itself (never behind its start, where the road may bend away), the player on pole
	var slots := _grid_slots(n)
	_player_grid = slots[0]
	_place(me, slots[0])
	for k in bots.size():
		var b := bots[k]
		_place(b, slots[k + 1])
		b.skill = minf(b.skill * band_k, MAX_SKILL)
		b.tyre = {"c": "M", "wear": 1.0, "temp": 1.0} # road tyres, warm: the grip the player's car has (FreeCar.mu)
		b.fuel = 30.0
		b.reaction = 0.25 + rng.randf() * 0.35 + (1.0 - b.skill) * 1.5
		# a driving error somewhere along the route, as a lap of a race gives one (Race.on_line)
		b.mistake_p = et.start_s + rng.randf() * length if rng.randf() < b.mistake_rate * maxf(length / 3000.0, 1.0) else null
		rivals.append({"s": b.s - et.start_s, "lat": b.d, "v": 0.0, "out": false, "gone": false, "done": false, "t_done": -1.0,
			"name": b.name, "number": b.number})
	me.fuel = 30.0
	me.tyre = {"c": "M", "wear": 1.0, "temp": 1.0}

## A Strategy.calibrate result good enough for a race nobody pits in: T0 from the reference driver (pace_time) and
## large enough that no "the winner's been home for ages" cap ends the race under the player.
static func _stand_in_cal(cm: CarModel) -> Dictionary:
	var mix := {}
	for m in Strategy.MIXES:
		mix[m] = {"time": 1.0, "fuel": 1.0}
	return {"m_ref": cm.mass_with_fuel(15.0), "mu_grid": [[0.4, 1e6], [1.25, 1e6]], "mass_exp": 0.0, "T0": 1e6,
		"fuel_per_lap": 0.0, "pit_drive_loss": 20.0, "top_speed": 60.0, "vs": [], "mix": mix}

func _place(c: RaceCar, slot: Vector2) -> void:
	c.s = et.start_s + slot.x
	c.d = slot.y
	var p := track.pos(c.s, c.d)
	c.x = p[0]
	c.y = p[1]
	c.heading = track.heading(c.s)
	c.vx = 0.0
	c.vy = 0.0
	c.v = 0.0
	c.yaw_rate = 0.0
	c.phys = null

## The grid on the route: rows GRID_ROW m apart running forward to the front row, two abreast where the road takes
## two cars side by side, single file where it doesn't. Slot 0 is the player's (pole), then the rivals': (along the
## route from its start, across from the road's centre).
func _grid_slots(n: int) -> Array:
	var lim := INF
	var span := GRID_ROW * (n + 1)
	var s := 0.0
	while s <= span:
		lim = minf(lim, maxf(track.half_at(et.start_s + s) - EDGE, 0.3))
		s += EventTrack.STEP
	var two := lim >= 1.25
	var a := clampf(lim, 1.25, 1.5)
	var rows := ceili((n + 1) / 2.0) if two else n + 1
	var out := []
	for j in n + 1:
		var row := j / 2 if two else j
		var along := float(rows - 1 - row) * GRID_ROW
		var lat := (a if j % 2 == 1 else -a) if two else 0.0
		var hw := maxf(track.half_at(et.start_s + along) - EDGE, 0.3)
		out.append(Vector2(along, clampf(lat, -hw, hw)))
	return out

## Where the player is put at the start: (along the route, across from the road's centre).
func player_grid() -> Vector2:
	return _player_grid

## [map position, direction] at `s` m along the route from its start and `lat` m across the road's centre (left +).
func pose(s: float, lat: float) -> Array:
	var ls := et.start_s + s
	var p := track.pos(ls, lat)
	var h := track.heading(ls)
	return [Vector2(p[0], p[1]), Vector2.from_angle(h)]

## Bot k as drawn: [map position, heading (rad), speed m/s, height of the road under it].
func car_pose(k: int) -> Array:
	var b := bots[k]
	var v := sqrt(b.vx * b.vx + b.vy * b.vy) if b.control == "free" else b.v
	return [Vector2(b.x, b.y), b.heading, v, track.sample(track.H, b.s)]

func count() -> int:
	return bots.size()

## One frame: the player's car (FreeCar.car: its pose and velocity are mirrored into the race, and the race's contact
## pushes are handed back to it), or, without one, the player at p doing pv m/s along the road. hint_s: the player's
## progress along the route (LiveEvents' own, m from the start) to find it again after a reset.
func step(dt: float, p: Vector2, pv: float, car: RaceCar = null, hint_s := -1.0) -> void:
	if dt <= 0.0 or track == null:
		return
	if car != null:
		me.x = car.x
		me.y = car.y
		me.heading = car.heading
		me.vx = car.vx
		me.vy = car.vy
		me.yaw_rate = car.yaw_rate
		me.speed = car.speed
	else:
		me.x = p.x
		me.y = p.y
		var pr0 := track.project(p.x, p.y, me.s)
		me.heading = track.heading(pr0[0])
		me.vx = cos(me.heading) * pv
		me.vy = sin(me.heading) * pv
		me.speed = pv
	if hint_s >= 0.0 and absf(me.s - (et.start_s + hint_s)) > 30.0:
		me.s = et.start_s + hint_s # lost (a reset to a gate): look again where the route has the player
	var x0 := me.x
	var y0 := me.y
	var vx0 := me.vx
	var vy0 := me.vy
	var w0 := me.yaw_rate
	_acc += dt
	var steps := 0
	while _acc >= DT and steps < 30:
		_acc -= DT
		steps += 1
		race.step(DT, _input)
		t += DT
		_read_impacts()
		_park()
		if knockout and lap_length > 0.0:
			_knock_out()
	if steps >= 30:
		_acc = 0.0
	if car != null:
		car.x += me.x - x0
		car.y += me.y - y0
		car.vx += me.vx - vx0
		car.vy += me.vy - vy0
		car.yaw_rate += me.yaw_rate - w0
	player_s = me.s - et.start_s
	player_v = maxf(pv, 0.0)
	_mirror()

## The race's contacts this tick (Race.impacts, car-to-car only): the player's for the host, the bots' counted.
func _read_impacts() -> void:
	var im := race.impacts
	var i := 0
	while i + Race.IMPACT_STRIDE <= im.size():
		if int(im[i + 3]) == 1:
			var a := int(im[i + 4])
			var b := int(im[i + 5])
			if a == me.id or b == me.id:
				contacts += 1
				player_hits.append([Vector2(im[i], im[i + 1]), float(im[i + 2])])
			else:
				bot_contacts += 1
				if float(im[i + 2]) >= KNOCK:
					bot_knocks += 1
					if bot_knock_s.size() < 4096:
						bot_knock_s.append(_s_of_id(a))
		i += Race.IMPACT_STRIDE
	im.clear()
	if player_hits.size() > 32:
		player_hits = player_hits.slice(-32)

## Cars home with no room left past the finish turn off out of sight (gone: no longer drawn or touched).
func _park() -> void:
	for k in bots.size():
		var b := bots[k]
		if not b.finished or _gone.has(k):
			continue
		if race.park_spot(b).x < et.finish_s + 2.0:
			_gone[k] = true
			b.dnf = true # (out of the race's contact and traffic; still home in its time)
			b.recovered = true
			b.vx = 0.0
			b.vy = 0.0
			b.v = 0.0

## Each time the leader (the player or a running bot) crosses a new multiple of the lap, short of the end of the
## last lap, the last running car is out.
func _knock_out() -> void:
	var lead := -INF if player_out else me.s - et.start_s
	for k in bots.size():
		if not _is_out(k):
			lead = maxf(lead, _bot_s(k))
	while _next_lap * lap_length < length - 1.0 and lead >= _next_lap * lap_length:
		_next_lap += 1
		var alive := 0
		for k in bots.size():
			if not _is_out(k):
				alive += 1
		if alive + (0 if player_out else 1) <= 1:
			break
		var low := INF if player_out else me.s - et.start_s
		var who := -2 if player_out else -1
		for k in bots.size():
			if _is_out(k) or bots[k].finished:
				continue
			if _bot_s(k) < low:
				low = _bot_s(k)
				who = k
		if who == -2:
			break
		out_order.append(who)
		if who == -1:
			player_out = true
			player_out_pos = alive + 1
			me.dnf = true
			me.recovered = true
		else:
			var b := bots[who]
			b.dnf = true
			b.recovered = true # off the road at once: no wreck to dodge
			b.vx = 0.0
			b.vy = 0.0
			b.v = 0.0
			rivals[who].out = true

func _s_of_id(id: int) -> float:
	for b in bots:
		if b.id == id:
			return b.s - et.start_s
	return -1.0

func _is_out(k: int) -> bool:
	return bool(rivals[k].out)

func _bot_s(k: int) -> float:
	return bots[k].s - et.start_s

func _mirror() -> void:
	for k in bots.size():
		var b := bots[k]
		var r: Dictionary = rivals[k]
		r.s = b.s - et.start_s
		r.lat = b.d
		r.v = sqrt(b.vx * b.vx + b.vy * b.vy) if b.control == "free" else b.v
		r.done = b.finished
		r.t_done = float(b.finish_time) if b.finished and b.finish_time != null else -1.0
		r.gone = _gone.has(k)

func lap_of(s: float) -> int:
	if not knockout or lap_length <= 0.0:
		return 0
	var laps := maxi(int(ceilf(length / lap_length - 0.001)), 1)
	return clampi(int(maxf(s, 0.0) / lap_length), 0, laps - 1)

func player_lap() -> int:
	return lap_of(player_s)

func player_done() -> bool:
	return player_out or (length > 0.0 and player_s >= length)

func finished_count() -> int:
	var n := 0
	for r in rivals:
		if bool(r.done):
			n += 1
	return n

## The player's place in the field right now (1 = leading): rivals home already or further along count ahead; rivals
## that are out don't count while the player runs (once out, it keeps the place it went out in).
func position() -> int:
	if player_out:
		return player_out_pos
	var ahead := 0
	for r in rivals:
		if bool(r.out):
			continue
		if bool(r.done) or float(r.s) > player_s:
			ahead += 1
	return ahead + 1

## "GAP 1.4 s" to the car directly ahead, or leading "LEAD 2.0 s" over the car behind, at the player's speed (at
## least 8 m/s); "" with nobody else running.
func gap_text() -> String:
	if player_out:
		return ""
	var ahead := INF
	var behind := INF
	for r in rivals:
		if bool(r.out) or bool(r.done):
			continue
		var d := float(r.s) - player_s
		if d > 0.0:
			ahead = minf(ahead, d)
		else:
			behind = minf(behind, -d)
	var v := maxf(player_v, 8.0)
	if position() > 1:
		return "GAP %.1f s" % (ahead / v) if is_finite(ahead) else ""
	return "LEAD %.1f s" % (behind / v) if is_finite(behind) else ""

func field() -> int:
	if player_out:
		return rivals.size() + 1
	var n := 1
	for r in rivals:
		if not bool(r.out):
			n += 1
	return n

## The running order for the HUD's timing list, first to last: {name, number, player, gap ("" for the leader, "+1.4"
## seconds to the car ahead, a time once home, "OUT"), out, done}. Cars knocked out come last, the latest out first.
func standings() -> Array:
	var live_rows: Array = []
	for k in rivals.size():
		if not bool(rivals[k].out):
			live_rows.append(k)
	live_rows.sort_custom(func(a, b):
		var ra: Dictionary = rivals[a]
		var rb: Dictionary = rivals[b]
		var da := bool(ra.done)
		var db := bool(rb.done)
		if da != db:
			return da
		if da:
			return float(ra.t_done) < float(rb.t_done)
		return float(ra.s) > float(rb.s))
	var rows: Array = []
	for k in live_rows:
		var r: Dictionary = rivals[k]
		rows.append({"name": String(r.name), "number": int(r.number), "player": false, "s": float(r.s),
			"t_done": float(r.t_done), "out": false})
	var mine := {"name": "YOU", "number": 0, "player": true, "s": player_s, "t_done": -1.0, "out": player_out}
	if not player_out:
		rows.insert(clampi(position() - 1, 0, rows.size()), mine)
	var v := maxf(player_v, 8.0)
	for i in rows.size():
		var row: Dictionary = rows[i]
		row.done = float(row.t_done) >= 0.0
		if bool(row.done):
			row.gap = LiveEvents.clock_text(float(row.t_done))
		elif i == 0:
			row.gap = ""
		else:
			var up: Dictionary = rows[i - 1]
			var d := float(up.s) - float(row.s) if not bool(up.done) else maxf(length - float(row.s), 0.0)
			row.gap = "+%.1f" % maxf(d / v, 0.0)
	for j in range(out_order.size() - 1, -1, -1):
		var who := int(out_order[j])
		if who == -1:
			mine.gap = "OUT"
			mine.done = true
			rows.append(mine)
		else:
			var r: Dictionary = rivals[who]
			rows.append({"name": String(r.name), "number": int(r.number), "player": false, "gap": "OUT", "out": true, "done": true})
	return rows

## The fastest rival time home so far, or -1.
func best_time() -> float:
	var b := -1.0
	for r in rivals:
		if float(r.t_done) >= 0.0 and (b < 0.0 or float(r.t_done) < b):
			b = float(r.t_done)
	return b

## Breaks the race's reference cycles (call when the run ends).
func dispose() -> void:
	if race:
		race.dispose()
