## The car's parts and the service area between championship rounds, after Colin McRae Rally 2.0: race
## control's damage (RaceCar.damage, which costs power, drag and a steering pull) is broken down into the
## parts that took it, depending on where the car was hit, and the crew has a 60-minute allocation to
## put them right before the next round. Whatever they don't get to is still bent at the start.
class_name Service
extends RefCounted

const ALLOCATION := 60 ## minutes of service between rounds
## part -> [share of the car's total damage it holds when fully broken, minutes to repair it from 100 %,
##          what breaks]. The shares add up to 1, so damage = Σ share × severity. The car drives on the
## total (less power, more drag, a steering pull); the parts say where it is and what fixing it costs.
const PARTS := {
	"Body": [0.34, 30, "Bent panels and a twisted shell: the car pushes more air and sits crooked."],
	"Suspension": [0.2, 16, "Bent arms, struts and wheel bearings: the main cause of the car pulling to one side."],
	"Steering": [0.12, 12, "A bent track rod or a knocked rack: the wheel is no longer straight when the car is."],
	"Engine": [0.1, 24, "A holed radiator, a cracked sump guard and damaged ancillaries: the engine down on power."],
	"Gearbox": [0.06, 20, "Mountings and the gear linkage knocked out of line by a hit from behind."],
	"Brakes": [0.06, 8, "Bent brake lines, a damaged disc and a caliper knocked out of true."],
	"Exhaust": [0.05, 6, "A crushed tailpipe and silencer, choking the little 899 cc engine."],
	"Electrics": [0.07, 6, "Smashed lamp units and torn wiring looms."],
}
## Where a hit goes, by where the car was struck: part -> weight (each zone's weights add up to 1).
const ZONES := {
	"front": {"Body": 0.34, "Engine": 0.2, "Steering": 0.14, "Suspension": 0.14, "Electrics": 0.12, "Brakes": 0.06},
	"side": {"Body": 0.44, "Suspension": 0.3, "Steering": 0.14, "Brakes": 0.06, "Electrics": 0.06},
	"rear": {"Body": 0.4, "Exhaust": 0.24, "Suspension": 0.14, "Gearbox": 0.12, "Electrics": 0.1},
}

## The zone of a hit whose direction from the car's centre makes cosine f with its heading.
static func zone(f: float) -> String:
	return "front" if f > 0.5 else ("rear" if f < -0.5 else "side")

## Spreads add (the rise in car.damage from one impact) over the parts in the hit zone.
static func spread(car: RaceCar, add: float, f: float) -> void:
	var weights: Dictionary = ZONES[zone(f)]
	for part in weights:
		var share: float = PARTS[part][0]
		car.parts[part] = minf(1.0, float(car.parts.get(part, 0.0)) + add * weights[part] / share)
	sync(car)

## The total damage the parts make up (what RaceCar.damage starts a race at).
static func total(parts: Dictionary) -> float:
	var sum := 0.0
	for part in parts:
		if PARTS.has(part):
			sum += PARTS[part][0] * clampf(float(parts[part]), 0.0, 1.0)
	return minf(sum, 0.95)

## Minutes to repair a part at severity sev (0..1): whole minutes, at least one for any real damage.
static func minutes(part: String, sev: float) -> int:
	if sev < 0.01:
		return 0
	return maxi(1, ceili(sev * PARTS[part][1]))

## Gives a car the parts it carries over (a championship round starting with last round's damage).
## pull is the steering pull per unit of bent suspension and steering (pull_rate), so it keeps its side and
## shrinks with what the crew straightened.
static func fit(car: RaceCar, parts: Dictionary, pull: float) -> void:
	car.parts = {}
	for part in parts:
		if PARTS.has(part) and float(parts[part]) > 0.0:
			car.parts[part] = clampf(float(parts[part]), 0.0, 1.0)
	car.damage = total(car.parts)
	sync(car)
	car.dmg_pull = clampf(pull * _bent(car.parts), -0.05, 0.05)

## The car's steering pull per unit of bent suspension and steering, for fit.
static func pull_rate(car: RaceCar) -> float:
	return car.dmg_pull / maxf(0.1, _bent(car.parts))

static func _bent(parts: Dictionary) -> float:
	return (float(parts.get("Suspension", 0.0)) + float(parts.get("Steering", 0.0))) * 0.5

## The parts as they stand, for saving: {part: severity} of everything damaged.
static func snapshot(car: RaceCar) -> Dictionary:
	var out := {}
	for part in car.parts:
		if float(car.parts[part]) >= 0.01:
			out[part] = snappedf(float(car.parts[part]), 0.001)
	return out

# ---------------- what each damaged part does to the car ----------------
## On top of the total's power, drag and pull (race.gd), every part breaks its own system. All of it sits
## behind RaceCar.fx_on, which only a damaged part sets, so an undamaged car drives exactly as before.
const MISFIRE_FROM := 0.15 ## engine damage below this runs smoothly, just down on power
const LOST_GEAR_FROM := 0.7 ## gearbox damage from which top gear is gone
const MISSED_SHIFT_FROM := 0.4 ## gearbox damage from which some shifts fail and have to be tried again

