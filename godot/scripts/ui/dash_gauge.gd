## Neon street circular-dial speedometer shared by the race HUD and the open-world HUD (NFS Unbound /
## Forza Horizon 6 style): dark-glass circular dial with a thick glowing segmented RPM arc (cyan -> hot
## magenta -> redline crimson, flashing white at the limiter), multi-pass neon bloom halo, radial ticks,
## huge bold slanted speed digits inside the dial, a glowing bordered GEAR badge, an optional SLIPSTREAM
## indicator, and a curved neon-yellow/cyan N2O boost bar hugging the left flank.
class_name DashGauge
extends Control

const SEGMENTS := 26
const REF_W := 330.0 ## design width (scale 1.0)
const REF_H := 276.0 ## design height (scale 1.0)
const NITRO_BAND := 0.0 ## curved boost arc hugs the left flank inside REF_W (no extra bottom shift)

const ARC_START := 2.3038346 ## 132 deg (bottom-left ~7:30)
const ARC_SPAN := 4.8171087 ## 276 deg clockwise through top to bottom-right (~4:30)
const N2O_START := 2.5830873 ## 148 deg (lower-left flank)
const N2O_END := 3.7699112 ## 216 deg (upper-left flank)
const N2O_SEGS := 14

var speed_kmh := 0
var gear_text := "1"
var rev_frac := 0.0
var redline := false
var slipstream := false
var nitro := -1.0 ## 0..1 when the Nitrous modifier is on; negative hides the boost bar
var nitro_burning := false
var reserve_nitro := false ## kept for API compatibility (curved boost arc sits inside the fixed dial frame)
var tilt_skew := Vector2.ZERO ## subtle 2.5D cockpit shear driven by HudMotion (exact zero at rest)

## Optional audit hook: func(canvas: Control, font: Font, at: Vector2, s: String, align: int, width: float, size: int)
var audit_fn: Callable = Callable()

var _mesh_size := Vector2.ZERO
var _mesh_nitro := false
var _points := PackedVector2Array() ## SEGMENTS * 4 verts (tested by test_ui_layout.gd)
var _colors := PackedColorArray()
var _indices := PackedInt32Array() ## SEGMENTS * 6 indices
var _glow_points := PackedVector2Array() ## wider outer halo mesh behind the lit RPM arc
var _glow_colors := PackedColorArray()
var _glow_indices := PackedInt32Array()
var _n2o_points := PackedVector2Array()
var _n2o_colors := PackedColorArray()
var _n2o_indices := PackedInt32Array()
var _dial_center := Vector2.ZERO
var _dial_r_out := 110.0
var _dial_r_in := 88.0
var _state_key: Array = []
var _queued: Array = [] ## [outline size (0 plain), font, at, text, align, width, size, colour]

## Segments lit for a normalised engine speed in 0..1: segment i is lit while (i + 0.78) / n <= frac + 0.03.
static func lit_segments(frac: float) -> int:
	var f := clampf(frac, 0.0, 1.0)
	return clampi(floori((f + 0.03) * SEGMENTS - 0.78) + 1, 0, SEGMENTS)

## Redline strobe at 12 Hz once revs reach 91% of the limiter.
static func is_redline(frac: float, clock: float) -> bool:
	return frac >= 0.91 and fmod(clock * 12.0, 1.0) < 0.5

static func _shade(a: float) -> Color:
	return Color(CmrStyle.PLATE.darkened(0.55), a)

## Updates the displayed state and queues a redraw only when something visible changes.
func set_state(kmh: int, gear: String, frac: float, red: bool, slip := false, n2o := -1.0, burning := false) -> void:
	var cfrac := clampf(frac, 0.0, 1.0)
	var lit := lit_segments(cfrac)
	var n2o_q := -1 if n2o < 0.0 else roundi(clampf(n2o, 0.0, 1.0) * 250.0)
	var key: Array = [size, lit, gear, kmh, red, slip, n2o_q, burning]
	speed_kmh = kmh
	gear_text = gear
	rev_frac = cfrac
	redline = red
	slipstream = slip
	nitro = n2o
	nitro_burning = burning
	if key != _state_key:
		_state_key = key
		queue_redraw()

