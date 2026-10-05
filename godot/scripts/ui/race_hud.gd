## In-race HUD (port of the HUD half of js/ui.js) in the style of Colin McRae Rally 2.0: standings as
## light gradient bars top left, a lime pace-note box for the next corner top centre, the segmented lap
## progress and stage-style clock top right, a segmented rev arc with a big gear digit bottom right, plus
## the pit wall, event feed, minimap, start lights, banner, key help and name tags. Each panel is one
## custom-drawn Control; text panels redraw at about 8 Hz like the reference, the dash, pace note,
## minimap and tags every frame. Laid out on the 1600×900 design canvas and scaled with the window.
class_name RaceHud
extends Control

const INK := CmrStyle.INK
const TEXT := CmrStyle.TEXT
const MUTED := CmrStyle.MUTED
const RED := CmrStyle.RED
const YELLOW := CmrStyle.ORANGE
const GOOD := CmrStyle.VIOLET
const PURPLE := CmrStyle.PLUM
const BLUE := CmrStyle.VIOLET
# Colours: shorthands for the CmrStyle palette plus a few HUD-only tints
const METER_BG := Color(0, 0, 0, 0.35)
const CHIP_BG := Color(0.13, 0.08, 0.2, 0.85)
const BAR_HI := Color(0.97, 0.95, 1.0, 0.9) ## opaque end of the CMR gradient bars
const BAR_LO := Color(0.55, 0.36, 0.85, 0.35) ## faded end, violet where CMR has blue
# Layout, in pixels on the 1600×900 design canvas
const REFRESH := 0.12 ## s between redraws of the text panels (about 8 Hz, like the reference)
const ROW_H := 21.0 ## height of one timing-tower row
const TOWER_W := 262.0 ## timing tower (standings) width
const PITWALL_W := 330.0 ## pit-wall panel width
const FEED_W := 330.0 ## event feed width
const CLOCK_W := 300.0 ## lap / clock panel width
const MAP_S := 190.0 ## minimap size (square)
const REPAIR_AT_HUD := 0.3 ## the damage at which the gauge turns red (RaceControl.REPAIR_AT)
const FEED_BORDER := {"good": GOOD, "bad": RED, "warn": CmrStyle.ORANGE_SOFT, "box": YELLOW, "pit": Color("#8a8f99"),
	"purple": PURPLE, "ai": Color("#2ec4b6"), "rc": Color("#ffcc00")}
const HELP_TEXT := "↑/W throttle · ↓/S/Space brake · ←→/AD steer · E/Q gear (manual)\nP box request · [ ] next tyre · − = fuel · R ask strategist\nV flag speed limiter · C camera · L racing line · G ghost car · O autopilot / co-driver · M mute · H hide · Esc pause · , . time warp"

var race: Race
var records: LapRecords ## the player's lap record here, for the gap to it (null: no record row)
var world: Node3D
var audio: RaceAudio
var warp := 1
## Text shown under the banner while the rest of the race is simulated (set by the game).
var skip_note := ""

var tower: Control
var clock: Control
var pacenote: Control
var lights: Control
var banner: Label
var banner_small: Label
var feed: Control
var pitwall: Control
var dash: Control
var minimap: Control
var minimap_base: Control ## the map's backdrop, line and flags under minimap's dots, redrawn only when they change
var tags: Control
var help: PanelContainer
var flagbar: Control

var _font: Font
var _bold: Font
var _digits: Font
var _panel_style: StyleBoxFlat
var _lights_style: StyleBoxFlat
var _refresh_t := 0.0
var _clock := 0.0
var _event_seen := 0
var _last_flag := ""
var _fitted := {} ## name -> name shortened to fit the tower column
var _sheet: Array = [] ## qualifying: the live time sheet the tower shows
var _map_track: Track
var _map_size := Vector2.ZERO
var _map_points := PackedVector2Array()
var _map_start := PackedVector2Array()
var _map_scale := 1.0
var _map_origin := Vector2.ZERO
var _map_key := "" ## what minimap_base last drew (track, size, flags)
var _dash_key := [] ## what the dash last drew (size, lit segments, gear, speed)
var _dash_points := PackedVector2Array() ## the rev band's segments and their outlines, built once per size
var _dash_colors := PackedColorArray()
var _dash_indices := PackedInt32Array()
var _dash_size := Vector2.ZERO
## Batching: every polygon, circle, arc and polyline drawn on its own is a separate draw call, and text
## between them breaks the glyph batches too (the HUD came to over 500 draw calls a frame). The busy
## panels gather their flat shapes into one triangle list (_tri_*), draw circles from small textures
## (_round_tex) and queue their text (_q) to draw grouped by font and size once the shapes are down.
var _tri_points := PackedVector2Array()
var _tri_colors := PackedColorArray()
var _tri_indices := PackedInt32Array()
var _queued: Array = [] ## [outline size (0 plain), font, at, text, align, width, size, colour]
var _round_textures := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = CmrStyle.font(400)
	_bold = CmrStyle.font(600)
	_digits = CmrStyle.digits()
	_panel_style = CmrStyle.panel(Color(0.13, 0.08, 0.2, 0.8), Color(CmrStyle.VIOLET, 0.5), 0)
	_lights_style = StyleBoxFlat.new()
	_lights_style.bg_color = Color("#0b0b0d")
	_lights_style.border_color = Color("#222222")
	_lights_style.set_border_width_all(2)

	tags = _canvas(_draw_tags)
	tags.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tower = _canvas(_draw_tower)
	tower.position = Vector2(14, 14)
	tower.size = Vector2(TOWER_W + 20, 40)
	pacenote = _canvas(_draw_pacenote)
	_place(pacenote, 0.5, 0.0, 0.5, 0.0, -150, 14, 150, 124)
	clock = _canvas(_draw_clock)
	_place(clock, 1.0, 0.0, 1.0, 0.0, -14 - CLOCK_W - 20, 14, -14, 222)
	lights = _canvas(_draw_lights)
	flagbar = _canvas(_draw_flag)
	_place(flagbar, 0.5, 0.0, 0.5, 0.0, -210, 132, 210, 186)
	_place(lights, 0.0, 0.0, 1.0, 0.0, 0, 140, 0, 212)
	minimap_base = _canvas(_draw_minimap_base)
	_place(minimap_base, 1.0, 0.0, 1.0, 0.0, -14 - MAP_S, 224, -14, 224 + MAP_S)
	minimap = _canvas(_draw_minimap)
	_place(minimap, 1.0, 0.0, 1.0, 0.0, -14 - MAP_S, 224, -14, 224 + MAP_S)
	feed = _canvas(_draw_feed)
	_place(feed, 1.0, 0.0, 1.0, 0.0, -14 - FEED_W, 428, -14, 700)
	pitwall = _canvas(_draw_pitwall)
	_place(pitwall, 0.0, 1.0, 0.0, 1.0, 14, -214, 14 + PITWALL_W, -14)
	dash = _canvas(_draw_dash)
	_place(dash, 1.0, 1.0, 1.0, 1.0, -360, -190, -14, -14)

	var banner_box := VBoxContainer.new()
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(banner_box, 0.5, 0.3, 0.5, 0.3, -400, -40, 400, 60)
	banner_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(banner_box)
	banner = _banner_label(46)
	banner_box.add_child(banner)
	banner_small = _banner_label(18)
	banner_small.add_theme_color_override("font_color", CmrStyle.MUTED)
	banner_box.add_child(banner_small)

	help = PanelContainer.new()
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var help_style := CmrStyle.box(Color(0.13, 0.08, 0.2, 0.62), Color.TRANSPARENT, 18, 6)
	help.add_theme_stylebox_override("panel", help_style)
	var help_label := Label.new()
	help_label.text = HELP_TEXT
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_override("font", _font)
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", Color("#cfe0f5"))
	help.add_child(help_label)
	help.anchor_left = 0.5
	help.anchor_right = 0.5
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_bottom = -14
	add_child(help)

