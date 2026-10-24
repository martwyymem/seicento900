## Race control: what happens after the contact physics (Race.collide / barrier_contact) has done its work.
## - Damage: every hard impact bends the car a little (less power, more drag, a steering pull) until the
##   crew repairs it at a pit stop; a big enough one wrecks it, and the wreck slides to rest where it hit.
## - Stewards: each car-to-car incident is investigated a few seconds later. Whoever drove into the other
##   car gets a warning or a time penalty scaled by the consequences; a racing incident gets nothing.
## - Marshals: the lap is split into marshal sectors. A spun, stopped or beached car brings out a yellow
##   (double yellow if it is on the racing surface) there and in the sector before it; no overtaking, slow down.
## - Safety car: a car stopped on the track, or several stranded at once, neutralises the race. The safety
##   car picks up the leader, the field queues behind it at reduced pace while the marshals clear the
##   track, then it pulls in and the race goes green again when the leader crosses the line.
## - Red flag: a huge impact (barrier repairs) or a multi-car pile-up suspends the race. The field returns to
##   the pit lane and waits in order, the crews may repair the cars and fit fresh tyres, and the race
##   restarts behind the safety car.
class_name RaceControl
extends RefCounted

const G := 9.81 ## gravity, m/s²
const SECTOR_LEN := 200.0 ## roughly one marshal post per 200 m
const DMG_FLOOR := 1.2 ## m/s of impact a car shrugs off
const DMG_SPAN := 8.5 ## further m/s that wreck it in one hit
const REPAIR_TIME := 24.0 ## s of pit work to straighten a car on the verge of being wrecked
const REPAIR_AT := 0.3 ## damage at which a team calls the car in for repairs
const YELLOW_PACE := [1.0, 0.9, 0.72] ## bots' pace in a clear / yellow / double-yellow sector
const PLAYER_SLOW := 0.86 ## share of the racing line's limit you may do under double yellow
const HAZARD_PACE := 0.9 ## bots elsewhere on the lap while a double yellow is out
const CATCHUP_PACE := 0.95 ## anyone more than CATCHUP_GAP off the car ahead under the safety car
const CATCHUP_GAP := 25.0 ## m
const LIMITER_DECEL := 3.0 ## m/s² the V limiter plans to brake at, for corners and for the car ahead
const LIMITER_LOOK := 160.0 ## m of track the limiter looks ahead for slower stretches
const LIMITER_GAP := 6.0 ## m the limiter keeps to the car ahead under the safety car
const DELTA_PACE := 0.8 ## the fastest anyone may go under the safety car while catching the queue
const RED_PACE := 0.6 ## ... and under a red flag on the way back to the pits
const SC_PACE := 0.7 ## share of the racing line's speed the safety car itself drives at (capped by SC_VMAX)
const SC_VMAX := 31.0 ## 112 km/h: plenty for a queue of Seicentos
const SC_GAP := 12.0 ## metres each car keeps to the one ahead in the queue
const SC_MIN_TIME := 75.0 ## the safety car stays out at least this long
const RECOVER_OFF := 35.0 ## s for the marshals to clear a car beached off the racing surface
const RECOVER_ON := 50.0 ## ... and one stopped on the track (they work under the safety car)
const RED_IMPACT := 19.0 ## m/s square into a barrier: the barrier needs repairing, red flag
const RED_SUSPEND := 30.0 ## s the race stays suspended once everybody is in the pit lane
const PILEUP_CARS := 2 ## cars out of control at once that bring yellow flags round the whole circuit
const PILEUP_SC_CARS := 3 ## ... and cars lying across the track that bring out the safety car
const PILEUP_SC_AFTER := 4.0 ## s that many must stay there before the safety car comes out
const PILEUP_HOLD := 15.0 ## s the whole-circuit yellow stays out after the last car was in trouble
const YELLOW_BEHIND := 2 ## sectors upstream of a double yellow that carry a yellow, so drivers see it coming
const GIVE_BACK := 12.0 ## s to hand back a place taken under yellow / safety car before a penalty

var race: Race
var track: Track
var flag := "green" ## green | sc | sc_in | red
var red_state := "" ## slowing | suspended
var red_t := 0.0
var green_t := -100.0 ## race clock when the race last went green after a neutralisation
var sc: RaceCar ## the safety car (not part of race.cars: it is never classified)
var sc_state := "garage" ## garage | waiting | out | in
var sc_since := 0.0
var sc_from_pit := false
var n_sec := 0
var sec_len := 0.0
var yellow := PackedInt32Array() ## per marshal sector: 0 clear, 1 yellow, 2 double yellow
var _hold := PackedFloat64Array() ## how long each flag stays out after its cause has gone
var _cause := PackedInt32Array()
var _announced := PackedInt32Array() ## double yellow already called out in the feed
var incidents := {} ## pair key -> {a, b, t, last, dv, at_fault, victim, under, vic_dmg}
var give_back: Array = [] ## [{car (the one you passed), until, why}]
var _gaps := {} ## car -> the player's gap to it last tick, for overtakes under yellow
var _over_t := 0.0 ## seconds you've spent too fast in a slow zone this episode
var _over_warned := false
var _wrecks: Array = [] ## [clock] of recent crashes, for pile-up red flags
var _red_reason := ""
var _tick := 0.0
var _fcy := false
var _fcy_until := -100.0 ## race clock until which a pile-up keeps the whole circuit under yellow
var _trouble := 0 ## cars spun, stopped or stranded right now
var _blocking := 0 ## of those, the ones lying across the racing surface
var _pileup_since := -100.0 ## last clock time fewer than PILEUP_SC_CARS cars lay across the track
var hazard := false ## a car is stopped on the racing surface somewhere: everybody eases off