## Works out the car's per-part factors (RaceCar.fx_*) from its parts. Call after car.parts changes.
static func sync(car: RaceCar) -> void:
	var p := car.parts
	var eng := _sev(p, "Engine")
	var exh := _sev(p, "Exhaust")
	car.fx_power = 1.0 - 0.25 * eng - 0.08 * exh
	car.fx_brake = 1.0 - 0.4 * _sev(p, "Brakes")
	car.fx_grip = 1.0 - 0.1 * _sev(p, "Suspension")
	car.fx_drag = 1.0 + 0.25 * _sev(p, "Body")
	car.fx_on = false
	for part in p:
		if float(p[part]) > 0.0:
			car.fx_on = true
	if not car.fx_on:
		car.fx_power = 1.0
		car.fx_brake = 1.0
		car.fx_grip = 1.0
		car.fx_drag = 1.0

static func _sev(parts: Dictionary, part: String) -> float:
	return clampf(float(parts.get(part, 0.0)), 0.0, 1.0)

## Engine: down on power, and from MISFIRE_FROM on it misfires under load (the throttle cuts out for a few
## hundredths of a second, more often the worse it is). Deterministic in the race clock, so replays agree.
static func misfire(car: RaceCar, clock: float, thr: float) -> float:
	thr *= car.fx_power
	var eng := _sev(car.parts, "Engine")
	if eng >= MISFIRE_FROM and thr > 0.3:
		var rate := 0.4 + 2.2 * eng # misfires a second
		if fposmod(clock * rate + car.id * 0.37, 1.0) < 0.07 * rate:
			thr *= 0.15
	return thr

## Steering and brakes on the wheel: a bent rack is vague about the centre and sits off straight; damaged
## brakes pull the car to one side under braking (the side the suspension already pulls to).
static func steer_feel(car: RaceCar, steer: float, brk: float) -> float:
	var side := 1.0 if car.dmg_pull >= 0.0 else -1.0
	var st := _sev(car.parts, "Steering")
	if st > 0.0:
		var dead := 0.05 * st
		steer = signf(steer) * maxf(0.0, absf(steer) - dead) + side * 0.02 * st
	var br := _sev(car.parts, "Brakes")
	if br > 0.0:
		steer += side * 0.06 * br * brk
	return clampf(steer, -1.0, 1.0)

## Gearbox: every shift takes longer, from MISSED_SHIFT_FROM some shifts don't go in at the first try, and
## from LOST_GEAR_FROM top gear is gone. top is the highest gear index. Call after the shift was asked for.
static func gearbox(car: RaceCar, top: int, clock: float) -> void:
	var gb := _sev(car.parts, "Gearbox")
	if gb <= 0.0:
		car.fx_gear = car.gear
		return
	if car.fx_gear >= 0 and car.gear != car.fx_gear:
		if gb >= MISSED_SHIFT_FROM and fposmod(clock * 7.3 + car.id * 0.61, 1.0) < 0.5 * gb:
			car.gear = car.fx_gear # missed: still in the old gear, try again in a moment
			car.shift_t = maxf(car.shift_t, 0.35)
		else:
			car.shift_t += 0.3 * gb
	if gb >= LOST_GEAR_FROM and car.gear >= top:
		car.gear = top - 1
	car.fx_gear = car.gear

## Gearbox damage has taken top gear away (gearbox).
static func top_gear_lost(car: RaceCar) -> bool:
	return _sev(car.parts, "Gearbox") >= LOST_GEAR_FROM

## Electrics: the headlights' brightness factor (dim, and flickering when badly damaged). 1 when fine.
static func lamp(car: RaceCar, clock: float) -> float:
	var el := _sev(car.parts, "Electrics")
	if el <= 0.0:
		return 1.0
	var level := 1.0 - 0.6 * el
	if el >= 0.3 and fposmod(clock * (2.0 + 6.0 * el) + car.id * 0.29, 1.0) < 0.25 * el:
		level *= 0.1
	return level

## What a part at severity sev (0..1) will do to the car in the next race, in plain words.
static func symptom(part: String, sev: float) -> String:
	if sev < 0.01:
		return "In working order."
	var pct := roundi(sev * 100.0)
	match part:
		"Engine":
			return "About %d%% down on power%s." % [roundi(sev * 25.0) + 1, " and it misfires under load" if sev >= MISFIRE_FROM else ""]
		"Gearbox":
			var out := "Every gear change is slower"
			if sev >= MISSED_SHIFT_FROM:
				out += ", some shifts won't go in first time"
			if sev >= LOST_GEAR_FROM:
				out += ", and top gear is gone"
			return out + "."
		"Brakes":
			return "Stopping distances about %d%% longer, and the car pulls to one side under braking." % roundi(100.0 / maxf(0.2, 1.0 - 0.4 * sev) - 100.0)
		"Suspension":
			return "Less grip in the corners (about %d%%) and the car pulls to one side." % maxi(1, roundi(sev * 10.0))
		"Steering":
			return "The wheel is vague around the centre and sits off straight."
		"Body":
			return "Bent panels add drag: lower top speed (%d%% more drag)." % maxi(1, roundi(sev * 25.0))
		"Exhaust":
			return "A little down on power and much louder."
		"Electrics":
			return "The headlights are dim%s: hard going at night." % (" and flicker" if sev >= 0.3 else "")
	return "%d%% damaged." % pct