## Hand the HUD a new race.
func start(race_: Race, world_: Node3D, audio_: RaceAudio) -> void:
	race = race_
	world = world_
	audio = audio_
	warp = 1
	skip_note = ""
	_event_seen = 0
	_last_flag = ""
	_refresh_t = 0.0
	_map_track = null
	_map_key = ""
	_dash_key = []
	_fitted.clear()
	_sheet = Qualifying.sheet(race) if race.s.qualifying else []
	pitwall.visible = not race.s.qualifying # nobody pits in qualifying
	help.visible = true
	show()
	update(0.0)

func toggle_help() -> void:
	help.visible = not help.visible

## Call once per frame while a race is on screen.
func update(dt: float) -> void:
	if not race:
		return
	_clock += dt
	var dash_key := _dash_state()
	if dash_key != _dash_key:
		_dash_key = dash_key
		dash.queue_redraw()
	pacenote.queue_redraw()
	flagbar.queue_redraw()
	if _minimap_key() != _map_key:
		minimap_base.queue_redraw()
	minimap.queue_redraw()
	tags.queue_redraw()
	_refresh_t -= dt
	if _refresh_t > 0.0:
		return
	_refresh_t = REFRESH
	if race.s.qualifying:
		_sheet = Qualifying.sheet(race)
	tower.size.y = (_sheet.size() if race.s.qualifying else race.order.size()) * (ROW_H + 2.0)
	var pw_h := _pitwall_height()
	pitwall.offset_top = -14.0 - pw_h
	tower.queue_redraw()
	clock.queue_redraw()
	lights.queue_redraw()
	feed.queue_redraw()
	pitwall.queue_redraw()
	_update_banner()
	_update_event_sounds()

# ---------------- helpers ----------------
func _canvas(fn: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	add_child(c)
	return c

static func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

func _banner_label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", _bold)
	l.add_theme_color_override("font_outline_color", Color(0.01, 0.05, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 12 if size > 20 else 6)
	return l

func _text(c: Control, at: Vector2, s: String, size: int, color: Color, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	c.draw_string(_bold if bold else _font, at, s, align, width, size, color)

## White HUD type straight over the 3D view gets a dark outline, as in CMR.
func _text_o(c: Control, at: Vector2, s: String, size: int, color: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := font if font else _bold
	c.draw_string_outline(f, at, s, align, width, size, maxi(2, size / 9), Color(0.08, 0.03, 0.12, 0.85 * color.a))
	c.draw_string(f, at, s, align, width, size, color)

## The CMR 2.0 bar: a plain rectangle, bright at one end fading to translucent violet at the other.
func _gbar(c: Control, rect: Rect2, hi := BAR_HI, lo := BAR_LO, flip := false) -> void:
	var a := hi if not flip else lo
	var b := lo if not flip else hi
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	c.draw_polygon(pts, PackedColorArray([a, b, b, a]))

## A quad into the panel's triangle list, corners clockwise from the top left with their own colours.
func _tri_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var i := _tri_points.size()
	_tri_points.append(a)
	_tri_points.append(b)
	_tri_points.append(c)
	_tri_points.append(d)
	_tri_colors.append(ca)
	_tri_colors.append(cb)
	_tri_colors.append(cc)
	_tri_colors.append(cd)
	_tri_indices.append_array(PackedInt32Array([i, i + 1, i + 2, i, i + 2, i + 3]))

func _tri_rect(rect: Rect2, col: Color) -> void:
	_tri_quad(rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), col, col, col, col)

## _gbar into the triangle list.
func _tri_gbar(rect: Rect2, hi := BAR_HI, lo := BAR_LO) -> void:
	_tri_quad(rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), hi, lo, lo, hi)

## A polyline into the triangle list: width wide with a pixel of soft edge each side, like an
## antialiased draw_polyline (which Godot splits into dozens of draw calls). closed when it ends where it starts.
func _tri_strip(pts: PackedVector2Array, width: float, col: Color, closed := false) -> void:
	var n := pts.size()
	if n < 2:
		return
	var clear := Color(col, 0.0)
	var half := width * 0.5
	var base := _tri_points.size()
	for i in n:
		var prev := pts[i - 1] if i > 0 else (pts[n - 2] if closed else pts[0])
		var next := pts[i + 1] if i < n - 1 else (pts[1] if closed else pts[n - 1])
		var n1 := (pts[i] - prev).normalized().orthogonal() if pts[i] != prev else Vector2.ZERO
		var n2 := (next - pts[i]).normalized().orthogonal() if next != pts[i] else Vector2.ZERO
		var m := (n1 + n2).normalized() if n1 + n2 != Vector2.ZERO else (n1 if n1 != Vector2.ZERO else n2)
		# mitre the corner, but not into a spike on a hairpin
		var k := 1.0 / maxf(0.5, m.dot(n1 if n1 != Vector2.ZERO else n2))
		for off in [half + 1.0, half, -half, -half - 1.0]:
			_tri_points.append(pts[i] + m * off * k)
		_tri_colors.append(clear)
		_tri_colors.append(col)
		_tri_colors.append(col)
		_tri_colors.append(clear)
	for i in n - 1:
		var a := base + i * 4
		var b := a + 4
		for band in 3:
			_tri_indices.append_array(PackedInt32Array([a + band, b + band, b + band + 1, a + band, b + band + 1, a + band + 1]))

## Draws the triangle list in one call and empties it.
func _tri_flush(c: Control) -> void:
	if not _tri_indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), _tri_indices, _tri_points, _tri_colors)
	_tri_points.clear()
	_tri_colors.clear()
	_tri_indices.clear()

## Text for _q_flush (outlined like _text_o when outline).
func _q(at: Vector2, s: String, size: int, color: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := false) -> void:
	var f := font if font else _bold
	if outline:
		_queued.append([maxi(2, size / 9), f, at, s, align, width, size, Color(0.08, 0.03, 0.12, 0.85 * color.a)])
	_queued.append([0, f, at, s, align, width, size, color])

