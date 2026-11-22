## The drift readout in the races and the open world, Forza / Unbound style: while the car slides, a slanted neon plate
## over the centre of the screen shows the slip angle, the running combo, its multiplier and the chain of linked slides
## (with the time left to link the next); when the combo banks, a punchy popup names it (GOOD / GREAT / INSANE DRIFT)
## and its points, or flashes COMBO LOST after a crash. Fed a DriftScore each frame (feed); draws nothing otherwise.
class_name DriftMeter
extends Control

const RED := Color("#ff4d4d")
const POP_IN := 0.16 ## s the popup's punch takes to settle
const POP_HOLD := 1.5 ## s it stays up
const POP_OUT := 0.45 ## s it fades over
const CHAIN_SEGS := 12 ## lit segments from x1 to DriftScore.MULT_MAX

var top_min := 0.0 ## px (this control's frame): the plate stays below this (the HUD's top-centre panels)
var _top := -1.0 ## the plate's eased top
var _ds: DriftScore = null
var _seen_t := -99.0
var _show := 0.0 ## the plate's fade, 0..1
var _angle := 0.0 ## deg, eased
var _points := 0
var _points_text := ""
var _mult := 1.0
var _mult_text := ""
var _mult_punch := 0.0 ## 1 when the multiplier just went up, easing to 0
var _link := 0.0 ## 0..1 of the link window left (no slide right now, a combo waiting)
var _drifting := false
var _pop_t := 99.0 ## s since the last popup
var _pop_title := ""
var _pop_points := ""
var _pop_col := Color.WHITE
var _pop_level := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## One frame: ds is the drift being scored (null: nothing to show; the plate fades and a popup plays out).
func feed(ds: DriftScore, dt: float) -> void:
	if ds != _ds:
		_ds = ds
		_seen_t = ds.event_t if ds else -99.0
	var want := 0.0
	if ds:
		if ds.event_t != _seen_t:
			_seen_t = ds.event_t
			_popup(ds.last_event, ds.event_points)
		var pend := ds.pending()
		_drifting = ds.drifting
		if pend > 0 or ds.drifting:
			want = 1.0
			if pend != _points:
				_points = pend
				_points_text = OpenWorldHud._thousands(pend)
			if ds.mult > _mult + 0.01:
				_mult_punch = 1.0
			if absf(ds.mult - _mult) > 0.01 or _mult_text == "":
				_mult = ds.mult
				_mult_text = "×%.1f" % ds.mult
			_link = 0.0 if ds.drifting else clampf(1.0 - ds.idle / DriftScore.LINK, 0.0, 1.0)
		_angle = lerpf(_angle, rad_to_deg(ds.angle) if ds.drifting else 0.0, 1.0 - exp(-dt * 10.0))
	_show = move_toward(_show, want, dt * (6.0 if want > _show else 3.0))
	var top_want := maxf(size.y * 0.205, top_min)
	_top = top_want if _top < 0.0 or _show <= 0.0 else lerpf(_top, top_want, 1.0 - exp(-dt * 8.0))
	if _show <= 0.0:
		_mult = 1.0
		_mult_text = ""
	_mult_punch = move_toward(_mult_punch, 0.0, dt * 4.0)
	_pop_t += dt
	if _show > 0.0 or _pop_t < POP_IN + POP_HOLD + POP_OUT or _mult_punch > 0.0:
		queue_redraw()
	elif _pop_t < POP_IN + POP_HOLD + POP_OUT + 0.1:
		queue_redraw() # one last frame to clear it

## Off (a menu, a replay, the race over): everything gone at once.
func clear() -> void:
	_ds = null
	_show = 0.0
	_pop_t = 99.0
	queue_redraw()

func _popup(kind: String, pts: int) -> void:
	if kind == "BANKED" and pts > 0:
		_pop_level = DriftStyle.label_index(pts)
		_pop_title = String(DriftStyle.LABELS[_pop_level][1]) + "!"
		_pop_col = [HudLayout.neon_primary(), HudLayout.neon_primary(), HudLayout.neon_boost(), HudLayout.neon_hot()][_pop_level]
		_pop_points = "+" + OpenWorldHud._thousands(pts)
	elif kind == "LOST" and pts >= 50:
		_pop_level = 0
		_pop_title = "COMBO LOST"
		_pop_col = RED
		_pop_points = "−" + OpenWorldHud._thousands(pts)
	else:
		return
	_pop_t = 0.0

func _draw() -> void:
	var s := HudLayout.hud_scale(size)
	var cx := size.x * 0.5
	var top := _top if _top >= 0.0 else maxf(size.y * 0.205, top_min)
	if _show > 0.001:
		_draw_plate(cx, top, s, _show)
	var life := POP_IN + POP_HOLD + POP_OUT
	if _pop_t < life:
		_draw_popup(cx, top + (8.0 if _show > 0.5 else 0.0) * s + 118.0 * s * _show, s)

