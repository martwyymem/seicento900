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

## Inward HUD margin (px) inside the safe frame: ~4.5% of the screen at standard 16:9 / 16:10 / 21:9
## canvases so corner widgets sit closer to the action (NFS Unbound / Forza Horizon style), easing
## down smoothly on compact scaled canvases (e.g. 1231x692 at 1.3x UI scale) so nothing crowds.
static func hud_inset(safe_size: Vector2) -> Vector2:
	var tx := clampf((safe_size.x - 1220.0) / 300.0, 0.0, 1.0)
	var ty := clampf((safe_size.y - 680.0) / 180.0, 0.0, 1.0)
	var mx := roundf(lerpf(18.0, clampf(safe_size.x * 0.045, 56.0, 96.0), tx))
	var my := roundf(lerpf(16.0, clampf(safe_size.y * 0.046, 36.0, 62.0), ty))
	return Vector2(mx, my)

## Responsive panel scale inside the safe frame: 1.0 at standard 1600x900+ canvases (where panels
## already sit at the bigger 1.3-1.5x design size), easing gently down on compact 1.3x-scaled canvases.
static func hud_scale(safe_size: Vector2) -> float:
	if safe_size.x <= 1.0 or safe_size.y <= 1.0:
		return 1.0
	return clampf(minf(safe_size.x / 1520.0, safe_size.y / 860.0), 0.72, 1.0)

# ---------------- shared neon street palette & italic typography ----------------

## Primary electric neon accent (cyan in default/Carbon/FH1, adapted cleanly for other retro skins).
static func neon_primary() -> Color:
	match CmrStyle.skin:
		"mw": return Color("#d4ff2a")
		"sa": return Color("#78f065")
		"ps1": return Color("#5ce1ff")
		"carbon": return Color("#1ff0ff")
		"fh1": return Color("#2eeeff")
		_: return Color("#00ebff")

## Hot secondary neon accent (magenta/pink for high revs, redline halos, highlights).
static func neon_hot() -> Color:
	match CmrStyle.skin:
		"mw": return Color("#ff9d1a")
		"sa": return Color("#ffd633")
		"ps1": return Color("#ff4fd8")
		"carbon": return Color("#ff3fd6")
		"fh1": return Color("#ff3898")
		_: return Color("#ff2a9d")

## High-energy boost / nitrous / shift accent (Unbound laser yellow).
static func neon_boost() -> Color:
	match CmrStyle.skin:
		"carbon": return Color("#ffe633")
		"mw": return Color("#e6ff33")
		_: return Color("#ffe81a")

## Deep translucent glass plate tinted by the active skin's PLATE so panels stay readable over bright
## daytime sky and at night alike.
static func glass_plate(alpha := 0.86) -> Color:
	return Color(CmrStyle.PLATE.darkened(0.38), alpha)

static var _italic_cache := {}
static var _italic_skin := ""
static var _saira_face: Font = null

static func _saira() -> Font:
	if _saira_face == null:
		_saira_face = load("res://fonts/Saira.ttf")
	return _saira_face

## Slanted bold display font for punchy arcade speed, position, event titles and checkpoint toasts
## (preserves the active skin's full bold weight and stays upright in PS1 pixel mode).
static func italic_font(weight := 800, slant := -0.15) -> Font:
	if CmrStyle.skin == "ps1":
		return CmrStyle.font(weight)
	if _italic_skin != CmrStyle.skin:
		_italic_cache.clear()
		_italic_skin = CmrStyle.skin
	var key := "w%d_%.2f" % [weight, slant]
	if not _italic_cache.has(key):
		var base := CmrStyle.font(weight)
		var fv := FontVariation.new()
		if base is FontVariation:
			var bv := base as FontVariation
			fv.base_font = bv.base_font
			fv.variation_opentype = bv.variation_opentype.duplicate()
			fv.opentype_features = bv.opentype_features.duplicate()
			fv.fallbacks = bv.fallbacks
		else:
			fv.base_font = base
		fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(slant, 1.0), Vector2.ZERO)
		_italic_cache[key] = fv
	return _italic_cache[key]

