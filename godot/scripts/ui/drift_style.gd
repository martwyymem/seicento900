## What a drift looks like, shared by the races (RaceWorld, RaceHud, RaceCarVisual) and the open world: the slip
## angle, how much of a drift it is (0..1, for the smoke, the skid marks and the camera), the chase camera's swing
## out to the car's side and its roll, and the label a banked drift combo earns (DriftMeter's popup).
## Presentation only: nothing here feeds the physics or the race sim.
class_name DriftStyle
extends RefCounted

const ANGLE_START := 0.12 ## rad of slip where a drift starts to show
const ANGLE_FULL := 0.45 ## rad more than ANGLE_START where it shows fully
const ANGLE_SPIN := 2.0 ## rad: past this the car is going backwards (reversing or spun), not drifting
const CAM_SWING := 0.55 ## share of the slip angle the chase camera swings round towards the car's side
const CAM_ROLL := 0.075 ## rad of camera roll per rad of slip
const CAM_IN := 2.6 ## /s: the camera eases out into a drift ...
const CAM_OUT := 1.4 ## /s: ... and settles back behind the car more slowly afterwards

## Banked-combo labels (points at least, text), smallest first: DriftMeter's popup.
const LABELS := [[0, "DRIFT"], [250, "GOOD DRIFT"], [1000, "GREAT DRIFT"], [3000, "INSANE DRIFT"]]

var swing := 0.0 ## rad (signed like the slip angle) the chase camera is swung round from behind the car
var roll := 0.0 ## rad the chase camera rolls about its view
var lead := 0.0 ## rad of yaw rate x CAM_LEAD: a chase camera that eases after the car trails a car rotating through a
## drift by about yaw rate / its rate, turned back towards the car's front; the caller adds it with its own lag
const CAM_LEAD := 1.0 ## share of that trail made up while drifting

## The angle from where the car points to where it is going, rad in (-PI, PI]; 0 when nearly stopped.
## (Sim frame: heading and velocity in the same x/y plane.)
static func slip_angle(vx: float, vy: float, heading: float) -> float:
	if vx * vx + vy * vy < 9.0:
		return 0.0
	return wrapf(atan2(vy, vx) - heading, -PI, PI)

## How much of a drift a slip of a_abs rad at v m/s is: 0 for a tidy corner or a car reversing, 1 for a proper slide.
static func amount(a_abs: float, v: float) -> float:
	if a_abs > ANGLE_SPIN:
		return 0.0
	return clampf((a_abs - ANGLE_START) / ANGLE_FULL, 0.0, 1.0) * smoothstep(4.0, 14.0, v)

## Index into LABELS for a banked combo of `points`.
static func label_index(points: int) -> int:
	var i := 0
	for k in LABELS.size():
		if points >= int(LABELS[k][0]):
			i = k
	return i

## One frame of the chase camera's drift swing and roll for a car moving at (vx, vy) and pointing along heading.
## yaw_lag: the car's yaw rate (rad/s) over the camera's ease rate (/s), the trail to make up (0: none).
func update_camera(vx: float, vy: float, heading: float, dt: float, snap := false, yaw_lag := 0.0) -> void:
	var a := slip_angle(vx, vy, heading)
	var k := amount(absf(a), sqrt(vx * vx + vy * vy))
	var want_swing := clampf(a, -1.2, 1.2) * CAM_SWING * k
	var want_roll := -clampf(a, -1.0, 1.0) * CAM_ROLL * k
	var want_lead := clampf(yaw_lag, -0.5, 0.5) * CAM_LEAD * k
	if snap:
		swing = want_swing
		roll = want_roll
		lead = want_lead
		return
	var e := 1.0 - exp(-dt * (CAM_IN if absf(want_swing) > absf(swing) else CAM_OUT))
	swing += (want_swing - swing) * e
	roll += (want_roll - roll) * e
	lead += (want_lead - lead) * e

func reset() -> void:
	swing = 0.0
	roll = 0.0
	lead = 0.0