func _init(race_: Race) -> void:
	race = race_
	track = race.track
	n_sec = maxi(4, ceili(track.L / SECTOR_LEN))
	sec_len = track.L / n_sec
	yellow.resize(n_sec)
	_hold.resize(n_sec)
	_cause.resize(n_sec)
	_announced.resize(n_sec)
	sc = RaceCar.new()
	sc.id = -1
	sc.name = "Safety Car"
	sc.number = 0
	sc.color = Color("#f4f4f0")
	sc.is_safety_car = true
	sc.control = "rail"
	sc.tyre = {"c": "M", "wear": 1.0, "temp": 1.0}

# ---------------- queries ----------------
func sector_of(s: float) -> int:
	return clampi(int(track.wrap_s(s) / sec_len), 0, n_sec - 1)

func yellow_at(s: float) -> int:
	return yellow[sector_of(s)]

## Racing is neutralised: nobody may overtake anywhere.
var neutral: bool:
	get: return flag != "green"

var sc_on_track: bool:
	get: return sc_state == "out" or sc_state == "in"

## No overtaking for this car right now (its own sector or the next one is flagged, or the race is neutral).
func no_pass(car: RaceCar) -> bool:
	return neutral or yellow_at(car.s) > 0 or yellow_at(car.s + 80.0) > 0

## The player is driving under a flag (the learning AI doesn't learn from these laps).
func slowed(car: RaceCar) -> bool:
	return no_pass(car)

static func _speed(c: RaceCar) -> float:
	return sqrt(c.vx * c.vx + c.vy * c.vy) if c.control == "free" else c.v

func _running(c: RaceCar) -> bool:
	return not c.dnf and not c.finished and c.mode == "race"

func _leader() -> RaceCar:
	for c in race.order:
		if not c.dnf and not c.finished:
			return c
	return null

# ---------------- damage ----------------
## An impact of dv m/s (velocity change / speed into a barrier). f is the cosine between the car's heading
## and the direction it was hit from (1 head-on, 0 side, -1 from behind), for which parts take the damage.
## Returns true if it wrecked the car.
func hurt(car: RaceCar, dv: float, into_barrier := false, f := 0.0) -> bool:
	if car.is_safety_car or car.dnf or dv <= DMG_FLOOR:
		return false
	var x := (dv - DMG_FLOOR) / DMG_SPAN
	var add := x * x
	var before := car.damage
	car.damage = minf(1.0, car.damage + add)
	Service.spread(car, car.damage - before, f)
	if add > 0.02:
		car.dmg_pull = clampf(car.dmg_pull + (race.rng.next() - 0.5) * 0.12 * add, -0.05, 0.05)
	if car.damage >= 1.0:
		wreck(car, dv, into_barrier)
		return true
	if car.is_player and add > 0.04:
		var hint := " — box for repairs" if car.damage >= REPAIR_AT and race.s.mode == "race" else ""
		log_rc("Damage: %d%% (steering pull, less power)%s" % [roundi(car.damage * 100.0), hint], "bad")
	elif not car.is_player and before < 0.15 and car.damage >= 0.15 and _near_player(car):
		log_rc("%s is damaged and limping" % car.name, "info")
	return false

func wreck(car: RaceCar, dv: float, into_barrier: bool) -> void:
	car.wrecked = true
	car.dnf = true
	car.dnf_reason = "Accident"
	car.pit_request = false
	car.overtake_t = 0.0
	if car.control == "rail":
		race.to_free(car) # it slides on with whatever speed it had
	car.spin_t = race.clock
	_strand(car)
	_wrecks.append(race.clock)
	if car.is_player:
		log_rc("You crashed out of the race!", "bad")
	else:
		log_rc("%s crashes out!" % car.name, "bad")
	if into_barrier and dv >= RED_IMPACT and race.phase == "racing" and not race.winner:
		_red_reason = "barrier repairs after %s's crash" % _short(car)

func _strand(car: RaceCar) -> void:
	car.stranded = true
	race.any_stranded = true
	car.recover_left = RECOVER_ON if absf(car.d) < track.half + 0.6 else RECOVER_OFF

## Seconds of extra pit work to repair this car's damage.
func repair_time(car: RaceCar) -> float:
	return car.damage * REPAIR_TIME if car.damage > 0.02 else 0.0

func repaired(car: RaceCar) -> void:
	car.damage = 0.0
	car.dmg_pull = 0.0
	car.parts = {}
	Service.sync(car)
	car.repair_asked = false

# ---------------- stewards ----------------
static func _pair_key(a: RaceCar, b: RaceCar) -> int:
	return mini(a.id, b.id) * 64 + maxi(a.id, b.id)

func _out_of_control(c: RaceCar) -> bool:
	if c.stranded or c.dnf or race.clock - c.spin_t < 2.0:
		return true
	return absf(SimUtil.wrap_angle(c.heading - track.heading(c.s))) > 0.9