## Updates the subtle 2.5D perspective shear driven by HudMotion; zero at rest leaves draw identical.
func set_tilt(skew: Vector2) -> void:
	if skew.is_zero_approx():
		if tilt_skew != Vector2.ZERO:
			tilt_skew = Vector2.ZERO
			queue_redraw()
		return
	if absf(skew.x - tilt_skew.x) > 0.0008 or absf(skew.y - tilt_skew.y) > 0.0008:
		tilt_skew = skew
		queue_redraw()

## Called by CmrStyle.restyle() and the parent HUD on a retro-skin switch.
func _skin_changed() -> void:
	_mesh_size = Vector2.ZERO
	_state_key = []
	queue_redraw()

func _scale(W: float, H: float) -> float:
	return minf(W / REF_W, H / REF_H)

## Builds the circular segmented RPM arc (exact SEGMENTS*4 verts / SEGMENTS*6 indices), its outer
## neon glow halo mesh, and the curved left-flank N2O boost arc mesh.
func _build_mesh(W: float, H: float) -> void:
	_mesh_size = size
	_mesh_nitro = reserve_nitro
	var s := _scale(W, H)
	_dial_r_out = 114.0 * s
	_dial_r_in = 91.0 * s
	# Shift the dial centre slightly right to reserve the left flank for the curved N2O arc.
	_dial_center = Vector2(W - _dial_r_out - 14.0 * s, H * 0.51)

	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	_glow_points = PackedVector2Array()
	_glow_colors = PackedColorArray()
	_glow_indices = PackedInt32Array()

	var n := SEGMENTS
	var gap := 0.14 / float(n)
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n) - gap
		var a0 := ARC_START + ARC_SPAN * t0
		var a1 := ARC_START + ARC_SPAN * t1
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		# Thickens slightly toward redline for extra kinetic punch
		var ri0 := _dial_r_in - 3.0 * s * pow(t0, 1.8)
		var ri1 := _dial_r_in - 3.0 * s * pow(t1, 1.8)
		var ro0 := _dial_r_out + 2.5 * s * pow(t0, 1.8)
		var ro1 := _dial_r_out + 2.5 * s * pow(t1, 1.8)

		var k := _points.size()
		_points.append_array(PackedVector2Array([
			_dial_center + d0 * ri0,
			_dial_center + d1 * ri1,
			_dial_center + d1 * ro1,
			_dial_center + d0 * ro0,
		]))
		for _j in 4:
			_colors.append(Color.WHITE)
		_indices.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))

		# Soft neon bloom quad extending ±8 px radially around each lit segment
		var gk := _glow_points.size()
		var ga0 := a0 - 0.012
		var ga1 := a1 + 0.012
		var gd0 := Vector2(cos(ga0), sin(ga0))
		var gd1 := Vector2(cos(ga1), sin(ga1))
		_glow_points.append_array(PackedVector2Array([
			_dial_center + gd0 * (ri0 - 9.0 * s),
			_dial_center + gd1 * (ri1 - 9.0 * s),
			_dial_center + gd1 * (ro1 + 10.0 * s),
			_dial_center + gd0 * (ro0 + 10.0 * s),
		]))
		for _j in 4:
			_glow_colors.append(Color.TRANSPARENT)
		_glow_indices.append_array(PackedInt32Array([gk, gk + 1, gk + 2, gk, gk + 2, gk + 3]))

	# Curved boost / N2O bar hugging the left outer rim of the dial (Unbound style)
	_n2o_points = PackedVector2Array()
	_n2o_colors = PackedColorArray()
	_n2o_indices = PackedInt32Array()
	var nr_in := _dial_r_out + 11.0 * s
	var nr_out := _dial_r_out + 24.0 * s
	for i in N2O_SEGS:
		var u0 := float(i) / float(N2O_SEGS)
		var u1 := (float(i) + 0.84) / float(N2O_SEGS)
		var na0 := lerpf(N2O_START, N2O_END, u0)
		var na1 := lerpf(N2O_START, N2O_END, u1)
		var nd0 := Vector2(cos(na0), sin(na0))
		var nd1 := Vector2(cos(na1), sin(na1))
		var nk := _n2o_points.size()
		_n2o_points.append_array(PackedVector2Array([
			_dial_center + nd0 * nr_in,
			_dial_center + nd1 * nr_in,
			_dial_center + nd1 * nr_out,
			_dial_center + nd0 * nr_out,
		]))
		for _j in 4:
			_n2o_colors.append(Color.WHITE)
		_n2o_indices.append_array(PackedInt32Array([nk, nk + 1, nk + 2, nk, nk + 2, nk + 3]))

