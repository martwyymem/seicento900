## Fiat Seicento 900 vehicle model (port of js/car.js).
class_name CarModel
extends RefCounted

const G := 9.81

var spec: CarSpec

func _init(car_spec: CarSpec = null) -> void:
	spec = car_spec if car_spec else load("res://data/seicento.tres")

func torque_at(rpm: float) -> float:
	var tc := spec.torque_curve
	if rpm <= tc[0].x:
		return tc[0].y
	for i in range(1, tc.size()):
		if rpm <= tc[i].x:
			var a := tc[i - 1]
			var b := tc[i]
			return a.y + (b.y - a.y) * (rpm - a.x) / (b.x - a.x)
	return 0.0

func ratio(gear: int) -> float:
	return spec.gears[gear] * spec.final_drive

func rpm_for(v: float, gear: int) -> float:
	return absf(v) / spec.wheel_radius * ratio(gear) * (60.0 / TAU)

## Engine rpm including clutch slip in first gear when pulling away.
func engine_rpm(v: float, gear: int, throttle: float) -> float:
	var r := rpm_for(v, gear)
	if gear == 0 and throttle > 0.05:
		return maxf(r, 2600.0 * throttle + spec.idle_rpm * (1.0 - throttle))
	return maxf(r, spec.idle_rpm)

func wheel_force(v: float, gear: int, throttle: float) -> float:
	var rpm := engine_rpm(v, gear, throttle)
	if rpm >= spec.limiter:
		return 0.0
	return throttle * torque_at(rpm) * ratio(gear) * spec.efficiency / spec.wheel_radius

## The gear an ideal driver would be in: most tractive force without passing the redline.
func best_gear(v: float) -> int:
	var best := 0
	var best_f := -1.0
	var n := spec.gears.size()
	for g in n:
		if g > 0 and rpm_for(v, g) < 1500.0:
			break
		if rpm_for(v, g) > spec.redline and g < n - 1:
			continue
		var f := wheel_force(v, g, 1.0)
		if f > best_f:
			best_f = f
			best = g
	return best

func resistance(v: float, mass: float, drag_mul := 1.0) -> float:
	return 0.5 * 1.2 * spec.cd_a * drag_mul * v * v + spec.crr * mass * G

## Full-throttle longitudinal acceleration in the best gear (used by AI and the lap simulator).
func max_accel(v: float, mass: float, mu: float, drag_mul := 1.0) -> float:
	var drive := minf(wheel_force(v, best_gear(v), 1.0), spec.front_weight * mu * G * mass)
	return (drive - resistance(v, mass, drag_mul)) / (mass * 1.05)

## Deceleration from tyre scrub while cornering on curvature k: slip angles tilt the lateral force
## backwards. Fitted to the four-wheel model in physics.
func scrub(v: float, k: float, mu: float) -> float:
	var ay := v * v * absf(k)
	var u := minf(1.2, ay / (mu * G))
	return 0.065 * ay * u * sqrt(u)

## Litres per second for a given engine output (W).
func fuel_rate(power_w: float) -> float:
	var idle := 0.35 / 3600.0
	if power_w <= 0.0:
		return idle
	return idle + power_w / 1000.0 * spec.bsfc / 3600.0 / (spec.fuel_density * 1000.0)

func base_mass() -> float:
	return spec.mass_empty + spec.driver_mass

func mass_with_fuel(litres: float) -> float:
	return base_mass() + litres * spec.fuel_density