## Race.collide found a (closing) contact: n points from a to b, jimp is the impulse per car (m/s).
func report_contact(a: RaceCar, b: RaceCar, nx: float, ny: float, dv_a: float, dv_b: float) -> void:
	var key := _pair_key(a, b)
	var inc = incidents.get(key)
	if inc == null and maxf(dv_a, dv_b) > 1.5 and not a.stranded and not b.stranded:
		# who drove into whom: each car's own speed towards the other along the contact normal
		var a_in := a.vx * nx + a.vy * ny
		var b_in := -(b.vx * nx + b.vy * ny)
		var at_fault: RaceCar = null
		if absf(a_in - b_in) > 0.8:
			at_fault = a if a_in > b_in else b
		var victim: RaceCar = null
		if at_fault:
			victim = b if at_fault == a else a
			# a car already out of control isn't driving into anyone, and a spinning one can't be avoided
			if _out_of_control(at_fault) or _out_of_control(victim):
				at_fault = null
				victim = null
		inc = {"a": a, "b": b, "t": race.clock, "last": race.clock, "dv": 0.0, "at_fault": at_fault,
			"victim": victim, "under": no_pass(a) or no_pass(b), "vic_dmg": victim.damage if victim else 0.0,
			"announced": false}
		incidents[key] = inc
	# where each car was hit: b lies along n from a, a along -n from b
	hurt(a, dv_a, false, cos(a.heading) * nx + sin(a.heading) * ny)
	hurt(b, dv_b, false, -(cos(b.heading) * nx + sin(b.heading) * ny))
	if inc == null:
		return
	inc.last = race.clock
	inc.dv = maxf(inc.dv, maxf(dv_a, dv_b))
	if not inc.announced and inc.dv > 3.0 and (a.is_player or b.is_player):
		inc.announced = true
		log_rc("Incident between #%d %s and #%d %s — under investigation" % [a.number, _short(a), b.number, _short(b)], "rc")

## A barrier hit at vn m/s; f as in hurt (the wall's direction from the car against its heading).
func report_barrier(car: RaceCar, vn: float, f := 0.0) -> void:
	hurt(car, vn, true, f)

func _decide(inc: Dictionary) -> void:
	var a: RaceCar = inc.a
	var b: RaceCar = inc.b
	var mine: bool = a.is_player or b.is_player
	var off: RaceCar = inc.at_fault
	if not off or inc.dv < 2.0:
		if inc.announced:
			log_rc("Incident #%d / #%d: racing incident — no further action" % [a.number, b.number], "rc")
		return
	var vic: RaceCar = inc.victim
	var spun: bool = vic.spin_t >= inc.t - 0.1
	var harm: float = vic.damage - inc.vic_dmg
	var secs := 0
	if vic.wrecked:
		secs = 10
	elif spun or harm > 0.12 or inc.dv > 6.0:
		secs = 5
	elif off.offences >= 2:
		secs = 5
	if inc.under and (secs > 0 or inc.dv > 3.5):
		# a real hit under yellows or the safety car is judged harshly; a nudge in the queue isn't
		secs = maxi(secs, 5) + (5 if secs >= 5 else 0)
	off.offences += 1
	var why := "causing a collision with %s%s" % [_short(vic), " under %s" % ("the safety car" if flag != "green" else "yellow flags") if inc.under else ""]
	if secs == 0:
		if mine or _near_player(off):
			log_rc("Warning for #%d %s — %s" % [off.number, _short(off), why], "rc")
		return
	penalise(off, secs, why)

func penalise(car: RaceCar, secs: int, why: String) -> void:
	car.penalties.append([why.substr(0, 1).to_upper() + why.substr(1), float(secs)])
	car.penalty = 0.0
	for p in car.penalties:
		car.penalty += p[1]
	var who := "you" if car.is_player else "#%d %s" % [car.number, _short(car)]
	log_rc("%d s time penalty for %s — %s" % [secs, who, why], "bad" if car.is_player else "rc")

# ---------------- per tick ----------------
func step(dt: float) -> void:
	if race.phase == "countdown":
		return
	_tick -= dt
	for c in race.cars:
		if c.stranded:
			_slide(c, dt)
		elif c.dnf and not c.recovered and c.mode == "race" and not c.wrecked:
			_strand(c) # out of fuel or retired where it stopped
	if race.s.mode != "race":
		return # alone against the clock (a rally stage): damage only, no flags, stewards or safety car
	_update_yellows(dt)
	_recover(dt)
	# stewards decide a few seconds after the dust settles
	for key in incidents.keys():
		var inc: Dictionary = incidents[key]
		if race.clock - inc.last > 4.0 and race.clock - inc.t > 7.0:
			incidents.erase(key)
			_decide(inc)
	_player_rules(dt)
	if _tick <= 0.0:
		_tick = 0.5
		_teams()
	if race.phase != "racing":
		_update_sc(dt)
		return
	_escalate()
	if flag == "red":
		_update_red(dt)
	_update_sc(dt)

func log_rc(text: String, kind := "rc") -> void:
	race.log_event(("Race Control: " if kind == "rc" else "") + text, kind)

func _near_player(c: RaceCar) -> bool:
	var p := race.player
	return absi(c.pos - p.pos) <= 3

static func _short(c: RaceCar) -> String:
	return "you" if c.is_player else Brain.short(c)

## A wrecked car slides to rest; the barriers stop it.
func _slide(c: RaceCar, dt: float) -> void:
	var v := sqrt(c.vx * c.vx + c.vy * c.vy)
	if v < 0.05 and absf(c.yaw_rate) < 0.01:
		c.vx = 0.0
		c.vy = 0.0
		c.yaw_rate = 0.0
		c.v = 0.0
		c.speed = 0.0
		return
	var off := absf(c.d) > track.half + 0.3
	var dec := minf(v, (9.0 if off else 6.5) * dt)
	if v > 0.0:
		c.vx -= c.vx / v * dec
		c.vy -= c.vy / v * dec
	c.x += c.vx * dt
	c.y += c.vy * dt
	c.heading += c.yaw_rate * dt
	c.yaw_rate *= exp(-2.5 * dt)
	var pr := track.project(c.x, c.y, c.s)
	c.s = track.wrap_s(pr[0])
	var lim := track.limits(c.s)
	var d := clampf(pr[1], lim[0], lim[1])
	if d != pr[1]:
		var nx := track.sample(track.NX, c.s)
		var ny := track.sample(track.NY, c.s)
		c.x += nx * (d - pr[1])
		c.y += ny * (d - pr[1])
		var vn := c.vx * nx + c.vy * ny
		if vn * signf(pr[1]) > 0.0:
			c.vx -= nx * vn * 1.3
			c.vy -= ny * vn * 1.3
	c.d = d
	c.v = sqrt(c.vx * c.vx + c.vy * c.vy)
	c.speed = c.v
	c.throttle = 0.0
	c.brake_on = false