func _rpm_color(t: float, cyan: Color, hot: Color, red_col: Color) -> Color:
	if t >= 0.84:
		return red_col
	if t >= 0.60:
		var u := clampf((t - 0.60) / 0.24, 0.0, 1.0)
		return cyan.lerp(hot, u)
	return cyan.lerp(cyan.lightened(0.18), t / 0.60)

func _draw() -> void:
	var W := size.x
	var H := size.y
	if W < 1.0 or H < 1.0:
		return
	if tilt_skew != Vector2.ZERO:
		var mid := Vector2(W * 0.5, H * 0.5)
		var xf := Transform2D(Vector2(1.0, tilt_skew.y), Vector2(tilt_skew.x, 1.0), Vector2.ZERO)
		draw_set_transform_matrix(Transform2D(0.0, mid) * xf * Transform2D(0.0, -mid))
	if _mesh_size != size or _mesh_nitro != reserve_nitro:
		_build_mesh(W, H)

	var s := _scale(W, H)
	var c := _dial_center
	var lit := lit_segments(rev_frac)
	var cyan := HudLayout.neon_primary()
	var hot := HudLayout.neon_hot()
	var boost_col := HudLayout.neon_boost()
	var red_col := CmrStyle.RED
	var text_col := Color.WHITE if CmrStyle.skin != "ps1" else CmrStyle.TEXT
	var muted_col := CmrStyle.MUTED
	var bold := HudLayout.italic_font(800, -0.14)
	var heavy := HudLayout.italic_font(900, -0.14)
	var digits := HudLayout.italic_digits(-0.14)

	# 1. Outer ambient neon glow & dark translucent glass dial disc (high contrast day & night)
	var aura_col := red_col if redline else (hot if rev_frac >= 0.72 else cyan)
	draw_circle(c, _dial_r_out + 12.0 * s, Color(aura_col, 0.11))
	draw_circle(c, _dial_r_out + 5.0 * s, Color(aura_col, 0.18))
	draw_circle(c, _dial_r_out + 3.0 * s, HudLayout.glass_plate(0.84))
	draw_circle(c, _dial_r_in - 3.0 * s, Color(CmrStyle.PLATE.darkened(0.65), 0.55))

	# Outer sleek bezel ring + subtle inner track ring
	draw_arc(c, _dial_r_out + 3.0 * s, ARC_START - 0.12, ARC_START + ARC_SPAN + 0.12, 48, Color(cyan, 0.55), maxf(1.5, 2.2 * s), true)
	draw_arc(c, _dial_r_in - 4.0 * s, ARC_START, ARC_START + ARC_SPAN, 42, Color(1.0, 1.0, 1.0, 0.14), maxf(1.0, 1.5 * s), true)

	# 2. Radial tick marks around the inner edge of the dial (redline zone glowing hot)
	var ticks := 28
	for i in ticks + 1:
		var u := float(i) / float(ticks)
		var a := ARC_START + ARC_SPAN * u
		var dir := Vector2(cos(a), sin(a))
		var major := (i % 4 == 0)
		var t_in := _dial_r_in - ((12.0 if major else 7.5) * s)
		var t_out := _dial_r_in - 2.0 * s
		var tcol := Color(hot if u >= 0.80 else Color.WHITE, 0.85 if major else 0.35)
		draw_line(c + dir * t_in, c + dir * t_out, tcol, (2.2 if major else 1.2) * s, true)

	# 3. Thick glowing segmented RPM arc + rich neon bloom behind lit segments
	var n := SEGMENTS
	for i in n:
		var t0 := float(i) / float(n)
		var col := Color(hot if t0 >= 0.82 else cyan, 0.18)
		var gcol := Color(0.0, 0.0, 0.0, 0.0)
		if i < lit:
			if redline and t0 >= 0.82:
				col = Color.WHITE
				gcol = Color(red_col, 0.58)
			else:
				col = _rpm_color(t0, cyan, hot, red_col)
				gcol = Color(col, 0.44)
		for j in 4:
			_colors[i * 4 + j] = col
			_glow_colors[i * 4 + j] = gcol
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _glow_indices, _glow_points, _glow_colors)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _points, _colors)

	# Leading bright glow cap at the current RPM tip
	if lit > 0:
		var tip_a := ARC_START + ARC_SPAN * clampf(rev_frac, 0.0, 1.0)
		var tip_d := Vector2(cos(tip_a), sin(tip_a))
		var tip_col := Color.WHITE if redline else _rpm_color(rev_frac, cyan, hot, red_col).lightened(0.4)
		draw_line(c + tip_d * (_dial_r_in - 6.0 * s), c + tip_d * (_dial_r_out + 6.0 * s), Color(tip_col, 0.55), 6.0 * s, true)
		draw_line(c + tip_d * (_dial_r_in - 4.0 * s), c + tip_d * (_dial_r_out + 4.0 * s), Color.WHITE, 2.4 * s, true)

	# 4. Curved left-flank N2O boost bar (when nitro >= 0) or subtle decorative rim accent
	if nitro >= 0.0:
		var nfrac := clampf(nitro, 0.0, 1.0)
		var nlit := clampi(roundi(nfrac * float(N2O_SEGS)), 0, N2O_SEGS)
		var nr_mid := _dial_r_out + 17.5 * s
		# Dark curved backdrop & neon glow behind the boost bar
		draw_arc(c, nr_mid, N2O_START - 0.04, N2O_END + 0.04, 24, HudLayout.glass_plate(0.82), 18.0 * s, true)
		var active_boost := Color("#38f8ff") if nitro_burning else boost_col
		if nlit > 0:
			var fill_end := lerpf(N2O_START, N2O_END, float(nlit) / float(N2O_SEGS))
			draw_arc(c, nr_mid, N2O_START, fill_end, 20, Color(active_boost, 0.36 if nitro_burning else 0.26), 26.0 * s, true)
		for i in N2O_SEGS:
			var ncol := active_boost if i < nlit else Color(boost_col, 0.16)
			for j in 4:
				_n2o_colors[i * 4 + j] = ncol
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _n2o_indices, _n2o_points, _n2o_colors)
		draw_arc(c, _dial_r_out + 25.0 * s, N2O_START - 0.03, N2O_END + 0.03, 22, Color(active_boost, 0.65), maxf(1.0, 1.6 * s), true)
		_q(Vector2(34.0 * s, c.y + 84.0 * s), "N2O", maxi(10, roundi(14.0 * s)), active_boost, heavy, HORIZONTAL_ALIGNMENT_RIGHT, 56.0 * s)
	else:
		# Subtle sleek curved bracket on the left flank so the dial has dynamic Unbound silhouette even without N2O
		draw_arc(c, _dial_r_out + 11.0 * s, N2O_START + 0.12, N2O_END - 0.12, 20, Color(cyan, 0.35), maxf(1.5, 2.5 * s), true)

	# 5. Huge bold slanted speed digits inside the dial + KM/H + centered GEAR label + glowing GEAR badge
	var spd_str := "%d" % speed_kmh
	var spd_fs := maxi(14, roundi((74.0 if spd_str.length() <= 3 else 60.0) * s))
	var spd_w := 172.0 * s
	var spd_x := c.x - spd_w * 0.5
	var spd_y := c.y - 4.0 * s
	# Subtle neon glow behind the big speed numeral
	if CmrStyle.skin != "ps1":
		draw_string_outline(digits, Vector2(spd_x, spd_y), spd_str, HORIZONTAL_ALIGNMENT_CENTER, spd_w, spd_fs, maxi(4, roundi(11.0 * s)), Color(aura_col, 0.30))
	_q(Vector2(spd_x, spd_y), spd_str, spd_fs, text_col, digits, HORIZONTAL_ALIGNMENT_CENTER, spd_w)

	var kmh_fs := maxi(10, roundi(14.0 * s))
	var kmh_w := 96.0 * s
	_q(Vector2(c.x - kmh_w * 0.5, c.y + 22.0 * s), "KM/H", kmh_fs, cyan.lightened(0.35), bold, HORIZONTAL_ALIGNMENT_CENTER, kmh_w)

	# "GEAR" tag sits cleanly centered right above the glowing gear badge (never touches the RPM arc)
	var gl_w := 76.0 * s
	_q(Vector2(c.x - gl_w * 0.5, c.y + 40.0 * s), "GEAR", maxi(9, roundi(11.0 * s)), Color(1.0, 1.0, 1.0, 0.82), bold, HORIZONTAL_ALIGNMENT_CENTER, gl_w)

	# Glowing bordered GEAR badge centered in the bottom opening of the dial
	var badge_w := 54.0 * s
	var badge_h := 44.0 * s
	var badge := Rect2(c.x - badge_w * 0.5, c.y + 46.0 * s, badge_w, badge_h)
	var gear_col := red_col if redline else (boost_col if gear_text != "N" else Color(0.88, 0.94, 1.0))
	draw_rect(badge.grow(4.5 * s), Color(gear_col, 0.26))
	draw_rect(badge, HudLayout.glass_plate(0.94))
	draw_rect(badge, gear_col, false, maxf(1.5, 2.5 * s))
	var gear_fs := maxi(12, roundi(34.0 * s))
	_q(Vector2(badge.position.x, badge.position.y + 34.0 * s), gear_text, gear_fs, gear_col, digits, HORIZONTAL_ALIGNMENT_CENTER, badge_w)

	if slipstream:
		var sl_w := 124.0 * s
		var sl_r := Rect2(c.x - sl_w * 0.5, 4.0 * s, sl_w, 20.0 * s)
		draw_rect(sl_r.grow(3.0 * s), Color(cyan, 0.24))
		draw_rect(sl_r, HudLayout.glass_plate(0.92))
		draw_rect(sl_r, Color(cyan, 0.24))
		draw_rect(sl_r, cyan, false, 1.5)
		_q(Vector2(sl_r.position.x, sl_r.position.y + 15.0 * s), "SLIPSTREAM", maxi(9, roundi(12.0 * s)), cyan.lightened(0.35), heavy, HORIZONTAL_ALIGNMENT_CENTER, sl_w)

	_q_flush()

