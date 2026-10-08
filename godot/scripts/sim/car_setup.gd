## A car set-up, after Colin McRae Rally 2.0's: five settings, each on a five-notch scale from -2 to +2 with the
## stock Seicento in the middle. apply() turns a set-up into the CarSpec a car drives on (Race.fit_setup). The
## player's is kept per circuit, as CMR kept one per stage; each bot runs its driver's (Drivers.ROSTER). A set-up
## of all zeros is the stock spec exactly, so the physics parity with the JS reference is untouched. Set-ups act
## in the full physics only: on the rail model (time warp, bot physics off) every car runs the stock figures.
class_name CarSetup
extends RefCounted

const NOTCHES := 2 ## each setting runs -NOTCHES .. +NOTCHES
## (No gear ratios: the stock Seicento is geared to its power peak, and ±10 % on the final drive moved
## 0–100 km/h by a tenth and the top speed by under 1 km/h, so a slider for it would do nothing.)
## setting -> [name on the page, left end, right end, what it does]
const SETTINGS := {
	"brakes": ["BRAKE BALANCE", "FRONT", "REAR",
		"More rear brake helps the car turn in on the brakes, but the rear wheels lock first and the tail steps out."],
	"springs": ["SPRINGS", "SOFT", "HARD",
		"Hard springs make the weight shift quicker, so the car answers the wheel sooner but is snappier at the limit."],
	"roll": ["ANTI-ROLL BALANCE", "FRONT", "REAR",
		"Stiffer at the front the car understeers and is safe; stiffer at the rear it turns in and can oversteer."],
	"height": ["RIDE HEIGHT", "LOW", "HIGH",
		"A low car has less weight transfer and drag on the circuit, but digs into grass and gravel off it."],
	"steering": ["STEERING", "SLOW", "QUICK",
		"Quick steering gives more lock for the same input at speed: sharper, but easier to overdo."],
}

## Every setting at its stock notch.
static func stock() -> Dictionary:
	var out := {}
	for key in SETTINGS:
		out[key] = 0
	return out

## A set-up read from a save: known settings only, whole notches in range, stock for anything missing.
static func clean(setup) -> Dictionary:
	var out := stock()
	if setup is Dictionary:
		for key in SETTINGS:
			if setup.has(key):
				out[key] = clampi(int(setup[key]), -NOTCHES, NOTCHES)
	return out

static func is_stock(setup: Dictionary) -> bool:
	for key in SETTINGS:
		if int(setup.get(key, 0)) != 0:
			return false
	return true

## A copy of base with the set-up applied (base itself when the set-up is stock).
static func apply(base: CarSpec, setup: Dictionary) -> CarSpec:
	var st := clean(setup)
	if is_stock(st):
		return base
	var spec: CarSpec = base.duplicate()
	var b: int = st.brakes
	spec.brake_front = base.brake_front * (1.0 - 0.04 * b)
	spec.brake_rear = base.brake_rear * (1.0 + 0.4 * b)
	var k: int = st.springs
	spec.susp_hz = base.susp_hz * (1.0 + 0.12 * k)
	spec.susp_zeta = base.susp_zeta * (1.0 - 0.06 * k) # stiffer springs on the same dampers are less damped
	spec.roll_gradient = base.roll_gradient * (1.0 - 0.15 * k)
	spec.pitch_gradient = base.pitch_gradient * (1.0 - 0.15 * k)
	spec.roll_front = base.roll_front - 0.05 * st.roll
	var hgt: int = st.height
	spec.cg_height = base.cg_height + 0.02 * hgt
	spec.cd_a = base.cd_a * (1.0 + 0.025 * hgt)
	spec.lift_a = base.lift_a * (1.0 + 0.2 * hgt)
	spec.offroad_drag = 1.0 - 0.3 * hgt
	spec.steer_gain = 1.0 + 0.08 * st.steering
	return spec