func _update_yellows(dt: float) -> void:
	_cause.fill(0)
	_trouble = 0
	_blocking = 0
	var settle := race.phase == "racing" and race.race_time > 8.0
	for c in race.cars:
		if c.finished or c.mode == "pit" or c.recovered or (c.dnf and not c.stranded):
			continue
		var on_track := absf(c.d) < track.half + 0.6
		var lvl := 0
		var trouble := false
		if c.stranded:
			lvl = 2 if on_track else 1
			trouble = true
		elif settle:
			var off := absf(SimUtil.wrap_angle(c.heading - track.heading(c.s)))
			var v := _speed(c)
			if off > 1.0 or (v < 4.0 and not neutral):
				lvl = 2 if on_track else 1
				trouble = off > 1.0 or v < 2.0 # a crawl is a queue, not a wreck
			elif absf(c.d) > track.half + 1.5:
				lvl = 1
			if lvl > 0:
				c.spin_t = race.clock
		if lvl == 0:
			continue
		var k := sector_of(c.s)
		_cause[k] = maxi(_cause[k], lvl)
		# the yellow starts upstream of the car, further back for one on the racing surface
		for j in range(1, (YELLOW_BEHIND if lvl == 2 else 1) + 1):
			var kb := posmod(k - j, n_sec)
			_cause[kb] = maxi(_cause[kb], 1)
		if lvl == 2:
			var ka := (k + 1) % n_sec
			_cause[ka] = maxi(_cause[ka], 1)
		if trouble:
			_trouble += 1
			if on_track:
				_blocking += 1
	if _blocking < PILEUP_SC_CARS:
		_pileup_since = race.clock
	hazard = false
	for k in n_sec:
		if _cause[k] == 2:
			hazard = true
	# a car stranded anywhere: yellow flags all round the circuit, double where it lies
	if _trouble >= PILEUP_CARS and race.phase == "racing":
		if race.clock >= _fcy_until and not _fcy:
			log_rc("Several cars in trouble — yellow flags around the whole circuit", "warn")
			_fcy = true
		_fcy_until = race.clock + PILEUP_HOLD
	var fcy := _stranded() > 0 or race.clock < _fcy_until
	if fcy:
		for k in n_sec:
			_cause[k] = maxi(_cause[k], 1)
		if not _fcy:
			_fcy = true
			log_rc("Yellow flags around the whole circuit — no overtaking, slow down", "warn")
	else:
		_fcy = false
	for k in n_sec:
		var c := _cause[k]
		if c > 0:
			if c == 2 and yellow[k] < 2 and _announced[k] == 0 and flag == "green":
				_announced[k] = 1
				var name := track.sector_name((k + 0.5) * sec_len)
				log_rc("Double yellow flags%s — slow down, no overtaking" % (" at " + name if name != "" else " in sector %d" % (k + 1)), "warn")
			yellow[k] = c
			_hold[k] = 4.0
		elif yellow[k] > 0:
			_hold[k] -= dt
			if _hold[k] <= 0.0:
				yellow[k] = 0
				_announced[k] = 0

## Marshals push the stranded cars away: quickly if they're off the road, under the safety car if not.
func _recover(dt: float) -> void:
	for c in race.cars:
		if not c.stranded or _speed(c) > 0.3:
			continue
		var on_track := absf(c.d) < track.half + 0.6
		if on_track and flag == "green" and race.phase == "racing" and not race.winner:
			continue # waiting for the safety car before anyone walks onto the track
		c.recover_left -= dt
		if c.recover_left <= 0.0:
			c.stranded = false
			c.recovered = true
			if c.is_player or _near_player(c):
				log_rc("The marshals have cleared %s car" % ("your" if c.is_player else _short(c) + "'s"), "info")

func _stranded_on_track() -> int:
	var n := 0
	for c in race.cars:
		if c.stranded and _speed(c) < 0.5 and absf(c.d) < track.half + 0.6:
			n += 1
	return n

func _stranded() -> int:
	var n := 0
	for c in race.cars:
		if c.stranded:
			n += 1
	return n

## Decide whether an accident calls for the safety car or a red flag.
func _escalate() -> void:
	if race.winner:
		_red_reason = ""
		if flag == "sc":
			_sc_in("the race is over")
		return
	while _wrecks.size() and race.clock - _wrecks[0] > 20.0:
		_wrecks.pop_front()
	if flag != "red":
		if _red_reason == "" and _wrecks.size() >= 3:
			_red_reason = "a multi-car accident"
		if _red_reason != "":
			red_flag(_red_reason)
			return
	_red_reason = ""
	if flag == "green" and race.race_time > 2.0:
		var on_track := _stranded_on_track()
		if on_track > 0:
			deploy_sc("car stopped on the track")
		elif _blocking >= PILEUP_SC_CARS and race.clock - _pileup_since >= PILEUP_SC_AFTER:
			deploy_sc("multi-car incident")
		elif _stranded() >= 2:
			deploy_sc("several cars stranded")

