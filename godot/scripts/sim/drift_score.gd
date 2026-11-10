## Drift points for a campaign drift mission (RaceSettings.drift_score): the open world's drift skill made into a
## score attack. While the car slides on the road (slip angle between ANGLE_MIN and ANGLE_MAX, above SPEED_MIN) it
## earns speed (km/h) x slip angle (rad) x RATE points a second into the running combo; every second a slide is
## held, and every new slide linked within LINK s of the last, raises the combo's multiplier (up to MULT_MAX). The
## combo banks into the score once the car has driven LINK s without sliding (or at the finish), and it is lost if
## the car hits something or leaves the road first.
class_name DriftScore
extends RefCounted

const ANGLE_MIN := 0.26 ## rad (15 degrees): less is just a tidy corner
const ANGLE_MAX := 1.9 ## rad: more is a spin, which scores nothing (and ends the slide)
const SPEED_MIN := 8.0 ## m/s
const RATE := 6.0 ## points per (km/h x rad) per second, as the open world's skill chain pays
const LINK := 2.6 ## s without a slide before the combo banks (OpenWorld.CHAIN_IDLE)
const MULT_STEP := 1.0 / 3.0 ## multiplier gained per held second or linked slide
const MULT_MAX := 5.0
const OFF_ROAD := 0.8 ## m beyond the road edge that counts as off (the combo is lost)
const HIT_MIN := 5.0 ## m/s of impact that counts as a crash

var score := 0 ## banked points
var tiers: Array = [] ## [bronze, silver, gold] points (the mission's; empty: none)
var combo := 0.0 ## points in the running combo, before the multiplier
var mult := 1.0
var best_combo := 0 ## the biggest banked combo (points x multiplier)
var drifting := false ## sliding this tick
var slide_t := 0.0 ## s the current slide has lasted
var angle := 0.0 ## the current slip angle, rad
var idle := 0.0 ## s since the last slide
var lost := 0 ## combos lost to a crash or the verge
var last_event := "" ## "BANKED", "LOST", "" (for the HUD's flash)
var event_t := -99.0 ## when last_event happened (race clock)
var event_points := 0
var _links := 0
var _paid := 0
var _hit_seen := 0.0

## The combo as it would bank now.
func pending() -> int:
	return int(combo * mult)

## The score with the running combo banked: what a finish now would give.
func total() -> int:
	return score + pending()

## One race tick for the player's car.
func tick(race: Race, car: RaceCar, dt: float) -> void:
	if car == null or car.finished or car.dnf:
		if combo > 0.0 and car != null and car.finished:
			bank(race.clock)
		return
	var crash := car.last_hit > _hit_seen
	_hit_seen = car.last_hit
	var off := absf(car.d) > race.track.half + OFF_ROAD
	var v := sqrt(car.vx * car.vx + car.vy * car.vy) if car.control == "free" else 0.0
	step(v, _slip(car), off, crash, dt, race.clock)

## The scoring itself, free of the race (unit tests drive it directly): v m/s, slip rad, whether the car is off
## the road or crashed this tick.
func step(v: float, slip: float, off: bool, crash: bool, dt: float, now := 0.0) -> void:
	angle = slip
	if crash or off:
		if combo > 0.0:
			lost += 1
			_event("LOST", pending(), now)
		combo = 0.0
		mult = 1.0
		_links = 0
		drifting = false
		slide_t = 0.0
		_paid = 0
		idle = LINK # nothing to link to
		return
	drifting = v > SPEED_MIN and slip > ANGLE_MIN and slip < ANGLE_MAX
	if drifting:
		if slide_t == 0.0 and combo > 0.0 and idle < LINK:
			_links += 1 # a new slide linked to the last
		slide_t += dt
		idle = 0.0
		combo += dt * v * 3.6 * slip * RATE
		if int(slide_t) > _paid:
			_paid = int(slide_t) # every held second raises the multiplier
			_links += 1
		mult = minf(MULT_MAX, 1.0 + _links * MULT_STEP)
	else:
		slide_t = 0.0
		_paid = 0
		idle += dt
		if combo > 0.0 and idle >= LINK:
			bank(now)

func bank(now := 0.0) -> void:
	var pts := pending()
	if pts > 0:
		score += pts
		best_combo = maxi(best_combo, pts)
		_event("BANKED", pts, now)
	combo = 0.0
	mult = 1.0
	_links = 0

func _event(kind: String, pts: int, now: float) -> void:
	last_event = kind
	event_points = pts
	event_t = now

## The angle between where the car points and where it is going, rad (0 when nearly stopped).
static func _slip(car: RaceCar) -> float:
	var v2 := car.vx * car.vx + car.vy * car.vy
	if v2 < 1.0 or car.control != "free":
		return 0.0
	return absf(wrapf(atan2(car.vy, car.vx) - car.heading, -PI, PI))

## The tier a score reaches against [bronze, silver, gold]: 0 none, 1 bronze, 2 silver, 3 gold.
static func tier(points: int, tiers: Array) -> int:
	var t := 0
	for i in tiers.size():
		if points >= int(tiers[i]):
			t = i + 1
	return t

const TIER_NAMES := ["", "BRONZE", "SILVER", "GOLD"]
