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