# ---------------- safety car ----------------
func deploy_sc(reason: String) -> void:
	flag = "sc"
	sc_state = "waiting"
	sc_since = race.clock
	_announced.fill(1)
	log_rc("SAFETY CAR DEPLOYED (%s) — no overtaking, close up behind the queue" % reason, "warn")
	for c in race.cars:
		c.overtake_t = 0.0
		c.sc_waved = false
		# an almost free pit stop: a crash reshuffles everyone's strategy
		if not _running(c):
			continue
		c.plan_stale = true
		if c.is_player or c.pit_request or race.R - c.lap <= 2:
			continue
		var st = c.plan[c.stint_idx] if c.stint_idx < c.plan.size() else null
		var laps_in := c.lap - c.stint_start_lap
		var worn: bool = c.tyre.wear < 0.55
		var due: bool = st != null and c.stint_idx < c.plan.size() - 1 and laps_in >= st.laps * 0.3
		# the leaders gamble on track position now and then; the rest take the cheap stop
		var gamble: bool = c.pos <= 2 and not worn and race.rng.next() < 0.5
		if (due or worn) and not gamble:
			c.pit_request = true
			c.service = race.default_service(c)
	var p := race.player
	if _running(p) and not p.pit_request and race.player_next_stop_lap() > 0 and race.player_next_stop_lap() - p.lap <= 3:
		log_rc("Strategist: cheap stop under the safety car — press P to box", "box")

func _sc_in(why := "") -> void:
	if flag != "sc":
		return
	flag = "sc_in"
	sc.sc_lights = false
	log_rc("SAFETY CAR IN THIS LAP%s — the leader controls the restart" % (" (%s)" % why if why != "" else ""), "warn")

## Put the safety car on the track at s (d offset), rolling at v.
func _launch_sc(s: float, d: float, v: float, from_pit: bool) -> void:
	sc_state = "out"
	sc_from_pit = from_pit
	sc.s = track.wrap_s(s)
	sc.d = d
	sc.v = v
	sc.lat_v = 0.0
	sc.sc_lights = true
	_place_sc(0.0)
	sc.px = sc.x
	sc.py = sc.y
	sc.ph = sc.heading
	sc.ps = sc.s
	sc.has_prev = true
	# lapped cars between the safety car and the leader are waved past to join the back of the queue
	var lead := _leader()
	for c in race.cars:
		c.sc_waved = false
		if not lead or c == lead or not _running(c):
			continue
		if track.rel(sc.s - c.s) > 0.0 and track.rel(c.s - lead.s) > 0.0:
			c.sc_waved = true

func _place_sc(dd: float) -> void:
	var q := track.pos(sc.s, sc.d)
	sc.x = q[0]
	sc.y = q[1]
	sc.heading = track.heading(sc.s) + atan2(dd, maxf(3.0, sc.v))
	sc.vx = cos(sc.heading) * sc.v
	sc.vy = sin(sc.heading) * sc.v
	sc.speed = sc.v

func _update_sc(dt: float) -> void:
	var cfg := track.cfg
	sc.px = sc.x
	sc.py = sc.y
	sc.ph = sc.heading
	sc.ps = sc.s
	if sc_state == "garage":
		return
	var po := cfg.pit_offset
	if sc_state == "waiting":
		# parked at the end of the pit lane with its lights on
		sc.s = track.wrap_s(track.lane_end)
		sc.d = po + signf(po) * 3.6
		sc.v = 0.0
		sc.sc_lights = true
		_place_sc(0.0)
		if flag == "red":
			return
		var lead := _leader()
		if not lead:
			return
		var g := track.rel(cfg.pit_exit - lead.s) # leader's distance to the pit exit
		if g > 60.0 and g < 220.0:
			_launch_sc(track.lane_end, po, 14.0, true)
			log_rc("The safety car leaves the pit lane ahead of %s" % _short(lead), "info")
		elif (g < -30.0 or g > 220.0 + 26.0 * 30.0) and race.clock - sc_since > 1.5:
			# too far to wait for: a second safety car joins from a service road ahead of the leader
			var s := lead.s + 140.0
			for i in 8:
				var clear := true
				for c in race.cars:
					if not c.dnf and absf(track.rel(c.s - s)) < 18.0:
						clear = false
						break
				if clear:
					break
				s += 25.0
			_launch_sc(s, track.sample(track.RLD, s), minf(_speed(lead), 24.0), false)
			log_rc("The safety car joins ahead of %s" % _short(lead), "info")
		return

	var mu: float = race.tyres.compound_grip("M", race.weather.wet)
	var rl := track.sample(track.RLD, sc.s)
	var p0 := track.rel(sc.s)
	var in_lane := sc_state == "in" or (sc_from_pit and p0 > cfg.pit_entry and p0 < cfg.pit_exit)
	# speed: a steady lap on the racing line, braking in time for what's ahead
	var vT := SC_VMAX
	var x := 0.0
	while x < 150.0:
		var va := track.sample(track.PROF, sc.s + x) * sqrt(mu) * SC_PACE
		vT = minf(vT, sqrt(va * va + 2.0 * 3.5 * x))
		x += 10.0
	if flag == "red":
		vT = minf(vT, track.sample(track.PROF, sc.s) * sqrt(mu) * RED_PACE)
	# don't run away from the queue while it's still forming
	var lead := _leader()
	if lead and flag == "sc" and not lead.sc_waved:
		var gap := track.rel(sc.s - lead.s)
		if gap > 50.0 and gap < 2000.0 and lead.mode == "race":
			vT *= clampf(1.0 - (gap - 50.0) / 400.0, 0.6, 1.0)
	var dT := rl
	if in_lane:
		dT = rl + (po - rl) * track.pit_blend(sc.s)
		if sc_state == "in" or p0 < cfg.pit_exit and p0 > track.lane_start:
			vT = minf(vT, Strategy.PIT_SPEED)
	sc.v = maxf(0.0, sc.v + clampf(vT - sc.v, -6.0 * dt, 2.8 * dt))
	sc.brake_on = vT < sc.v - 1.0
	sc.throttle = 0.6 if vT > sc.v else 0.0
	var want := clampf((dT - sc.d) * 2.0, -3.0, 3.0)
	sc.lat_v += clampf(want - sc.lat_v, -6.0 * dt, 6.0 * dt)
	sc.d += sc.lat_v * dt
	var before := track.rel(sc.s)
	sc.s = track.wrap_s(sc.s + sc.v * dt * track.s_rate(sc.s, sc.d))
	var after := track.rel(sc.s)
	_place_sc(sc.lat_v)
	if sc_from_pit and before < cfg.pit_exit and after >= cfg.pit_exit:
		sc_from_pit = false
	# into the pit lane when it's called in (or when the race is stopped)
	if sc_state == "out" and (flag == "sc_in" or flag == "red") and before < cfg.pit_entry and after >= cfg.pit_entry and after - before < 60.0:
		sc_state = "in"
	if sc_state == "in" and after > track.lane_start + 30.0 and after < cfg.pit_exit:
		sc_state = "garage"
		sc.sc_lights = false
		sc.v = 0.0
		return
	# ready to come in: track clear, it has been out long enough and the queue has formed behind it
	if flag == "sc" and sc_state == "out" and _stranded_on_track() == 0 and race.clock - sc_since > SC_MIN_TIME:
		var formed := lead != null and (track.rel(sc.s - lead.s) < 100.0 or race.clock - sc_since > SC_MIN_TIME + 60.0)
		# far enough before the pit entry to announce it, and not already past it on this lap
		var to_entry := track.wrap_s(cfg.pit_entry - sc.s)
		var lane := track.wrap_s(cfg.pit_exit - cfg.pit_entry)
		var margin := 150.0 if track.L < 2500.0 else 500.0
		var in_pits := false
		for c in race.cars:
			if c.mode == "pit" and c.pit and c.pit.phase == "red":
				in_pits = true
		if formed and not in_pits and to_entry > margin and to_entry < track.L - lane:
			_sc_in()

