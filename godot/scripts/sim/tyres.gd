## Tyre compounds, grip and wear (port of the tyre half of js/car.js).
class_name Tyres
extends RefCounted

const KEYS := ["S", "M", "H", "W"] ## soft, medium, hard, wet; each loads data/tyres/<key>.tres

var compounds := {} ## key -> TyreCompound

func _init() -> void:
	for k in KEYS:
		compounds[k] = load("res://data/tyres/%s.tres" % k)

static func compound_bit(c: String) -> int:
	return 1 << KEYS.find(c)

## Grip of a fresh, warm tyre for the given track wetness (0 dry .. 1 soaked).
func compound_grip(c: String, wet: float) -> float:
	if c == "W":
		return compounds.W.grip - 0.07 * wet
	return compounds[c].grip * (1.0 - 0.43 * wet)

## Remaining tread 1..0: gentle linear fall-off, then a cliff below 25 %.
static func wear_grip(w: float) -> float:
	if w >= 0.25:
		return 1.0 - 0.06 * (1.0 - w) / 0.75
	return maxf(0.6, 0.94 - 0.26 * (0.25 - w) / 0.25)

static func temp_grip(t: float) -> float:
	return 0.9 + 0.1 * clampf(t, 0.0, 1.0)

## Tread fraction lost per metre at nominal driving load.
func wear_per_metre(c: String, wet: float, wear_mult: float) -> float:
	var r: float = 1.0 / compounds[c].life
	if c == "W":
		r *= 1.0 + 3.5 * (1.0 - wet) * (1.0 - wet) # wets cook on a dry track
	else:
		r *= 1.0 - 0.35 * wet # slicks stay cool in the rain
	return r * wear_mult

## tyre: {c: compound key, wear: 1..0, temp: 0..1}
func tyre_grip(tyre: Dictionary, wet: float) -> float:
	return compound_grip(tyre.c, wet) * wear_grip(tyre.wear) * temp_grip(tyre.temp)