## The queued text, outlines first, grouped by font and size so each group's glyphs batch together.
func _q_flush(c: Control) -> void:
	var groups := {}
	var keys: Array = []
	for t in _queued:
		var key := Vector3i(-t[0], t[1].get_instance_id() % 1000003, t[6])
		if not groups.has(key):
			groups[key] = []
			keys.append(key)
		groups[key].append(t)
	keys.sort()
	for key in keys:
		for t in groups[key]:
			if t[0] > 0:
				c.draw_string_outline(t[1], t[2], t[3], t[4], t[5], t[6], t[0], t[7])
			else:
				c.draw_string(t[1], t[2], t[3], t[4], t[5], t[6], t[7])
	_queued.clear()

## A white antialiased disc (inner 0) or ring (inner: hole radius over outer radius) px texels across,
## tinted when drawn with _round.
func _round_tex(px: int, inner: float) -> Texture2D:
	var key := "%d:%.3f" % [px, inner]
	if _round_textures.has(key):
		return _round_textures[key]
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var half := px * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length()
			var a := clampf(half - d + 0.5, 0.0, 1.0)
			if inner > 0.0:
				a = minf(a, clampf(d - inner * half + 0.5, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_round_textures[key] = tex
	return tex

## A disc or ring of outer radius r from _round_tex (drawn about two texels per HUD pixel).
func _round(c: Control, center: Vector2, r: float, col: Color, inner := 0.0) -> void:
	var tex := _round_tex(maxi(8, ceili(r) * 4), inner)
	c.draw_texture_rect(tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, col)

func _text_w(s: String, size: int, bold := false) -> float:
	return (_bold if bold else _font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func _fit(s: String, size: int, width: float) -> String:
	var key := "%s|%d|%d" % [s, size, int(width)]
	if _fitted.has(key):
		return _fitted[key]
	var out := s
	if _text_w(out, size, true) > width:
		while out.length() > 1 and _text_w(out + "…", size, true) > width:
			out = out.left(-1)
		out += "…"
	_fitted[key] = out
	return out

## Round tyre badge: compound letter in a ring of the compound's colour.
func _badge(c: Control, center: Vector2, compound, big := false) -> void:
	var r := 13.0 if big else 8.5
	var key: String = compound if compound else "M"
	var col: Color = race.tyres.compounds[key].color
	c.draw_circle(center, r, Color("#111111"))
	c.draw_arc(center, r - (1.75 if big else 1.25), 0.0, TAU, 24, col, 3.5 if big else 2.5, true)
	var size := 12 if big else 9
	c.draw_string(_bold, center + Vector2(-r, size * 0.36), key, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size, col)

func _meter(c: Control, rect: Rect2, frac: float, col: Color) -> void:
	c.draw_rect(rect, METER_BG)
	c.draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(frac, 0.0, 1.0), rect.size.y)), col)

static func _clock_text(sec: float) -> String:
	var t := maxi(0, int(floorf(sec)))
	var h := t / 3600
	var m := (t % 3600) / 60
	var s := t % 60
	return "%d:%02d:%02d" % [h, m, s] if h > 0 else "%d:%02d" % [m, s]

static func _whole_time(t) -> String:
	var s := Race.fmt_time(t)
	var dot := s.rfind(".")
	return s.left(dot) if dot >= 0 else s

# ---------------- tower ----------------
func _gap_text(car: RaceCar, leader: RaceCar, i: int) -> String:
	var L := race.track.L
	if car.dnf:
		return "OUT"
	if i == 0:
		if car.finished:
			return "FINISH"
		return "LAP %d" % ((car.lap + 1) if race.timed else mini(car.lap + 1, race.R))
	if car.finished and leader.finish_time != null and car.finish_time != null:
		var laps_down := leader.finish_lap - car.finish_lap
		return "+%dL" % laps_down if laps_down > 0 else "+%.1f" % (car.finish_time - leader.finish_time)
	if car.mode == "pit":
		return "PIT"
	var lead: float = leader.finish_lap * L if leader.finished else leader.lap * L + leader.s
	var down := int(floorf((lead - (car.lap * L + car.s)) / L))
	if down >= 1:
		return "+%dL" % down
	return "+%.1f" % maxf(0.0, car.gap)

## Qualifying: the time sheet instead of the running order, pole on top.
func _draw_sheet() -> void:
	for i in _sheet.size():
		var r: Dictionary = _sheet[i]
		var y := i * (ROW_H + 2.0)
		if r.is_player:
			_gbar(tower, Rect2(0, y, TOWER_W, ROW_H), YELLOW, Color(YELLOW, 0.55))
		else:
			_gbar(tower, Rect2(0, y, TOWER_W, ROW_H), BAR_HI, BAR_LO)
		var base := y + 15.5
		_text(tower, Vector2(4, base), str(i + 1), 13, INK, true, HORIZONTAL_ALIGNMENT_RIGHT, 24)
		tower.draw_rect(Rect2(36, y + 3, 4, 15), r.color)
		_text(tower, Vector2(44, base), str(r.number), 11, CmrStyle.INK_SOFT, true, HORIZONTAL_ALIGNMENT_RIGHT, 26)
		var nm: String = str(r.name).to_upper() if r.is_player else str(r.name).split(" ")[-1].to_upper()
		_text(tower, Vector2(78, base), _fit(nm, 12, 64), 12, INK, true)
		var t := "—"
		if r.time != null:
			t = Race.fmt_time(r.time) if i == 0 else "+%.3f" % r.gap
		_text(tower, Vector2(136, base), t, 12, INK, true, HORIZONTAL_ALIGNMENT_RIGHT, 100)

func _draw_tower() -> void:
	if not race:
		return
	if race.s.qualifying:
		_draw_sheet()
		return
	var order := race.order
	var leader: RaceCar = order[0]
	# shapes first, then the badges' discs and rings, then all the text (see _tri_quad)
	var badges: Array = [] ## [centre, colour]
	for i in order.size():
		var c: RaceCar = order[i]
		var y := i * (ROW_H + 2.0)
		var fade := 0.45 if c.dnf else 1.0
		if c.is_player:
			_tri_gbar(Rect2(0, y, TOWER_W, ROW_H), YELLOW, Color(YELLOW, 0.55))
		else:
			_tri_gbar(Rect2(0, y, TOWER_W, ROW_H), Color(BAR_HI, BAR_HI.a * fade), Color(BAR_LO, BAR_LO.a * fade))
		var base := y + 15.5
		_q(Vector2(4, base), str(i + 1), 13, Color(INK, fade), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 24)
		_tri_rect(Rect2(36, y + 3, 4, 15), Color(c.color, fade))
		if c.damage > 0.05:
			# damage gauge: a thin bar beside the team colour, orange then red as the car gets worse
			var dh := 15.0 * clampf(c.damage, 0.15, 1.0)
			_tri_rect(Rect2(41, y + 18 - dh, 2, dh), Color(RED if c.damage >= REPAIR_AT_HUD else CmrStyle.ORANGE_SOFT, fade))
		_q(Vector2(44, base), str(c.number), 11, Color(CmrStyle.INK_SOFT, fade), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 26)
		var nm := c.name.to_upper() if c.is_player else Brain.short(c).to_upper()
		_q(Vector2(78, base), _fit(nm, 12, 64), 12, Color(INK, fade))
		var pit := c.mode == "pit"
		_q(Vector2(146, base), _gap_text(c, leader, i), 12, Color(Color("#a02000") if pit else INK, fade), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 62)
		# _badge: the compound letter in a ring of the compound's colour on a dark disc
		var key: String = c.tyre.c if c.tyre.c else "M"
		var center := Vector2(223, y + 10.5)
		badges.append([center, race.tyres.compounds[key].color])
		_q(center + Vector2(-8.5, 9 * 0.36), key, 9, race.tyres.compounds[key].color, _bold, HORIZONTAL_ALIGNMENT_CENTER, 17.0)
		_q(Vector2(236, base), str(c.stops), 11, Color(INK, fade), _bold, HORIZONTAL_ALIGNMENT_RIGHT, 16)
	_tri_flush(tower)
	for b in badges:
		_round(tower, b[0], 8.5, Color("#111111"))
	for b in badges:
		_round(tower, b[0], 8.5, b[1], 6.0 / 8.5)
	_q_flush(tower)

