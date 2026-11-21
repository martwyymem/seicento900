## Dynamic aspect-ratio helpers shared by the race HUD, open-world HUD, menus and 3D cameras:
## - HUD safe zone: caps HUD and menu spread on ultrawide displays to Full / 21:9 (default) / 16:9,
##   centred horizontally so HUD motion groups keep exact Vector2.ZERO rest pose inside the safe frame.
## - Camera Hor+ FOV: preserves vertical FOV at 16:9 and wider (more horizontal view) and widens vertical
##   FOV on narrower windows (16:10, 4:3, 5:4) so horizontal visibility never drops below 16:9's.
class_name HudLayout
extends RefCounted

const WIDTH_FULL := 0
const WIDTH_21_9 := 1
const WIDTH_16_9 := 2
const WIDTH_NAMES := ["Full", "21:9", "16:9"]
const WIDTH_RATIOS := [0.0, 21.0 / 9.0, 16.0 / 9.0]
const REF_ASPECT := 16.0 / 9.0 ## reference 16:9 aspect for Hor+ narrow-window FOV preservation
const MAX_VFOV := 135.0 ## safety clamp on vertical FOV for extreme portrait shapes

## Active HUD width setting shared by RaceHud, OpenWorldHud and menus (Options -> Display -> HUD WIDTH).
static var hud_width := WIDTH_21_9

static func load_from(config: ConfigFile) -> void:
	var raw: Variant = config.get_value("graphics", "hud_width", WIDTH_21_9)
	if raw is String:
		var idx := WIDTH_NAMES.find(raw)
		hud_width = idx if idx >= 0 else WIDTH_21_9
	else:
		hud_width = clampi(int(raw), WIDTH_FULL, WIDTH_16_9)

static func save_to(config: ConfigFile) -> void:
	config.set_value("graphics", "hud_width", hud_width)

## Centred safe-zone rectangle inside a canvas of size `canvas`, capped by `mode` (or active `hud_width`).
static func safe_rect(canvas: Vector2, mode := -1) -> Rect2:
	var m := hud_width if mode < 0 else clampi(mode, WIDTH_FULL, WIDTH_16_9)
	var W := maxf(0.0, canvas.x)
	var H := maxf(0.0, canvas.y)
	if W <= 0.0 or H <= 0.0:
		return Rect2(Vector2.ZERO, Vector2(W, H))
	var cap_ratio: float = WIDTH_RATIOS[m]
	if cap_ratio <= 0.0:
		return Rect2(Vector2.ZERO, Vector2(W, H))
	var max_w := H * cap_ratio
	if W <= max_w + 1.0:
		return Rect2(Vector2.ZERO, Vector2(W, H))
	var safe_w := minf(W, roundf(max_w))
	var x0 := clampf(roundf((W - safe_w) * 0.5), 0.0, maxf(0.0, W - safe_w))
	return Rect2(x0, 0.0, safe_w, H)

## Sizes `frame` (a child of a `canvas`-sized root Control) to the centred safe zone and returns that Rect2.
static func apply_safe_frame(frame: Control, canvas: Vector2, mode := -1) -> Rect2:
	var r := safe_rect(canvas, mode)
	if frame != null:
		frame.anchor_left = 0.0
		frame.anchor_top = 0.0
		frame.anchor_right = 1.0
		frame.anchor_bottom = 1.0
		frame.offset_left = r.position.x
		frame.offset_top = r.position.y
		frame.offset_right = r.end.x - canvas.x
		frame.offset_bottom = r.end.y - canvas.y
	return r

## Hor+ vertical FOV (degrees) for a viewport aspect ratio (width / height):
## - At 16:9 or wider (aspect >= REF_ASPECT): keeps base_vfov_deg unchanged so horizontal FOV grows.
## - Narrower than 16:9 (aspect < REF_ASPECT): grows vertical FOV so horizontal FOV matches 16:9's.
static func camera_fov(base_vfov_deg: float, aspect: float) -> float:
	if aspect <= 0.0 or aspect >= REF_ASPECT:
		return base_vfov_deg
	var half_tan := tan(deg_to_rad(base_vfov_deg) * 0.5) * (REF_ASPECT / aspect)
	return clampf(rad_to_deg(2.0 * atan(half_tan)), base_vfov_deg, MAX_VFOV)

## Ensures Hor+ (KEEP_HEIGHT) on `camera` and returns the vertical FOV for its current viewport aspect.
static func camera_fov_for(camera: Camera3D, base_vfov_deg: float) -> float:
	if camera == null:
		return base_vfov_deg
	if camera.keep_aspect != Camera3D.KEEP_HEIGHT:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var vp := camera.get_viewport()
	if vp == null:
		return base_vfov_deg
	var sz := vp.get_visible_rect().size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return base_vfov_deg
	return camera_fov(base_vfov_deg, sz.x / sz.y)