## A car crossed the line: the first one across after the safety car has pulled in restarts the race.
func on_line(car: RaceCar) -> void:
	# a car crossing the line in the pit lane counts too: when the whole field boxes at the end of the
	# safety car's lap, waiting for one on the track left the race neutralised for a whole extra lap
	if flag == "sc_in" and (sc_state == "in" or sc_state == "garage") and not car.dnf:
		flag = "green"
		green_t = race.clock
		_announced.fill(0)
		for c in race.cars:
			c.sc_waved = false
		log_rc("GREEN FLAG — racing resumes!", "good")

# ---------------- red flag ----------------
func red_flag(reason: String) -> void:
	flag = "red"
	red_state = "slowing"
	red_t = 0.0
	_red_reason = ""
	_announced.fill(1)
	if sc_state == "garage":
		sc_state = "waiting"
	log_rc("RED FLAG — race suspended (%s). Slow down and return to the pit lane" % reason, "bad")
	for c in race.cars:
		c.overtake_t = 0.0
		c.sc_waved = false

## Where the queue of cars stops in the pit lane under a red flag (track-relative distance).
var red_stop: float:
	get: return track.lane_end - 6.0

func _update_red(dt: float) -> void:
	red_t += dt
	for c in race.cars:
		if c.mode == "pit" and c.pit and c.pit.phase == "out" and track.rel(c.s) < red_stop - 2.0:
			c.pit.phase = "red"
	if red_state == "slowing":
		var all_in := true
		for c in race.cars:
			if c.dnf or c.finished:
				continue
			if c.mode != "pit" or c.pit.phase != "red" or c.v > 0.3:
				all_in = false
				break
		if all_in or red_t > 420.0:
			red_state = "suspended"
			red_t = 0.0
			_suspend_work()
	elif red_state == "suspended" and red_t >= RED_SUSPEND:
		_restart()

## During the suspension: the marshals clear every wreck and repair the barriers, the crews fix damage
## and may fit fresh tyres for the conditions.
func _suspend_work() -> void:
	var wet := race.weather.wet
	for c in race.cars:
		if c.stranded:
			c.stranded = false
			c.recovered = true
		if c.dnf or c.finished or c.mode != "pit":
			continue
		repaired(c)
		var cur: String = c.tyre.c
		var want := cur
		if cur != "W" and wet > c.wet_threshold:
			want = "W"
		elif cur == "W" and wet < 0.18:
			var nxt = c.plan[c.stint_idx + 1] if c.stint_idx + 1 < c.plan.size() else null
			want = nxt.c if nxt and nxt.c != "W" else "M"
		c.tyre = {"c": want, "wear": 1.0, "temp": 0.5}
		c.used_mask |= Tyres.compound_bit(want)
		if want != cur:
			c.history.append(want)
		c.plan_stale = true
	yellow.fill(0)
	_hold.fill(0.0)
	log_rc("The race is suspended — crews may repair the cars and change tyres. Restart behind the safety car in %d s" % int(RED_SUSPEND), "warn")

func _restart() -> void:
	red_state = ""
	flag = "sc"
	sc_since = race.clock
	_launch_sc(track.lane_end + 4.0, track.cfg.pit_offset, 10.0, true)
	# the queue leaves in order, one car every 1.5 s, so nobody rejoins on top of the car ahead
	var queue: Array = []
	for c in race.cars:
		if c.mode == "pit" and c.pit and c.pit.phase == "red":
			queue.append(c)
	queue.sort_custom(func(a, b): return track.rel(a.s) > track.rel(b.s))
	for k in queue.size():
		var c: RaceCar = queue[k]
		c.pit.phase = "out"
		c.pit.wait = 10.0 # nobody to give way to: the whole field leaves in its queue
		c.pit.go = race.race_time + 1.0 + 1.5 * k
	log_rc("The race resumes behind the safety car — follow it out of the pit lane", "warn")

