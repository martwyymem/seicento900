## Fiat Seicento 900 vehicle model (port of js/car.js).
class_name CarModel
extends RefCounted

const G := 9.81

var spec: CarSpec
# caches of the spec, rebuilt by refresh() (call it after editing the spec at runtime)
var _ratios := PackedFloat64Array()
var _tq_rpm := PackedFloat64Array()
var _tq_nm := PackedFloat64Array()
var _n_gears := 0

func _init(car_spec: CarSpec = null) -> void:
	spec = car_spec if car_spec else load("res://data/seicento.tres")
	refresh()

func refresh() -> void:
	_n_gears = spec.gears.size()
	_ratios.resize(_n_gears)
	for g in _n_gears:
		_ratios[g] = spec.gears[g] * spec.final_drive
	_tq_rpm.resize(spec.torque_curve.size())
	_tq_nm.resize(spec.torque_curve.size())
	for i in spec.torque_curve.size():
		_tq_rpm[i] = spec.torque_curve[i].x
		_tq_nm[i] = spec.torque_curve[i].y

func torque_at(rpm: float) -> float:
	if rpm <= _tq_rpm[0]:
		return _tq_nm[0]
	for i in range(1, _tq_rpm.size()):
		if rpm <= _tq_rpm[i]:
			var r0 := _tq_rpm[i - 1]
			var t0 := _tq_nm[i - 1]
			return t0 + (_tq_nm[i] - t0) * (rpm - r0) / (_tq_rpm[i] - r0)
	return 0.0

func ratio(gear: int) -> float:
	return _ratios[gear]

func rpm_for(v: float, gear: int) -> float:
	return absf(v) / spec.wheel_radius * _ratios[gear] * (60.0 / TAU)

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
	_best_gear(v)
	return _bg_gear

var _bg_gear := 0
var _bg_force := 0.0

## best_gear() and its full-throttle wheel force in one pass (same arithmetic as the JS, so bit-identical).
func _best_gear(v: float) -> void:
	var best := 0
	var best_f := -1.0
	var n := _n_gears
	var u := absf(v) / spec.wheel_radius
	var c := 60.0 / TAU
	for g in n:
		var rpm := u * _ratios[g] * c
		if g > 0 and rpm < 1500.0:
			break
		if rpm > spec.redline and g < n - 1:
			continue
		# wheel_force(v, g, 1) inlined
		if g == 0:
			rpm = maxf(rpm, 2600.0 + spec.idle_rpm * 0.0)
		else:
			rpm = maxf(rpm, spec.idle_rpm)
		var f := 0.0
		if rpm < spec.limiter:
			f = 1.0 * torque_at(rpm) * _ratios[g] * spec.efficiency / spec.wheel_radius
		if f > best_f:
			best_f = f
			best = g
	_bg_gear = best
	_bg_force = best_f

func resistance(v: float, mass: float, drag_mul := 1.0) -> float:
	return 0.5 * 1.2 * spec.cd_a * drag_mul * v * v + spec.crr * mass * G

## The full-throttle wheel force in the gear the last best_gear() or max_accel() picked: wheel_force(v, gear, 1)
## for that speed, already worked out.
func full_force() -> float:
	return _bg_force

## Full-throttle longitudinal acceleration in the best gear (used by AI and the lap simulator).
## power scales the engine's output (the fuel mix, Strategy.MIXES).
func max_accel(v: float, mass: float, mu: float, drag_mul := 1.0, power := 1.0) -> float:
	_best_gear(v)
	var drive := minf(_bg_force * power, spec.front_weight * mu * G * mass)
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