# ---------------- clock stack (top right) ----------------
## Segmented lap progress, the big clock, then lap / position / lap-time rows fading to the left.
func _draw_clock() -> void:
	if not race:
		return
	var p := race.player
	var W := CLOCK_W
	var x0 := clock.size.x - W
	# progress through the lap in green blocks, like CMR's stage splits
	var segs := 12
	var frac := clampf(p.s / race.track.L, 0.0, 1.0) if race.phase == "racing" else 0.0
	var sw := (W - (segs - 1) * 3.0) / segs
	for k in segs:
		var r := Rect2(x0 + k * (sw + 3.0), 0, sw, 12)
		var fill := clampf(frac * segs - k, 0.0, 1.0)
		clock.draw_rect(r, Color(0.13, 0.08, 0.2, 0.55))
		if fill > 0.0:
			clock.draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), YELLOW)
		clock.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
	# the clock
	var time_text: String
	var quali := race.s.qualifying
	if quali:
		time_text = Race.fmt_time(maxf(0.0, race.race_time - p.lap_start)) if race.phase == "racing" else "0:00.00"
	elif race.timed:
		if race.phase == "countdown":
			time_text = _clock_text(race.duration)
		else:
			time_text = _clock_text(race.time_left) if race.time_left > 0.0 else "FINAL"
	else:
		time_text = "0:00.00" if race.phase == "countdown" else Race.fmt_time(race.race_time)
	var box := Rect2(x0, 18, W, 58)
	var box_style := CmrStyle.box(BAR_HI, Color.TRANSPARENT, 0, 0)
	box_style.border_color = Color(1, 1, 1, 0.9)
	box_style.border_width_top = 2
	box_style.draw(clock.get_canvas_item(), box)
	var clock_label := "TIME LEFT" if race.timed else "RACE"
	if quali:
		clock_label = "OUT LAP" if p.lap == 0 else "TIMED LAP %d / %d" % [mini(p.lap, race.R - 1), race.R - 1]
	_text(clock, Vector2(x0 + 14, 34), clock_label, 11, CmrStyle.INK_SOFT, true)
	if records and records.ghost_time != null:
		# under the label: how far behind (+) or ahead (−) of the lap record this lap is, or the record itself
		var gap = records.gap()
		_text(clock, Vector2(x0 + 14, 50), "VS RECORD" if gap != null else "RECORD", 10, CmrStyle.INK_SOFT, true)
		if gap != null:
			_text(clock, Vector2(x0 + 14, 70), "%s%.2f" % ["+" if gap >= 0.0 else "−", absf(gap)], 18, RED if gap >= 0.0 else PURPLE, true)
		else:
			_text(clock, Vector2(x0 + 14, 67), Race.fmt_time(records.ghost_time), 13, CmrStyle.INK_SOFT, true)
	clock.draw_string(_digits, Vector2(x0, 68), time_text, HORIZONTAL_ALIGNMENT_RIGHT, W - 18, 38, INK)
	# rows
	var lap := str(p.lap + 1) if race.timed else "%d / %d" % [mini(p.lap + 1, race.R), race.R]
	var best_col := PURPLE if race.fastest and race.fastest.car == p else INK
	var current := Race.fmt_time(race.race_time - p.lap_start) if race.phase == "racing" else "—"
	var rows := [["LAP", lap, INK], ["POS", "%d / %d" % [p.pos, race.cars.size()], INK],
		["THIS LAP", current, INK], ["LAST", Race.fmt_time(p.last_lap), INK], ["BEST", Race.fmt_time(p.best_lap), best_col]]
	if quali:
		var pole = _sheet[0].time if not _sheet.is_empty() else null
		var mine := 0
		for k in _sheet.size():
			if _sheet[k].is_player:
				mine = k + 1
		rows = [["LAP", "OUT" if p.lap == 0 else "%d / %d" % [mini(p.lap, race.R - 1), race.R - 1], INK],
			["GRID", "P%d / %d" % [mine, _sheet.size()] if p.best_lap != null else "—", INK],
			["LAST", Race.fmt_time(p.last_lap) if p.lap > 1 else "—", INK], ["BEST", Race.fmt_time(p.best_lap), PURPLE if mine == 1 and p.best_lap != null else INK],
			["POLE", Race.fmt_time(pole), INK]]
	var y := 82.0
	for row in rows:
		_gbar(clock, Rect2(x0 + 40, y, W - 40, 20), BAR_HI, Color(BAR_HI, 0.55), true)
		_text(clock, Vector2(x0 + 56, y + 15), row[0], 11, CmrStyle.INK_SOFT, true)
		_text(clock, Vector2(x0 + 60, y + 15.5), row[1], 14, row[2], true, HORIZONTAL_ALIGNMENT_RIGHT, W - 72)
		y += 22.0
	# weather and local time, on a dark plate so it reads over a bright sky or a busy background
	var tod := race.time_of_day
	var clock_text := "%02d:%02d" % [int(tod), int(fmod(tod, 1.0) * 60.0)]
	if warp > 1:
		clock_text += "  ×%d" % warp
	var w := race.weather
	var sky := "RAIN" if w.rain > 0.05 else ("DAMP" if w.wet > 0.05 else "DRY")
	var weather_text := "%s %d%% · %s · %s" % [sky, roundi(w.wet * 100.0), w.forecast(maxf(0.0, race.race_time)), clock_text]
	var tw := minf(W, _text_w(weather_text, 12) + 16.0)
	clock.draw_rect(Rect2(x0 + W - tw, y + 1, tw, 17), Color(0.08, 0.03, 0.12, 0.62))
	_text_o(clock, Vector2(x0, y + 14), weather_text, 12, TEXT, _font, HORIZONTAL_ALIGNMENT_RIGHT, W - 8)