# ---------------- AI behaviour under flags ----------------
## Adjust a bot's speed and line target for the flags: slower in yellow sectors, a queue behind the
## safety car, and a slow in-lap under a red flag.
func limit_speed(car: RaceCar, t: Dictionary, mu: float) -> void:
	var lvl := maxi(yellow_at(car.s), yellow_at(car.s + 60.0))
	var vT: float = t.vT
	if lvl > 0:
		vT *= YELLOW_PACE[lvl]
	elif hazard and not neutral:
		vT *= HAZARD_PACE # the whole field lifts while a car is stopped on the track, the leader included
	if neutral:
		var pace := RED_PACE if flag == "red" else DELTA_PACE
		var v_race := vT
		var v_prof := track.sample(track.PROF, car.s + car.v * 0.12) * sqrt(mu)
		vT = minf(vT, track.sample(track.PROF, car.s + car.v * 0.12) * sqrt(mu) * pace)
		# close up to whatever is physically ahead: the safety car or the next car in the queue
		var ahead := _queue_ahead(car)
		var gap: float = ahead[0]
		var v_ahead: float = ahead[1]
		if gap < 4000.0:
			# close up to about half a second behind, braking for the car ahead at a steady 2.5 m/s² near
			# it so the queue can concertina through the braking zones, and twice as late while well back
			# (otherwise every follower lifts the moment the car ahead does and the gap never closes)
			var want := SC_GAP + 0.5 * _speed(car)
			if gap > want:
				if flag != "red" and gap > want + CATCHUP_GAP:
					# off the back of the queue: hurry up to it at nearly racing speed
					vT = maxf(vT, minf(v_race, v_prof * CATCHUP_PACE))
				var room := 2.0 * 2.5 * ((gap - want) + maxf(0.0, gap - want - 15.0))
				vT = minf(vT, sqrt(v_ahead * v_ahead + room))
			else:
				vT = minf(vT, maxf(0.0, v_ahead - (want - gap) * 0.5))
		if car.sc_waved and sc_on_track:
			var g := track.rel(sc.s - car.s)
			if g < -8.0:
				car.sc_waved = false
			elif g < 45.0:
				var lim := track.half - 1.0
				t.dT = clampf(sc.d + (2.8 if sc.d < 0.0 else -2.8), -lim, lim)
	t.vT = vT

## [gap, speed] to whatever is physically ahead of this car under a neutralisation: the safety car or
## the next running car; gap is INF when there is nothing.
func _queue_ahead(car: RaceCar) -> Array:
	var gap := INF
	var v_ahead := 0.0
	for o in race.cars:
		if o == car or o.dnf or o.mode == "pit":
			continue
		var g := track.rel(o.s - car.s)
		if g > 0.0 and g < gap:
			gap = g
			v_ahead = _speed(o)
	if sc_on_track and not car.sc_waved:
		var g := track.rel(sc.s - car.s)
		if g > 0.0 and g < gap:
			gap = g
			v_ahead = sc.v
	return [gap, v_ahead]

# ---------------- the player's obligations ----------------
## A car lies on the racing surface within reach ahead of (or just alongside) this position.
func _blocked_ahead(s: float) -> bool:
	for c in race.cars:
		if c.stranded and absf(c.d) < track.half + 1.0:
			var g := track.rel(c.s - s)
			if g > -40.0 and g < 260.0:
				return true
	return false

## Share of the racing line's speed limit the player may use right now, or 0 when nothing limits them.
func _cap_frac(p: RaceCar) -> float:
	if flag == "red":
		return RED_PACE + 0.1
	if neutral:
		if _queue_ahead(p)[0] > SC_GAP + 0.5 * _speed(p) + CATCHUP_GAP + 20.0:
			return CATCHUP_PACE + 0.05 # catching the queue
		return DELTA_PACE + 0.08
	if yellow_at(p.s) == 2:
		return PLAYER_SLOW
	return 0.0

## The fastest the player may go right now (m/s), or 0 when nothing limits them.
func speed_cap(p: RaceCar) -> float:
	var frac := _cap_frac(p)
	if frac <= 0.0:
		return 0.0
	var mu: float = race.tyres.tyre_grip(p.tyre, race.weather.wet)
	return track.sample(track.PROF, p.s) * sqrt(mu) * frac

## What the V limiter holds the car to: the flag speed cap, brought down early enough for the slower
## stretches ahead, and under a neutralisation never faster than lets the car stop short of the one in front
## (so full throttle behind the safety car closes up to the queue instead of through it).
func limiter_cap(p: RaceCar) -> float:
	var frac := _cap_frac(p)
	if frac <= 0.0:
		return 0.0
	var mu: float = race.tyres.tyre_grip(p.tyre, race.weather.wet)
	var root := sqrt(mu) * frac
	var cap := track.sample(track.PROF, p.s) * root
	var x := 10.0
	while x <= LIMITER_LOOK:
		var va: float = track.sample(track.PROF, p.s + x) * root
		cap = minf(cap, sqrt(va * va + 2.0 * LIMITER_DECEL * x))
		x += 10.0
	if neutral:
		var ahead := _queue_ahead(p)
		var gap: float = ahead[0]
		if gap < INF:
			var v_ahead: float = ahead[1]
			if gap > LIMITER_GAP:
				cap = minf(cap, sqrt(v_ahead * v_ahead + 2.0 * LIMITER_DECEL * (gap - LIMITER_GAP)))
			else:
				cap = minf(cap, maxf(0.0, v_ahead - (LIMITER_GAP - gap) * 0.5))
	return cap

