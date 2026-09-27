## Small helpers shared by the simulation (the JS SC.util), with JS-compatible rounding and modulo.
class_name SimUtil
extends RefCounted

## Mulberry32 PRNG, bit-identical to the JS version.
class Rng:
	var state := 0

	func _init(seed_: int) -> void:
		state = seed_ & 0xffffffff

	func next() -> float:
		state = (state + 0x6d2b79f5) & 0xffffffff
		var t := SimUtil.imul(state ^ (state >> 15), 1 | state)
		t = ((t + SimUtil.imul(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t
		return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0

## JS Math.imul on unsigned 32-bit values, split so the product never overflows 64 bits.
static func imul(a: int, b: int) -> int:
	return (a * (b & 0xffff) + (((a * (b >> 16)) & 0xffff) << 16)) & 0xffffffff

static func smooth01(x: float) -> float:
	return 0.0 if x <= 0.0 else (1.0 if x >= 1.0 else x * x * (3.0 - 2.0 * x))

static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))

## JS Math.round: halves round up (towards +infinity), unlike GDScript round().
static func js_round(x: float) -> int:
	return int(floorf(x + 0.5))

## JS % on numbers (result takes the sign of the dividend).
static func js_mod(a: float, b: float) -> float:
	return fmod(a, b)

## Sun elevation/azimuth (degrees) for local time h on a June race weekend at ~48–50°N, and how much
## daylight that gives (0 = night, 1 = full day). Returns [el, az, day].
static func sun_at(h: float) -> PackedFloat64Array:
	var rise := 5.9
	var set_ := 21.6
	var el: float
	if h >= rise and h <= set_:
		el = 63.0 * sin(PI * (h - rise) / (set_ - rise))
	else:
		el = -20.0 * sin(PI * fmod(h - set_ + 24.0, 24.0) / (24.0 - (set_ - rise)))
	return PackedFloat64Array([el, 180.0 + (h - 13.75) * 16.0, smooth01((el + 6.0) / 14.0)])