# ---------------- pace note (top centre) ----------------
## The co-driver's call for the next corner: CMR's lime box with a black arrow bent by how far the
## road turns over the next stretch, and the corner's name underneath.
func _draw_pacenote() -> void:
	if not race:
		return
	var p := race.player
	var tr := race.track
	var turn := SimUtil.wrap_angle(tr.heading(p.s + 170.0) - tr.heading(p.s + 25.0))
	var side := clampf(turn / 1.6, -1.0, 1.0)
	var S := 74.0
	var cx := pacenote.size.x * 0.5
	var box := Rect2(cx - S * 0.5, 0, S, S)
	pacenote.draw_rect(box, YELLOW)
	pacenote.draw_rect(box, Color(0, 0, 0, 0.9), false, 3.0)
	# arrow: straight up, then bending toward the corner
	var base := Vector2(cx - side * 10.0, S - 12.0)
	var pts := PackedVector2Array()
	for k in 9:
		var t := k / 8.0
		var up := base + Vector2(0, -t * 46.0)
		up.x += side * 30.0 * t * t
		up.y += absf(side) * 14.0 * t * t * t
		pts.append(up)
	pacenote.draw_polyline(pts, Color.BLACK, 6.0, true)
	var tip := pts[pts.size() - 1]
	var dir := (tip - pts[pts.size() - 2]).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	pacenote.draw_colored_polygon(PackedVector2Array([tip + dir * 11.0, tip + nrm * 9.0, tip - nrm * 9.0]), Color.BLACK)
	var sector := tr.sector_name(p.s)
	if sector != "":
		var tw := _text_w(sector.to_upper(), 13, true) + 28.0
		var r := Rect2(cx - tw * 0.5, S + 8, tw, 22)
		_gbar(pacenote, r, Color(0.03, 0.08, 0.17, 0.8), Color(0.03, 0.08, 0.17, 0.8))
		_text(pacenote, Vector2(r.position.x, r.position.y + 16), sector.to_upper(), 13, TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, tw)

func _draw_lights() -> void:
	if not race or race.s.qualifying or (race.phase != "countdown" and race.race_time >= 1.2):
		return
	var lit := clampi(int(floorf(race.clock)), 0, 5) if race.phase == "countdown" else 0
	var w := 5.0 * 40.0 + 4.0 * 14.0 + 40.0
	var x0 := (lights.size.x - w) * 0.5
	_lights_style.draw(lights.get_canvas_item(), Rect2(x0, 0, w, 68))
	for k in 5:
		var c := Vector2(x0 + 40.0 + k * 54.0, 34.0)
		if k < lit:
			lights.draw_circle(c, 30.0, Color(1.0, 0.12, 0.12, 0.18))
			lights.draw_circle(c, 20.0, Color("#ff1a1a"))
			lights.draw_circle(c + Vector2(-5, -6), 8.0, Color(1.0, 0.6, 0.6, 0.55))
		else:
			lights.draw_circle(c, 20.0, Color("#2a0c0c"))

## Race control's flag for the player: a coloured board under the pace notes.
func _draw_flag() -> void:
	if not race or not race.rc or race.phase != "racing":
		return
	var f: Dictionary = race.rc.player_flag()
	if f.is_empty():
		return
	var W := flagbar.size.x
	var col: Color = f.color
	var title: String = f.title
	# the safety-car boards flash like the marshals' lights
	var flash := title.begins_with("SAFETY CAR") or title == "DOUBLE YELLOW"
	var a := 0.72 + 0.28 * absf(cos(_clock * PI * 1.5)) if flash else 1.0
	flagbar.draw_rect(Rect2(0, 0, W, 54), Color(0.01, 0.03, 0.08, 0.72))
	flagbar.draw_rect(Rect2(0, 0, 62, 54), Color(col, a))
	if title == "DOUBLE YELLOW":
		flagbar.draw_rect(Rect2(31, 0, 2, 54), Color(0, 0, 0, 0.5))
	flagbar.draw_rect(Rect2(62, 0, W - 62, 3), Color(col, a))
	_text(flagbar, Vector2(74, 25), title, 20, col.lightened(0.1) if col.get_luminance() > 0.3 else TEXT, true)
	_text(flagbar, Vector2(74, 44), f.sub, 12, TEXT)

func _update_banner() -> void:
	var p := race.player
	var tr := race.track
	var big := ""
	var small := ""
	var box := false
	if skip_note != "":
		big = "Simulating the rest of the race…"
		small = skip_note
	elif race.phase == "countdown":
		if race.s.qualifying:
			big = "QUALIFYING"
			small = "An out lap to warm the tyres, then %d timed lap%s — the fastest sets your grid slot" % [race.R - 1, "s" if race.R > 2 else ""]
		elif race.clock < 1.0:
			big = "Grid P%d" % p.grid
			small = "Hold the throttle for a good launch — wait for lights out"
	elif race.race_time < 1.5:
		big = "GO!"
	elif race.s.qualifying and p.finished:
		big = "QUALIFYING COMPLETE"
	elif race.s.qualifying and p.lap == 0 and race.race_time < 5.0:
		big = "OUT LAP"
		small = "Warm the tyres — the timed laps start at the line"
	elif race.s.qualifying and p.lap >= 1 and race.race_time - p.lap_start < 3.0 and not p.dnf:
		big = "TIMED LAP %d / %d" % [mini(p.lap, race.R - 1), race.R - 1]
		small = "Last lap %s" % Race.fmt_time(p.last_lap) if p.lap > 1 else "Push!"
	elif p.dnf and p.wrecked:
		big = "CRASHED OUT"
		small = "Enter — skip to results"
	elif p.dnf:
		big = "RETIRED"
		small = "Enter — skip to results"
	elif p.finished:
		big = "FINISHED P%d" % p.pos
		small = "Enter — skip to results"
	elif p.mode == "pit" and p.pit and p.pit.phase == "service":
		big = "PIT STOP %.1f s" % p.pit.left
	elif p.out_of_fuel:
		big = "OUT OF FUEL"
	elif p.pit_request:
		big = "BOX  BOX"
		box = true
	elif p.control == "free" and absf(p.speed) > 4.0 and cos(p.heading - tr.heading(p.s)) < -0.3:
		big = "WRONG WAY"
	elif p.autopilot:
		small = "CO-DRIVER · TIME ×%d ( , . )" % warp if warp > 1 else "AUTOPILOT (O)"
	if race.s.qualifying and p.lap >= 1 and p.invalid_lap and small == "" and not p.finished:
		small = "LAP INVALID — you left the track"
	banner.text = big
	banner_small.text = small
	banner.add_theme_color_override("font_color", YELLOW if box else TEXT)
	# BOX BOX blinks
	banner.visible = not box or fmod(_clock, 0.8) < 0.4

