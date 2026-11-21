## Segmented rev-sweep speedometer shared by the race HUD and the open-world HUD: slanted segments rising
## along a curve (accent, orange near the top, red at the limiter, flashing white at the redline), big speed
## digits with "KM/H", a right-hand GEAR column, an optional SLIPSTREAM note and an optional N2O bar below.
class_name DashGauge
extends Control

const SEGMENTS := 26
const REF_W := 346.0 ## RaceHud's design width (scale 1.0)
const REF_H := 176.0 ## RaceHud's design height (scale 1.0)
const NITRO_BAND := 20.0 ## height reserved below the sweep when reserve_nitro is true

var speed_kmh := 0
var gear_text := "1"
var rev_frac := 0.0
var redline := false
var slipstream := false
var nitro := -1.0 ## 0..1 when the Nitrous modifier is on; negative hides the bar
var nitro_burning := false
var reserve_nitro := false ## keeps NITRO_BAND clear under the sweep so toggling nitro never shifts it
var tilt_skew := Vector2.ZERO ## subtle 2.5D cockpit shear driven by HudMotion (exact zero at rest)

## Optional audit hook: func(canvas: Control, font: Font, at: Vector2, s: String, align: int, width: float, size: int)
var audit_fn: Callable = Callable()

var _mesh_size := Vector2.ZERO
var _mesh_nitro := false
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
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
	return Color(CmrStyle.PLATE.darkened(0.4), a)

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

func _sweep_height() -> float:
	return maxf(1.0, size.y - (NITRO_BAND if reserve_nitro else 0.0))

func _scale(W: float, sweep_h: float) -> float:
	return minf(W / REF_W, sweep_h / REF_H)

## The rev band: slanted segments along a curve that rises and thickens toward the redline (CMR's swoosh).
func _build_mesh(W: float, sweep_h: float) -> void:
	_mesh_size = size
	_mesh_nitro = reserve_nitro
	var s := _scale(W, sweep_h)
	var n := SEGMENTS
	var arc_w := W - 84.0 * s
	var bottom := sweep_h - 8.0 * s
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	_indices = PackedInt32Array()
	for i in n:
		var t0 := float(i) / n
		var t1 := (i + 0.78) / n
		var p0 := Vector2(arc_w * t0, bottom - 96.0 * s * pow(t0, 2.6))
		var p1 := Vector2(arc_w * t1, bottom - 96.0 * s * pow(t1, 2.6))
		var d := (p1 - p0).normalized()
		var up := Vector2(d.y, -d.x)
		var poly := PackedVector2Array([p0, p1, p1 + up * ((10.0 + 22.0 * t1) * s), p0 + up * ((10.0 + 22.0 * t0) * s)])
		var k := _points.size()
		_points.append_array(poly)
		for j in 4:
			_colors.append(Color.WHITE)
		_indices.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))

func _draw() -> void:
	var W := size.x
	var H := size.y
	if W < 1.0 or H < 1.0:
		return
	if tilt_skew != Vector2.ZERO:
		var c := Vector2(W * 0.5, H * 0.5)
		var xf := Transform2D(Vector2(1.0, tilt_skew.y), Vector2(tilt_skew.x, 1.0), Vector2.ZERO)
		draw_set_transform_matrix(Transform2D(0.0, c) * xf * Transform2D(0.0, -c))
	var sweep_h := _sweep_height()
	if _mesh_size != size or _mesh_nitro != reserve_nitro:
		_build_mesh(W, sweep_h)
	var s := _scale(W, sweep_h)
	var lit := lit_segments(rev_frac)
	var text_col := CmrStyle.TEXT
	var muted_col := CmrStyle.MUTED
	var red_col := CmrStyle.RED
	var yellow_col := CmrStyle.ORANGE
	var blue_col := CmrStyle.VIOLET
	var bold := CmrStyle.font(600)
	var digits := CmrStyle.digits()

	var n := SEGMENTS
	for i in n:
		var t0 := float(i) / n
		var col := Color(text_col, 0.2)
		if i < lit:
			if redline and t0 >= 0.85:
				col = Color.WHITE
			else:
				col = red_col if t0 >= 0.9 else (yellow_col if t0 >= 0.78 else blue_col)
		for j in 4:
			_colors[i * 4 + j] = col
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _indices, _points, _colors)

	# the speed sits above the low end of the swoosh, the gear in the column its high end leaves free
	var gear_w := 84.0 * s
	_q(Vector2(0.0, 74.0 * s), "%d" % speed_kmh, maxi(12, roundi(88.0 * s)), text_col, digits, HORIZONTAL_ALIGNMENT_LEFT, W - 90.0 * s)
	_q(Vector2(0.0, 100.0 * s), "KM/H", maxi(10, roundi(17.0 * s)), muted_col, bold, HORIZONTAL_ALIGNMENT_LEFT, 80.0 * s)
	var gear_col := red_col if redline else (yellow_col if gear_text != "N" else muted_col)
	_q(Vector2(W - gear_w, sweep_h - 22.0 * s), gear_text, maxi(12, roundi(72.0 * s)), gear_col, bold, HORIZONTAL_ALIGNMENT_CENTER, gear_w)
	_q(Vector2(W - gear_w, sweep_h - 94.0 * s), "GEAR", maxi(10, roundi(12.0 * s)), muted_col, bold, HORIZONTAL_ALIGNMENT_CENTER, gear_w)

	if slipstream:
		_q(Vector2(0.0, 16.0 * s), "SLIPSTREAM", maxi(10, roundi(12.0 * s)), blue_col, bold, HORIZONTAL_ALIGNMENT_RIGHT, W)

	if nitro >= 0.0:
		var bar_y := sweep_h + 6.0 if reserve_nitro else H - 10.0
		var label_w := 40.0
		var bar := Rect2(label_w + 2.0, bar_y, maxf(10.0, W - label_w - 2.0), 8.0)
		draw_rect(bar, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(nitro, 0.0, 1.0), bar.size.y)), Color("#7fe8ff") if nitro_burning else Color("#3aa8ff"))
		_q(Vector2(0.0, bar_y + 9.0), "N2O", 12, muted_col, bold, HORIZONTAL_ALIGNMENT_LEFT, label_w)

	_q_flush()

func _q(at: Vector2, text: String, font_size: int, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_queued.append([maxi(2, font_size / 9), font, at, text, align, width, font_size, _shade(0.85 * color.a)])
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