func _draw_plate(cx: float, top: float, s: float, a: float) -> void:
	var w := 360.0 * s
	var h := 84.0 * s
	var hot := HudLayout.neon_hot()
	var cyan := HudLayout.neon_primary()
	var boost := HudLayout.neon_boost()
	var ps1 := CmrStyle.skin == "ps1"
	# slide in from above as it appears, slanted like the rest of the HUD's plates
	var y := top - (1.0 - a) * 14.0 * s
	draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(0.0 if ps1 else -0.14, 1.0), Vector2(cx - w * 0.5 + (0.0 if ps1 else 0.14 * h * 0.5), y)))
	var accent := cyan.lerp(hot, clampf((_mult - 1.0) / (DriftScore.MULT_MAX - 1.0), 0.0, 1.0))
	HudLayout.draw_neon_panel(self, Rect2(0.0, 0.0, w, h), accent, 0.88 * a, 6.0 * s, true)
	# the slip angle, a bar along the top that runs hot past 45 degrees
	var af := clampf(_angle / 70.0, 0.0, 1.0)
	draw_rect(Rect2(0.0, 0.0, w, 3.0 * s), Color(accent, 0.25 * a))
	draw_rect(Rect2(0.0, 0.0, w * af, 3.0 * s), Color(cyan.lerp(hot, smoothstep(0.45, 0.8, af)), a))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var x0 := cx - w * 0.5
	var title := HudLayout.italic_font(900, -0.14)
	var digits := HudLayout.italic_digits()
	var tfs := maxi(12, roundi(16.0 * s))
	draw_string(title, Vector2(x0 + 18.0 * s, y + 24.0 * s), "DRIFT", HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(1, 1, 1, 0.92 * a))
	if _drifting or _angle > 1.0:
		draw_string(digits, Vector2(x0 + 76.0 * s, y + 24.0 * s), "%d°" % roundi(_angle), HORIZONTAL_ALIGNMENT_LEFT, -1, tfs + roundi(2.0 * s), Color(boost, a))
	# the running combo, big
	var bfs := maxi(24, roundi(42.0 * s))
	var bx := x0 + 18.0 * s
	var by := y + 68.0 * s
	if not ps1:
		draw_string_outline(digits, Vector2(bx, by), _points_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, maxi(3, roundi(8.0 * s)), Color(accent, 0.28 * a))
	draw_string(digits, Vector2(bx, by), _points_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, Color(1, 1, 1, a))
	# the multiplier chip, punched up when it rises
	var mfs := maxi(16, roundi(30.0 * s * (1.0 + 0.35 * _mult_punch)))
	var mw := digits.get_string_size(_mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs).x
	var mx := x0 + w - 20.0 * s - mw
	var my := y + 58.0 * s
	if _mult_punch > 0.0:
		HudLayout.draw_radial_glow(self, Vector2(mx + mw * 0.5, my - mfs * 0.3), 60.0 * s * _mult_punch, Color(hot, 0.5 * _mult_punch * a))
	draw_string_outline(digits, Vector2(mx, my), _mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs, maxi(2, roundi(5.0 * s)), Color(0, 0, 0, 0.55 * a))
	draw_string(digits, Vector2(mx, my), _mult_text, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs, Color(hot.lerp(boost, _mult_punch), a))
	# the chain: one segment per linked slide or held second, up to the top multiplier
	var lit := clampi(roundi((_mult - 1.0) / DriftScore.MULT_STEP), 0, CHAIN_SEGS)
	var seg_w := 9.0 * s
	var gap := 3.0 * s
	var cxs := x0 + w - 20.0 * s - CHAIN_SEGS * (seg_w + gap) + gap
	var cys := y + h - 14.0 * s
	for i in CHAIN_SEGS:
		var on := i < lit
		draw_rect(Rect2(cxs + i * (seg_w + gap), cys, seg_w, 5.0 * s), Color(hot, (0.95 if on else 0.18) * a))
	# the link window: a draining bar under the plate while the combo waits for the next slide
	if _link > 0.0:
		draw_rect(Rect2(x0 + 8.0 * s, y + h + 5.0 * s, (w - 16.0 * s) * _link, 4.0 * s), Color(boost, 0.85 * a))

func _draw_popup(cx: float, y: float, s: float) -> void:
	var t := _pop_t
	var a := 1.0 if t < POP_IN + POP_HOLD else clampf(1.0 - (t - POP_IN - POP_HOLD) / POP_OUT, 0.0, 1.0)
	# punch: in big and settle with a little overshoot; INSANE punches harder
	var k := clampf(t / POP_IN, 0.0, 1.0)
	var punch := 1.0 + (0.7 + 0.25 * _pop_level) * (1.0 - k) * (1.0 - k) - 0.06 * sin(k * PI)
	var rise := -10.0 * s * maxf(0.0, t - POP_IN - POP_HOLD) / POP_OUT
	var title := HudLayout.italic_font(900, -0.16)
	var digits := HudLayout.italic_digits()
	var tfs := maxi(20, roundi((34.0 + 4.0 * _pop_level) * s))
	var pfs := maxi(16, roundi(26.0 * s))
	draw_set_transform(Vector2(cx, y + rise), 0.0, Vector2.ONE * punch)
	if _pop_level >= 2 and CmrStyle.skin != "ps1":
		HudLayout.draw_radial_glow(self, Vector2(0.0, tfs * 0.1), 150.0 * s, Color(_pop_col, 0.35 * a))
	var tw := title.get_string_size(_pop_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
	draw_string_outline(title, Vector2(-tw * 0.5, tfs * 0.35), _pop_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, maxi(4, roundi(9.0 * s)), Color(0, 0, 0, 0.6 * a))
	draw_string(title, Vector2(-tw * 0.5, tfs * 0.35), _pop_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(_pop_col, a))
	var pw := digits.get_string_size(_pop_points, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
	draw_string_outline(digits, Vector2(-pw * 0.5, tfs * 0.35 + pfs * 1.15), _pop_points, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, maxi(3, roundi(7.0 * s)), Color(0, 0, 0, 0.55 * a))
	draw_string(digits, Vector2(-pw * 0.5, tfs * 0.35 + pfs * 1.15), _pop_points, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color(1, 1, 1, a))
	draw_set_transform_matrix(Transform2D.IDENTITY)