func _update_event_sounds() -> void:
	for e in race.events:
		if e.id <= _event_seen:
			continue
		_event_seen = e.id
		if not audio:
			continue
		if e.kind == "box":
			audio.beep(880.0, 2)
		elif e.kind == "good":
			audio.beep(660.0, 1)
		elif e.kind == "rc":
			audio.beep(990.0, 1)
	# a new flag from race control: three quick beeps
	var f: String = race.rc.flag if race.rc else "green"
	if f != _last_flag:
		if audio and _last_flag != "":
			audio.beep(990.0, 3)
		_last_flag = f

# ---------------- event feed ----------------
func _draw_feed() -> void:
	if not race:
		return
	var now := race.clock
	var first := race.events.size()
	var shown := 0
	while first > 0 and shown < 6 and now - race.events[first - 1].t < 10.0:
		first -= 1
		shown += 1
	var y := 0.0
	for i in range(first, race.events.size()):
		var e: Dictionary = race.events[i]
		var fade := minf(1.0, (10.0 - (now - e.t)) / 2.0)
		var h := _font.get_multiline_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, FEED_W - 23.0, 13).y + 10.0
		_gbar(feed, Rect2(0, y, FEED_W, h), Color(BAR_LO, BAR_LO.a * fade), Color(BAR_HI, BAR_HI.a * fade))
		feed.draw_rect(Rect2(FEED_W - 5, y, 5, h), Color(FEED_BORDER.get(e.kind, Color("#666666")), fade))
		feed.draw_multiline_string(_bold, Vector2(10, y + 18), e.text, HORIZONTAL_ALIGNMENT_RIGHT, FEED_W - 23.0, 13, -1, Color(INK, fade))
		y += h + 4.0

func _service() -> Variant:
	var p := race.player
	if p.service:
		return p.service
	if p.mode == "race" and not p.finished and not p.dnf:
		return race.default_service(p)
	return null

func _pitwall_height() -> float:
	return 10.0 + 22.0 + 40.0 + 34.0 + (26.0 if _damage_row() else 0.0) + 26.0 + 22.0 + (44.0 if _service() else 0.0) + 8.0

## The car's damage and the stewards' time penalties get a row on the pit wall once there are any.
func _damage_row() -> bool:
	var p := race.player
	return race.rc != null and (p.damage > 0.01 or p.penalty > 0.0)

func _draw_pitwall() -> void:
	if not race:
		return
	var p := race.player
	var w := race.weather
	var ci := pitwall.get_canvas_item()
	var W := PITWALL_W
	_panel_style.draw(ci, Rect2(0, 0, W, pitwall.size.y))
	var x := 12.0
	var y := 10.0
	# title and box-request badge
	_text(pitwall, Vector2(x, y + 12), "PIT WALL", 11, MUTED, true)
	var req := "BOX REQUESTED" if p.pit_request else "P = REQUEST BOX"
	var rw := _text_w(req, 10, true) + 16.0
	var pulse := 0.55 + 0.45 * absf(cos(_clock * PI)) if p.pit_request else 1.0
	pitwall.draw_rect(Rect2(W - 12 - rw, y, rw, 17), Color(YELLOW, pulse) if p.pit_request else Color(BAR_HI, 0.25))
	_text(pitwall, Vector2(W - 12 - rw, y + 12.5), req, 10, INK if p.pit_request else TEXT, true, HORIZONTAL_ALIGNMENT_CENTER, rw)
	y += 22.0
	# tyres
	var t: Dictionary = p.tyre
	var per_lap: float = race.track.L * race.tyres.wear_per_metre(t.c, w.wet, race.s.wear_mult)
	var tyre_laps: float = t.wear / per_lap if per_lap > 0.0 else 0.0
	_badge(pitwall, Vector2(x + 13, y + 16), t.c, true)
	var tx := x + 34.0
	var name_part: String = "%s · " % race.tyres.compounds[t.c].display_name
	_text(pitwall, Vector2(tx, y + 13), name_part, 13, TEXT)
	_text(pitwall, Vector2(tx + _text_w(name_part, 13), y + 13), "%d%%" % roundi(t.wear * 100.0), 13, TEXT, true)
	_text(pitwall, Vector2(tx, y + 13), "%s · ≈%.1f laps" % ["cold" if t.temp < 0.75 else "warm", tyre_laps], 11, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT, W - 12 - tx)
	var wear_col := RED if t.wear < 0.25 else (YELLOW if t.wear < 0.5 else GOOD)
	_meter(pitwall, Rect2(tx, y + 22, W - 12 - tx, 7), t.wear, wear_col)
	y += 40.0
	# fuel
	var fpl := race.fpl
	_text(pitwall, Vector2(x, y + 13), "FUEL", 11, MUTED, true)
	_text(pitwall, Vector2(x + 40, y + 13), "%.1f L" % p.fuel, 13, TEXT, true)
	_text(pitwall, Vector2(x + 40, y + 13), "≈ %.1f laps · %.2f L/lap" % [p.fuel / fpl if fpl > 0.0 else 0.0, fpl], 11, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT, W - 12 - (x + 40))
	_meter(pitwall, Rect2(x + 40, y + 21, W - 64, 7), p.fuel / race.spec.tank, BLUE)
	y += 34.0
	# damage and penalties
	if _damage_row():
		var pen := "PENALTY +%d s" % roundi(p.penalty) if p.penalty > 0.0 else ""
		if p.damage > 0.01:
			var dcol := RED if p.damage >= RaceControl.REPAIR_AT else (YELLOW if p.damage > 0.12 else TEXT)
			_text(pitwall, Vector2(x, y + 13), "DMG", 11, MUTED, true)
			_text(pitwall, Vector2(x + 40, y + 13), "%d%%" % roundi(p.damage * 100.0), 13, dcol, true)
			var fix := "repairs ≈%.0f s" % race.rc.repair_time(p)
			_text(pitwall, Vector2(x + 40, y + 13), fix + ("  ·  " + pen if pen != "" else ""), 11, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT, W - 12 - (x + 40))
			_meter(pitwall, Rect2(x + 40, y + 19, W - 64, 5), p.damage, dcol)
		else:
			_text(pitwall, Vector2(x, y + 13), pen, 12, YELLOW, true)
		y += 26.0
	# the plan: done stints fade, the current one is outlined
	var from := maxi(0, p.stint_idx - 2)
	var cx := x
	if from > 0:
		_text(pitwall, Vector2(cx, y + 15), "+%d" % from, 11, Color(MUTED, 0.6))
		cx += 22.0
	for k in range(from, mini(p.plan.size(), from + 8)):
		var st: Dictionary = p.plan[k]
		var chip_w := 26.0 + _text_w(str(st.laps), 12, true)
		if cx + chip_w > W - 12:
			break
		var done := k < p.stint_idx
		var chip := Rect2(cx, y + 2, chip_w, 19)
		pitwall.draw_rect(chip, Color(CHIP_BG, 0.45 if done else 1.0))
		if k == p.stint_idx:
			pitwall.draw_rect(chip, YELLOW, false, 1.0)
		_badge(pitwall, Vector2(cx + 10, y + 11.5), st.c)
		_text(pitwall, Vector2(cx + 21, y + 16), str(st.laps), 12, Color(TEXT, 0.45 if done else 1.0), true)
		cx += chip_w + 4.0
	y += 26.0
	# status line
	var status := ""
	var status_col := TEXT
	var next_stop := race.player_next_stop_lap()
	if p.mode == "pit" and p.pit:
		if p.pit.phase == "in":
			status = "Pit lane — limiter 60 km/h"
		elif p.pit.phase == "red":
			status = "Red flag — queue at the pit exit"
			status_col = RED
		elif p.pit.phase == "service":
			status = "Crew working… %.1f / %.1f s" % [p.pit.total - p.pit.left, p.pit.total]
		else:
			status = "Released — pit exit ahead"
	elif p.pit_request:
		status = "Box this lap — follow the pit entry"
		status_col = YELLOW
	elif next_stop > 0:
		if next_stop == p.lap + 1:
			status = "Plan: box this lap (P to confirm)"
			status_col = YELLOW
		else:
			status = "Plan: box after lap %d" % next_stop
	else:
		status = "No more stops planned"
	_text(pitwall, Vector2(x, y + 13), status, 12, status_col)
	y += 22.0
	# the service the crew will do at the next stop
	var sv = _service()
	if sv:
		pitwall.draw_line(Vector2(x, y), Vector2(W - 12, y), Color(CmrStyle.VIOLET, 0.3), 1.0)
		var sx := x
		var head := "Next stop:" if next_stop > 0 or p.pit_request or p.mode == "pit" else "If you box:"
		_text(pitwall, Vector2(sx, y + 17), head, 12, MUTED)
		sx += _text_w(head + " ", 12)
		var tyre_txt := "keep tyres"
		if sv.c:
			_badge(pitwall, Vector2(sx + 8, y + 13), sv.c)
			sx += 20.0
			tyre_txt = race.tyres.compounds[sv.c].display_name
		var rest := tyre_txt
		if race.rules.refuel:
			rest += " · +%.1f L" % sv.litres
		rest += " · ≈%.1f s" % sv.time
		_text(pitwall, Vector2(sx, y + 17), rest, 12, TEXT, true)
		var keys := "[ ] tyre" + (" · − = fuel" if race.rules.refuel else "") + " · R ask strategist"
		_text(pitwall, Vector2(x, y + 35), keys, 10, MUTED)