func _player_rules(dt: float) -> void:
	var p := race.player
	var driving := race.phase == "racing" and _running(p) and p.control == "free"
	if not driving:
		_gaps.clear()
		_over_t = 0.0
		return
	var why := ""
	if flag == "red":
		why = "under the red flag"
	elif neutral:
		why = "under the safety car"
	# overtakes in a flagged zone must be handed back
	for o in race.cars:
		if o == p or not _running(o):
			_gaps.erase(o)
			continue
		var g := track.rel(o.s - p.s)
		if absf(g) > 30.0:
			_gaps.erase(o)
			continue
		var prev = _gaps.get(o)
		_gaps[o] = g
		if prev == null:
			continue
		if prev > 0.0 and g <= 0.0:
			var w := why
			if w == "" and (yellow_at(p.s) > 0 or yellow_at(o.s) > 0):
				w = "under yellow flags"
			var fair := o.sc_waved or o.stranded or _speed(o) < 8.0 or race.clock - o.spin_t < 3.0 or absf(o.d) > track.half + 0.5
			# steering round a wreck or a limping car is not overtaking
			fair = fair or _blocked_ahead(p.s) or (o.damage >= REPAIR_AT and _speed(o) < _speed(p) * 0.75)
			if w != "" and not fair:
				give_back.append({"car": o, "until": race.clock + GIVE_BACK, "why": w})
				log_rc("You passed %s %s — give the place back" % [_short(o), w], "rc")
		elif prev < 0.0 and g >= 0.0:
			for i in range(give_back.size() - 1, -1, -1):
				if give_back[i].car == o:
					give_back.remove_at(i)
					log_rc("Place given back to %s — no further action" % _short(o), "rc")
	for i in range(give_back.size() - 1, -1, -1):
		var gb: Dictionary = give_back[i]
		if not _running(gb.car):
			give_back.remove_at(i)
		elif race.clock > gb.until:
			give_back.remove_at(i)
			penalise(p, 5, "overtaking %s %s" % [_short(gb.car), gb.why])
	# slow down under double yellows, and keep to the safety-car delta
	var lim := speed_cap(p)
	# picking a way past a wreck gets some leeway
	if lim <= 0.0 or _speed(p) <= (lim * 1.25 if _blocked_ahead(p.s) else lim) + 1.0:
		# back under the limit: the time over it drains away, so a moment over the delta at each braking
		# zone of a long safety-car period does not add up to a penalty
		_over_t = maxf(0.0, _over_t - dt * 0.5)
		if _over_t == 0.0:
			_over_warned = false
	else:
		_over_t += dt
		if _over_t > 1.5 and not _over_warned:
			_over_warned = true
			log_rc("Too fast %s — slow down" % ("under double yellows" if not neutral else ("under the red flag" if flag == "red" else "for the safety-car delta")), "rc")
		if _over_t > 4.0:
			_over_t = 0.0
			_over_warned = false
			penalise(p, 5, "not slowing %s" % ("for double yellow flags" if not neutral else ("under the red flag" if flag == "red" else "to the safety-car delta")))

## Pit wall: call damaged cars in for repairs.
func _teams() -> void:
	for c in race.cars:
		if not _running(c) or c.repair_asked or c.damage < REPAIR_AT or flag == "red":
			continue
		if race.R - c.lap <= 1 and not race.timed:
			continue
		c.repair_asked = true
		if not c.is_player:
			c.pit_request = true
			c.service = race.default_service(c)
			continue
		if race.s.auto_strategist or c.autopilot:
			c.pit_request = true
			c.service = race.default_service(c)
			log_rc("Strategist: box this lap for repairs (damage %d%%, ≈%.0f s)" % [roundi(c.damage * 100.0), repair_time(c)], "box")
		else:
			log_rc("Strategist: damage %d%% — press P to box for repairs (≈%.0f s)" % [roundi(c.damage * 100.0), repair_time(c)], "box")

# ---------------- HUD ----------------
## What the flag panel shows the player: {title, sub, color, text_color} or {} for nothing.
func player_flag() -> Dictionary:
	var f := _player_flag()
	var p := race.player
	if not f.is_empty() and p.control == "free" and not p.autopilot and speed_cap(p) > 0.0:
		f["sub"] = "%s · V limiter %s" % [f.sub, "ON" if race.limiter else "off"]
	return f

func _player_flag() -> Dictionary:
	var p := race.player
	if flag == "red":
		var sub := "Slow down and enter the pit lane"
		if red_state == "suspended":
			sub = "Race suspended · restart in %d s" % ceili(RED_SUSPEND - red_t)
		elif p.mode == "pit":
			sub = "Race suspended · wait in the pit lane"
		return {"title": "RED FLAG", "sub": sub, "color": Color("#d81e1e"), "ink": Color.WHITE}
	if not give_back.is_empty():
		var gb: Dictionary = give_back[0]
		return {"title": "GIVE THE PLACE BACK", "sub": "Let %s by · %d s" % [_short(gb.car), ceili(gb.until - race.clock)], "color": Color("#1a1a1a"), "ink": Color.WHITE}
	if flag == "sc":
		var sub := "No overtaking · close up to the queue" if sc_state != "waiting" else "Safety car deployed · no overtaking"
		return {"title": "SAFETY CAR", "sub": sub, "color": Color("#ffd21a"), "ink": Color.BLACK}
	if flag == "sc_in":
		return {"title": "SAFETY CAR IN", "sub": "Restart at the line · no overtaking until then", "color": Color("#ffd21a"), "ink": Color.BLACK}
	if p.dnf or p.finished or p.mode == "pit":
		return {}
	var lvl := maxi(yellow_at(p.s), yellow_at(p.s + 120.0))
	if lvl == 2:
		return {"title": "DOUBLE YELLOW", "sub": "Slow down, be ready to stop · no overtaking", "color": Color("#ffd21a"), "ink": Color.BLACK}
	if lvl == 1:
		return {"title": "YELLOW FLAG", "sub": "Danger ahead · no overtaking", "color": Color("#ffd21a"), "ink": Color.BLACK}
	if race.clock - green_t < 4.0:
		return {"title": "GREEN FLAG", "sub": "Racing resumes", "color": Color("#1fae4b"), "ink": Color.WHITE}
	return {}
