class_name GfxFx
extends RefCounted
## Camera and screen-effect switches shared by the race, the open world and the options menu (CAMERA & SCREEN
## EFFECTS, saved in graphics.cfg by game.gd), plus the per-frame speed state they feed: the smoothed FOV widening
## and the radial speed blur strength.

static var bloom := true
static var lens_flare := true
static var rear_mirror := true
static var speed_fov := true
static var speed_blur := true

const FOV_MAX := 18.0 ## degrees added at FOV_TOP
const FOV_FROM := 30.0 ## km/h where the widening starts
const FOV_TOP := 220.0 ## km/h where it is full
const BLUR_FROM := 60.0 ## km/h where the speed blur starts
const BLUR_TOP := 200.0 ## km/h where it is full
const BLUR_MAX := 1.0

static var fov_bonus := 0.0
static var blur := 0.0

## Call once per frame from the chase camera with the car's speed. Returns the FOV bonus in degrees.
static func update(kmh: float, delta: float) -> float:
	var want_fov := smoothstep(FOV_FROM, FOV_TOP, kmh) * FOV_MAX if speed_fov else 0.0
	fov_bonus += (want_fov - fov_bonus) * (1.0 - exp(-delta * 3.0))
	var want_blur := smoothstep(BLUR_FROM, BLUR_TOP, kmh) * BLUR_MAX if speed_blur else 0.0
	blur += (want_blur - blur) * (1.0 - exp(-delta * 4.0))
	return fov_bonus

static func load_from(config: ConfigFile) -> void:
	bloom = bool(config.get_value("graphics", "bloom", true))
	lens_flare = bool(config.get_value("graphics", "lens_flare", true))
	rear_mirror = bool(config.get_value("graphics", "rear_mirror", true))
	speed_fov = bool(config.get_value("graphics", "speed_fov", true))
	speed_blur = bool(config.get_value("graphics", "speed_blur", true))

static func save_to(config: ConfigFile) -> void:
	config.set_value("graphics", "bloom", bloom)
	config.set_value("graphics", "lens_flare", lens_flare)
	config.set_value("graphics", "rear_mirror", rear_mirror)
	config.set_value("graphics", "speed_fov", speed_fov)
	config.set_value("graphics", "speed_blur", speed_blur)