# ---------------- dash ----------------
# ---------------- dash (bottom right) ----------------
## CMR 2.0 rev counter: slanted segments rising along a curve (cyan, amber near the top, red at the
## limiter), rpm figures underneath, the gear as one big digit and the speed beside it.
const DASH_SEGMENTS := 26

## What the dash shows: [size, segments lit, gear, km/h]. It is only redrawn when this changes.
func _dash_state() -> Array:
	if not race:
		return []
	var p := race.player
	var kmh := roundi(absf(p.speed) * 3.6)
	var gear := str(p.gear + 1)
	if p.rev or p.speed < -0.3:
		gear = "R"
	elif kmh < 1 and p.control == "free" and p.throttle < 0.05:
		gear = "N"
	var frac := clampf(p.rpm / race.spec.limiter, 0.0, 1.0)
	# segment i is lit while (i + 0.78) / n <= frac + 0.03
	var lit := clampi(floori((frac + 0.03) * DASH_SEGMENTS - 0.78) + 1, 0, DASH_SEGMENTS)
	return [dash.size, lit, gear, kmh]

## The rev band's segments (four points each, then their outlines as thin quads), for dash.size.
func _build_dash(W: float, H: float) -> void:
	_dash_size = Vector2(W, H)
	var n := DASH_SEGMENTS
	var arc_w := W - 96.0
	var bottom := H - 26.0
	_dash_points = PackedVector2Array()
	_dash_colors = PackedColorArray()
	_dash_indices = PackedInt32Array()
	var outline := Color(0.08, 0.03, 0.12, 0.5)
	var corners: Array[PackedVector2Array] = []
	for i in n:
		var t0 := float(i) / n
		var t1 := (i + 0.78) / n
		# the band's lower edge curves up toward the redline and the band thickens as it goes, like CMR's
		var p0 := Vector2(arc_w * t0, bottom - 96.0 * pow(t0, 2.6))
		var p1 := Vector2(arc_w * t1, bottom - 96.0 * pow(t1, 2.6))
		var d := (p1 - p0).normalized()
		var up := Vector2(d.y, -d.x)
		var poly := PackedVector2Array([p0, p1, p1 + up * (10.0 + 22.0 * t1), p0 + up * (10.0 + 22.0 * t0)])
		corners.append(poly)
		var k := _dash_points.size()
		_dash_points.append_array(poly)
		for j in 4:
			_dash_colors.append(Color.WHITE)
		_dash_indices.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))
	# the outlines after all the fills, so a lit segment never covers its neighbour's edge
	for poly in corners:
		for j in 4:
			var a := poly[j]
			var b := poly[(j + 1) % 4]
			var off := (b - a).normalized().orthogonal() * 0.5
			var k := _dash_points.size()
			_dash_points.append_array(PackedVector2Array([a + off, b + off, b - off, a - off]))
			for m in 4:
				_dash_colors.append(outline)
			_dash_indices.append_array(PackedInt32Array([k, k + 1, k + 2, k, k + 2, k + 3]))

func _draw_dash() -> void:
	if not race:
		return
	var W := dash.size.x
	var H := dash.size.y
	var state := _dash_state()
	var lit: int = state[1]
	if _dash_size != dash.size:
		_build_dash(W, H)
	var n := DASH_SEGMENTS
	for i in n:
		var t0 := float(i) / n
		var col := Color(1, 1, 1, 0.16)
		if i < lit:
			col = RED if t0 >= 0.9 else (YELLOW if t0 >= 0.78 else BLUE)
		for j in 4:
			_dash_colors[i * 4 + j] = col
	RenderingServer.canvas_item_add_triangle_array(dash.get_canvas_item(), _dash_indices, _dash_points, _dash_colors)
	var limiter: float = race.spec.limiter
	var arc_w := W - 96.0
	var thousands := int(limiter / 1000.0)
	for k in range(1, thousands + 1):
		var x := arc_w * (k * 1000.0 / limiter)
		_q(Vector2(x - 10, H - 6), str(k), 13, TEXT, _bold, HORIZONTAL_ALIGNMENT_CENTER, 20, true)
	_q(Vector2(W - 92, H - 58), state[2], 92, TEXT, _bold, HORIZONTAL_ALIGNMENT_CENTER, 92, true)
	_q(Vector2(W - 92, H - 6), "KMH %d" % state[3], 16, TEXT, _bold, HORIZONTAL_ALIGNMENT_CENTER, 92, true)
	_q_flush(dash)