func _q(at: Vector2, text: String, font_size: int, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_queued.append([maxi(2, font_size / 8), font, at, text, align, width, font_size, _shade(0.92 * color.a)])
	_queued.append([0, font, at, text, align, width, font_size, color])

func _q_flush() -> void:
	var groups := {}
	var keys: Array = []
	for t: Array in _queued:
		var outline_sz: int = t[0]
		var f: Font = t[1]
		var fs: int = t[6]
		var key := Vector3i(-outline_sz, f.get_instance_id() % 1000003, fs)
		if not groups.has(key):
			groups[key] = []
			keys.append(key)
		(groups[key] as Array).append(t)
	keys.sort()
	for key: Vector3i in keys:
		for t: Array in groups[key]:
			var outline_sz: int = t[0]
			var f: Font = t[1]
			var at: Vector2 = t[2]
			var s: String = t[3]
			var align: HorizontalAlignment = t[4]
			var width: float = t[5]
			var fs: int = t[6]
			var col: Color = t[7]
			if outline_sz > 0:
				draw_string_outline(f, at, s, align, width, fs, outline_sz, col)
			else:
				if audit_fn.is_valid():
					audit_fn.call(self, f, at, s, align, width, fs)
				draw_string(f, at, s, align, width, fs, col)
	_queued.clear()