## Slanted chunky tabular racing digits for speedometer, position callouts and clocks (upright in PS1).
static func italic_digits(slant := -0.14) -> Font:
	if CmrStyle.skin == "ps1":
		return CmrStyle.digits()
	if _italic_skin != CmrStyle.skin:
		_italic_cache.clear()
		_italic_skin = CmrStyle.skin
	var key := "d_%.2f" % slant
	if not _italic_cache.has(key):
		var ts := TextServerManager.get_primary_interface()
		var fv := FontVariation.new()
		if CmrStyle.skin == "cmr" and _saira() != null:
			# Chunky athletic motorsport numerals (Unbound / Forza style) with tabular figures
			fv.base_font = _saira()
			fv.variation_opentype = {
				ts.name_to_tag("wght"): 800,
				ts.name_to_tag("wdth"): 94,
			}
			fv.opentype_features = {ts.name_to_tag("tnum"): 1}
			fv.fallbacks = CmrStyle._fallbacks()
		else:
			var base := CmrStyle.digits()
			if base is FontVariation:
				var bv := base as FontVariation
				fv.base_font = bv.base_font
				var axes := bv.variation_opentype.duplicate()
				axes[ts.name_to_tag("wght")] = 800
				fv.variation_opentype = axes
				fv.opentype_features = bv.opentype_features.duplicate()
				fv.fallbacks = bv.fallbacks
			else:
				fv.base_font = base
		fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(slant, 1.0), Vector2.ZERO)
		_italic_cache[key] = fv
	return _italic_cache[key]

## Shared slanted neon StyleBoxFlat for cards, toasts, banners and pause panels.
static func neon_box(accent: Color, bg_alpha := 0.88, bar_w := 6, skew_x := -0.09, glow_sz := 10, pad_h := 22.0, pad_v := 14.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(CmrStyle.PLATE, bg_alpha)
	sb.border_color = accent
	sb.border_width_left = bar_w
	sb.border_width_top = 2
	sb.border_width_right = 1
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_right = 5
	sb.corner_radius_bottom_left = 3
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.skew = Vector2(0.0 if CmrStyle.skin == "ps1" else skew_x, 0.0)
	sb.shadow_color = Color(accent, 0.36)
	sb.shadow_size = 0 if CmrStyle.skin == "ps1" else glow_sz
	sb.shadow_offset = Vector2.ZERO
	return sb

## Draws a dark-glass panel with a soft neon halo, crisp border and bright left accent bar on a Control.
static func draw_neon_panel(c: Control, rect: Rect2, accent: Color, alpha := 0.86, bar_w := 5.0, top_glow := true) -> void:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	# soft outer neon bloom
	c.draw_rect(rect.grow(5.0), Color(accent, 0.10 * alpha))
	c.draw_rect(rect.grow(2.5), Color(accent, 0.20 * alpha))
	# dark translucent glass body
	c.draw_rect(rect, glass_plate(alpha))
	# subtle top sheen
	if top_glow:
		c.draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(rect.size.y * 0.45, 22.0))), Color(accent, 0.07 * alpha))
	# crisp neon outline + thick left accent bar
	c.draw_rect(rect, Color(accent, 0.72 * alpha), false, 1.5)
	if bar_w > 0.0:
		c.draw_rect(Rect2(rect.position.x - 1.5, rect.position.y, bar_w + 3.0, rect.size.y), Color(accent, 0.30 * alpha))
		c.draw_rect(Rect2(rect.position, Vector2(bar_w, rect.size.y)), Color(accent, minf(1.0, alpha + 0.12)))

static var _radial_glow_tex: GradientTexture2D = null

## Soft radial glow bloom drawn with a cached radial GradientTexture2D (no hard disc edges). Skipped in PS1.
static func draw_radial_glow(c: Control, center: Vector2, radius: float, col: Color) -> void:
	if CmrStyle.skin == "ps1" or radius <= 1.0 or col.a <= 0.001:
		return
	if _radial_glow_tex == null:
		var g := Gradient.new()
		g.set_offset(0, 0.0)
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.add_point(0.38, Color(1.0, 1.0, 1.0, 0.42))
		g.add_point(0.72, Color(1.0, 1.0, 1.0, 0.10))
		g.set_offset(g.get_point_count() - 1, 1.0)
		g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
		_radial_glow_tex = GradientTexture2D.new()
		_radial_glow_tex.gradient = g
		_radial_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_radial_glow_tex.fill_from = Vector2(0.5, 0.5)
		_radial_glow_tex.fill_to = Vector2(1.0, 0.5)
		_radial_glow_tex.width = 96
		_radial_glow_tex.height = 96
	c.draw_texture_rect(_radial_glow_tex, Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), false, col)

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