func _build_map() -> void:
	var tr := race.track
	_map_track = tr
	_map_size = minimap.size
	var b := tr.bounds
	var pad := 12.0
	_map_scale = minf((_map_size.x - 2.0 * pad) / (b[2] - b[0]), (_map_size.y - 2.0 * pad) / (b[3] - b[1]))
	_map_origin = Vector2((_map_size.x - (b[2] - b[0]) * _map_scale) * 0.5 - b[0] * _map_scale,
		(_map_size.y - (b[3] - b[1]) * _map_scale) * 0.5 - b[1] * _map_scale)
	_map_points = PackedVector2Array()
	var stride := maxi(1, tr.n / 320)
	for i in range(0, tr.n, stride):
		_map_points.append(Vector2(tr.X[i], tr.Y[i]) * _map_scale + _map_origin)
	_map_points.append(_map_points[0])
	var p0 := tr.pos(0.0, 0.0)
	var n0 := tr.pos(0.0, tr.half * 3.0)
	var a := Vector2(p0[0], p0[1])
	var n := Vector2(n0[0], n0[1])
	_map_start = PackedVector2Array([(2.0 * a - n) * _map_scale + _map_origin, n * _map_scale + _map_origin])

## What minimap_base shows: the circuit, the map's size and the flags along it.
func _minimap_key() -> String:
	if not race:
		return ""
	var key := "%d:%s" % [race.track.get_instance_id(), minimap.size]
	var rc := race.rc
	if rc:
		key += ":%s:%d" % [rc.flag, hash(rc.yellow)]
	return key

## The map's backdrop, the circuit and its flagged sectors; the cars go on minimap over it.
func _draw_minimap_base() -> void:
	if not race:
		return
	_map_key = _minimap_key()
	var rect := Rect2(Vector2.ZERO, minimap_base.size)
	minimap_base.draw_rect(rect, Color(0.03, 0.08, 0.17, 0.55))
	minimap_base.draw_rect(Rect2(0, 0, rect.size.x, 2), Color(CmrStyle.VIOLET, 0.7))
	if _map_track != race.track or _map_size != minimap.size:
		_build_map()
	_tri_strip(_map_points, 7.0, Color(0.01, 0.05, 0.12, 0.8), true)
	_tri_strip(_map_points, 3.2, Color("#e8f2ff"), true)
	_tri_strip(_map_start, 3.0, RED)
	if race.rc:
		_draw_map_flags(race.rc)
	_tri_flush(minimap_base)

func _draw_minimap() -> void:
	if not race:
		return
	if _map_track != race.track or _map_size != minimap.size:
		_build_map()
	var rc := race.rc
	var p := race.player
	# all the dots, then all their rims: two batched draws instead of two per car
	var dots: Array = [] ## [centre, colour]
	for car in race.cars:
		if car.stranded and not car.recovered:
			var wp := Vector2(car.x, car.y) * _map_scale + _map_origin
			minimap.draw_line(wp - Vector2(3.5, 3.5), wp + Vector2(3.5, 3.5), RED, 2.0, true)
			minimap.draw_line(wp + Vector2(-3.5, 3.5), wp + Vector2(3.5, -3.5), RED, 2.0, true)
		if car.dnf or car == p:
			continue
		dots.append([Vector2(car.x, car.y) * _map_scale + _map_origin, car.color])
	for d in dots:
		_round(minimap, d[0], 3.2, d[1])
	for d in dots:
		_round(minimap, d[0], 3.7, Color(0, 0, 0, 0.7), 2.7 / 3.7)
	if not p.dnf:
		var pp := Vector2(p.x, p.y) * _map_scale + _map_origin
		_round(minimap, pp, 5.5, YELLOW)
		_round(minimap, pp, 6.5, Color.BLACK, 4.5 / 6.5)
	if rc and rc.sc_state in ["out", "in"]:
		var sp := Vector2(rc.sc.x, rc.sc.y) * _map_scale + _map_origin
		var on := fmod(_clock, 0.5) < 0.25
		minimap.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color("#ffd21a") if on else Color.WHITE)
		minimap.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color.BLACK, false, 1.5)

## Yellow marshal sectors along the minimap line (the whole lap turns red under a red flag).
func _draw_map_flags(rc: RaceControl) -> void:
	var tr := race.track
	var step := maxf(15.0, tr.L / 320.0)
	for k in rc.n_sec:
		var lvl := 3 if rc.flag == "red" else rc.yellow[k]
		if lvl == 0:
			continue
		var col := RED if lvl == 3 else (Color("#ffd21a") if lvl == 2 else Color("#ffe98a"))
		var pts := PackedVector2Array()
		var s := k * rc.sec_len
		while s <= (k + 1) * rc.sec_len + 0.1:
			var q := tr.pos(s, 0.0)
			pts.append(Vector2(q[0], q[1]) * _map_scale + _map_origin)
			s += step
		if pts.size() >= 2:
			_tri_strip(pts, 4.0 if lvl == 2 else 3.2, col)

func _draw_tags() -> void:
	if not race or not is_instance_valid(world) or not world.camera:
		return
	var cam: Camera3D = world.camera
	var focus := race.player
	var shown := [] ## [distance to camera, car, screen point]
	for car in race.cars:
		if car == focus or car.dnf:
			continue
		var dx := car.x - focus.x
		var dy := car.y - focus.y
		if dx * dx + dy * dy > 90.0 * 90.0:
			continue
		var visual = world.visuals.get(car.id)
		if not visual or not visual.visible:
			continue
		var wp: Vector3 = visual.position + Vector3.UP * 2.1
		if cam.is_position_behind(wp):
			continue
		# the camera renders at window pixels; the HUD lives on the scaled design canvas
		var sp := cam.unproject_position(wp) * (size / Vector2(cam.get_viewport().size))
		shown.append([cam.global_position.distance_squared_to(wp), car, sp])
	# nearest first, so they keep their spot; a farther tag that would overlap one already placed moves up
	shown.sort_custom(func(a, b): return a[0] < b[0])
	var placed: Array[Rect2] = []
	for entry in shown:
		var car = entry[1]
		var sp: Vector2 = entry[2]
		var mark := ""
		if car.brain:
			mark = " »" if car.brain.mind == "attack" else (" «" if car.brain.mind == "defend" else "")
		var label := "P%d %s%s" % [car.pos, Brain.short(car), mark]
		var tw := _text_w(label, 11, true) + 14.0
		var r := Rect2(sp.x - tw * 0.5, sp.y - 14.0, tw, 16.0)
		var moved := true
		while moved:
			moved = false
			for other in placed:
				if r.intersects(other):
					r.position.y = other.position.y - 18.0
					moved = true
		placed.append(r)
		entry.append(label)
		entry.append(r)
	# draw far to near so the nearer cars' tags end up on top
	for i in range(shown.size() - 1, -1, -1):
		var car = shown[i][1]
		var label: String = shown[i][3]
		var r: Rect2 = shown[i][4]
		_gbar(tags, r, BAR_HI, Color(BAR_HI, 0.6))
		tags.draw_rect(Rect2(r.position, Vector2(4, 16)), car.color)
		_text(tags, Vector2(r.position.x + 8.0, r.position.y + 12.0), label, 11, INK, true)
