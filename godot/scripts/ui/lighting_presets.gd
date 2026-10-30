## Light per region, read by race_world.gd's _update_atmosphere. Small on purpose: the time of day and the
## weather do most of the work, a preset only nudges them. Ratios after the WRC (3DS) stage lighting sets:
## the sun about 2.5 times the sky fill, a cool blue fill, haze a paler, cooler sky colour.
##   haze: multiplies the distance haze (humid towns and coasts are mistier than a dry circuit)
##   warmth: how far the sun turns gold as it sinks (0 = none, 1 = the default, > 1 warmer)
##   fill: the sky fill's tint (the colour shadows take)
##   saturation: the picture's saturation by day, before the retro styles
extends RefCounted

const DEFAULT := {haze = 1.0, warmth = 1.0, fill = Color("#a9c3e6"), saturation = 1.16}

## Polish towns: hazier, softer northern light with a greener fill off the fields and woods.
const POLISH := {haze = 1.35, warmth = 0.9, fill = Color("#a8c2dc"), saturation = 1.12}

const PRESETS := {
	"bor": POLISH, "bielsko": POLISH, "brzeszcze": POLISH, "krakow": POLISH, "oswiecim": POLISH,
	"pszczyna": POLISH, "goliath": POLISH, "wilamowice": POLISH, "fiat": POLISH,
	"monaco": {haze = 1.1, warmth = 1.15, fill = Color("#a4c2ea"), saturation = 1.2},
	"monza": {haze = 1.15, warmth = 1.1, fill = Color("#a9c3e6"), saturation = 1.18},
	"tokyo": {haze = 1.45, warmth = 0.95, fill = Color("#a6bfe0"), saturation = 1.12},
	"indy": {haze = 0.85, warmth = 1.1, fill = Color("#a7c4ec"), saturation = 1.2},
}

static func for_track(key: String) -> Dictionary:
	return PRESETS.get(key, DEFAULT)
