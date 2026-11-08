## The shared post look of the 3D worlds (the race circuits, race_world.gd, and the open world, open_world.gd):
## tonemapper, glow, ambient occlusion and the base grade, and how the glow and grade move with the hour. Each world
## still lights its own scene (sun, sky, fill, fog); this keeps the camera side the same, so a race and the open
## world read as one game. The look aims at the mid-2000s street racers: firm blacks, saturated colour, crisp sun
## shadows by day, and after dark a deep blue night in which lamps, headlights and tail lights glow.
class_name SceneMood
extends RefCounted

## Glow levels (Environment.glow_levels/1..7): mostly the wide ones, so lights wear soft halos rather than a fuzzy rim.
const GLOW_LEVELS := [0.0, 0.55, 0.6, 0.55, 0.4, 0.25, 0.0]

## Settings that do not change with the hour.
static func base(env: Environment) -> void:
	# ACES (filmic): firmer blacks and richer colour than AgX, whose desaturated highlights read washed-out here;
	# the white point keeps lamps and the sun from clipping flat
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# contact shadows: under cars, eaves, kerbs, between houses
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.12
	env.glow_enabled = true
	env.glow_normalized = true
	for i in GLOW_LEVELS.size():
		env.set("glow_levels/%d" % (i + 1), GLOW_LEVELS[i])
	env.glow_strength = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 16.0
	env.adjustment_enabled = true

## Glow and grade for the light: day (0 night .. 1 full daylight), golden (0..1, the low warm sun), night (0..1).
## By day only the sun, its glints and the brightest sky glow; after dark everything brighter than the lit road
## (lamp heads, headlights, tail lights, lit windows) wears a halo. saturation: the world's own daylight saturation.
static func by_hour(env: Environment, day: float, golden: float, night: float, saturation := 1.15) -> void:
	# the eye opens up after dark: the moonlit blue stays readable and the lights bloom harder
	env.tonemap_exposure = lerpf(1.0, 1.35, night)
	env.glow_hdr_threshold = lerpf(1.2, 0.55, night)
	env.glow_intensity = lerpf(0.4, 1.05, night) + 0.15 * golden
	env.glow_bloom = 0.012 * night
	env.adjustment_contrast = lerpf(1.08, 1.12, maxf(golden, night))
	env.adjustment_saturation = lerpf(saturation, saturation + 0.1, golden) * lerpf(1.0, 0.95, night * (1.0 - day))
