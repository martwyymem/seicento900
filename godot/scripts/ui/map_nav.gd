class_name MapNav
extends RefCounted
## The big map's view: zoom (towards a point), pan, the marker filters, the item list and what keys, the mouse
## and a pad do to them. The maths are static so the tests can run them without a screen; the HUD (OpenWorldHud)
## owns one instance, feeds it the markers and the car, and draws what it says (BigMapDraw). North is always up.
## Projection is MapMarker.big_xy / big_world with this view's `centre`, `radius` (metres from the middle to the
## top edge) and `aspect`.

signal filters_changed(hidden: Array) ## the categories switched off, to be remembered in the save
signal selected(marker: int) ## the hop / list / a click picked this marker (an index into `markers`)
signal clicked(world: Vector2, marker: int) ## a click without a drag: a marker within reach (or -1) and the point

const MIN_RADIUS := 70.0 ## street level: 140 m top to bottom
const DEFAULT_RADIUS := 900.0 ## the opening view: a couple of kilometres across
const WHEEL_STEP := 1.2
const KEY_STEP := 1.35
const PAN_SPEED := 0.8 ## screen heights per second at full deflection
const CLICK_SLOP := 6.0 ## px a press may move and still be a click
const PICK_PX := 16.0
const STREET_RADIUS := 450.0 ## street names are drawn at or under this radius
const DISTRICT_RADIUS := 2800.0 ## the small districts (hamlets, neighbourhoods) at or under this one
const POI_LABEL_RADIUS := 1500.0
const CHIP := Vector2(236, 28)
const ROW_H := 25.0
const LIST_ROWS := 9

## The marker categories: the filter row's entries, in key order (1..5).
const CATS := [
	{"id": "stage", "name": "Stages", "key": KEY_1, "color": Color("#ff8a2a")},
	{"id": "mission", "name": "Missions", "key": KEY_2, "color": Color("#f2c94c")},
	{"id": "live", "name": "Live events", "key": KEY_3, "color": Color("#e0629a")},
	{"id": "trap", "name": "Speed traps", "key": KEY_4, "color": Color("#4aa3ff")},
	{"id": "landmark", "name": "Landmarks", "key": KEY_5, "color": Color("#52d6b2")},
]

var size := Vector2(1600, 900)
var aspect := 16.0 / 9.0
var bounds := Rect2(-1000, -1000, 2000, 2000)
var centre := Vector2.ZERO
var radius := DEFAULT_RADIUS
var goal_radius := DEFAULT_RADIUS
var anchor_px := Vector2(800, 450) ## the pixel a zoom in progress holds still
var goal_centre := Vector2.ZERO
var gliding := false
var hidden := {} ## category id -> true while switched off
var panel_open := false ## the side panel: filters on top, the list of what is shown under them
var focus := 0 ## panel row with the pad / keys: 0..CATS.size()-1 the filters, then the items
var pad := false ## the last input came from a pad (picks the hint)
var markers: Array = [] ## the HUD's marker dictionaries (read defensively: any key may be missing)
var sel := 0
var car_pos := Vector2.ZERO
var route := PackedVector2Array()
var cursor_on := false
var cursor := Vector2.ZERO
var _press := Vector2.ZERO
var _pressed := false
var _drag_moved := 0.0
var _list_cache: Array = []

# ================================================================================================ the maths

static func fit_radius(b: Rect2, asp: float) -> float:
	return maxf(b.size.y * 0.5, b.size.x * 0.5 / maxf(asp, 0.01)) * 1.05

## Zooms about the pixel `px`: the map point under it stays under it. factor > 1 zooms in. Returns {centre, radius}.
static func zoom_about(c: Vector2, r: float, asp: float, sz: Vector2, px: Vector2, factor: float, rmin: float, rmax: float) -> Dictionary:
	var world := MapMarker.big_world(px, c, r, asp, sz)
	var nr := clampf(r / maxf(factor, 0.001), rmin, maxf(rmin, rmax))
	var o := (px - sz * 0.5) / (sz * 0.5)
	o.x *= asp
	return {"centre": world - o * nr, "radius": nr}

## The view centre held so the view never shows more than `b` on an axis it is smaller than, and is centred on
## an axis it is larger than.
static func clamp_centre(c: Vector2, r: float, asp: float, b: Rect2) -> Vector2:
	var half := Vector2(r * asp, r)
	var out := c
	for ax in 2:
		if half[ax] * 2.0 >= b.size[ax]:
			out[ax] = b.position[ax] + b.size[ax] * 0.5
		else:
			out[ax] = clampf(c[ax], b.position[ax] + half[ax], b.end[ax] - half[ax])
	return out

## A cursor pushing the view: the centre moved just far enough that `cur` sits inside the middle (1 - 2 * margin)
## of the view.
static func push_view(c: Vector2, cur: Vector2, r: float, asp: float, margin := 0.12) -> Vector2:
	var half := Vector2(r * asp, r) * (1.0 - margin * 2.0)
	var out := c
	for ax in 2:
		out[ax] = clampf(c[ax], cur[ax] - half[ax], cur[ax] + half[ax])
	return out

## The scale bar: the longest of 1, 2, 5 x 10^n metres that fits in `max_px`, its pixel length and its text.
static func scale_bar(r: float, h_px: float, max_px := 180.0) -> Dictionary:
	var m_per_px := r / maxf(h_px * 0.5, 1.0)
	var target := max_px * m_per_px
	var e := pow(10.0, floor(log(maxf(target, 0.001)) / log(10.0)))
	var best := e
	for k in [1.0, 2.0, 5.0]:
		if e * k <= target:
			best = e * k
	return {"m": best, "px": best / m_per_px, "text": ("%d m" % int(best)) if best < 1000.0 else ("%s km" % String.num(best / 1000.0, 1).trim_suffix(".0"))}

static func fmt_dist(m: float) -> String:
	if m < 100.0:
		return "%d m" % int(round(m))
	if m < 1000.0:
		return "%d m" % (int(round(m / 10.0)) * 10)
	return "%.1f km" % (m / 1000.0)

## What is left of the route from the point on it nearest `from`, in metres.
static func route_left(pts: PackedVector2Array, from: Vector2) -> float:
	if pts.size() < 2:
		return 0.0
	var best := INF
	var bi := 0
	var bp := pts[0]
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(from, pts[i], pts[i + 1])
		var d := from.distance_squared_to(q)
		if d < best:
			best = d
			bi = i
			bp = q
	var left := bp.distance_to(pts[bi + 1])
	for i in range(bi + 1, pts.size() - 1):
		left += pts[i].distance_to(pts[i + 1])
	return left

## Which filter a marker belongs to: "stage" (no kind), "mission", "live", "trap", "landmark", "waypoint", or "other".
static func category(m: Dictionary) -> String:
	var k := String(m.get("kind", ""))
	match k:
		"":
			return "stage"
		"poi":
			return String(m.get("poi", "landmark"))
		"mission", "live", "waypoint":
			return k
	return "other"

## Whether a marker is shown with the categories in `hid` switched off. The waypoint and kinds with no filter always are.
static func shown(m: Dictionary, hid: Dictionary) -> bool:
	return not hid.has(category(m))

static func name_of(m: Dictionary) -> String:
	var n := String(m.get("label", ""))
	if n != "":
		return n
	match String(m.get("poi", "")):
		"trap":
			return "Speed trap"
		"landmark":
			return "Undiscovered landmark"
	return String(m.get("info", "")).get_slice(" · ", 0)

## The state word beside an item: discovered / undiscovered / not driven for points of interest, and the last word of
## the info line (Done, Open, Locked) for stages and events.
static func state_of(m: Dictionary) -> String:
	if String(m.get("kind", "")) == "poi":
		match int(m.get("state", 0)):
			0: return "undiscovered"
			1: return "not driven"
		return "driven" if String(m.get("poi", "")) == "trap" else "discovered"
	var tail := String(m.get("info", "")).get_slice(" · ", String(m.get("info", "")).count(" · ")).strip_edges()
	return tail.to_lower() if tail in ["Done", "Open", "Locked"] else ""

## How many markers each category holds: {id: n}, whatever is switched off.
static func counts(list: Array) -> Dictionary:
	var c := {}
	for cat in CATS:
		c[cat.id] = 0
	for m: Dictionary in list:
		var id := category(m)
		if c.has(id):
			c[id] += 1
	return c

## The markers shown, nearest `from` first: [{i, pos, name, cat, dist, state}].
static func items(list: Array, hid: Dictionary, from: Vector2) -> Array:
	var out := []
	for i in list.size():
		var m: Dictionary = list[i]
		if not shown(m, hid) or not m.get("pos") is Vector2:
			continue
		var p: Vector2 = m.pos
		out.append({"i": i, "pos": p, "name": name_of(m), "cat": category(m), "dist": p.distance_to(from), "state": state_of(m)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist if a.dist != b.dist else a.i < b.i)
	return out

## The marker `dir` (+1 / -1) steps after marker `cur` in a list of items(): the marker index, or -1 when it is empty.
## From a marker that is not in the list it starts at the nearest (+1) or the farthest (-1).
static func hop(list: Array, cur: int, dir: int) -> int:
	if list.is_empty():
		return -1
	var at := -1
	for k in list.size():
		if int(list[k].i) == cur:
			at = k
	if at < 0:
		return int(list[0].i) if dir > 0 else int(list[list.size() - 1].i)
	return int(list[posmod(at + dir, list.size())].i)

## How a label reads at this zoom: 0 none, 1 big (a town or village), 2 small (hamlet, neighbourhood).
static func district_tier(kind: String, r: float) -> int:
	if r < 350.0:
		return 0
	match kind:
		"place_town", "place_village":
			return 1
		"place_locality", "place_neighbourhood", "place_hamlet":
			return 2 if r <= DISTRICT_RADIUS else 0
	return 0

## The side panel's geometry in a view of `sz`: {chips: [Rect2], rows: [Rect2], panel: Rect2}.
static func layout(sz: Vector2, n_items: int) -> Dictionary:
	var x := sz.x - CHIP.x - 30.0
	var chips := []
	var y := 104.0
	for i in CATS.size():
		chips.append(Rect2(x, y + i * (CHIP.y + 4.0), CHIP.x, CHIP.y))
	var rows := []
	var ry := y + CATS.size() * (CHIP.y + 4.0) + 30.0
	for k in mini(n_items, LIST_ROWS):
		rows.append(Rect2(x, ry + k * ROW_H, CHIP.x, ROW_H))
	var top := y - 8.0
	var last: Rect2 = rows[rows.size() - 1] if not rows.is_empty() else chips[chips.size() - 1]
	var bottom := last.end.y + 8.0
	return {"chips": chips, "rows": rows, "panel": Rect2(x - 8.0, top, CHIP.x + 16.0, bottom - top)}

## The first item shown in the list window when row `foc` has the focus.
static func list_first(foc: int, n: int) -> int:
	return clampi(foc - CATS.size() - LIST_ROWS / 2, 0, maxi(n - LIST_ROWS, 0))

## The one-line help, for the device last used.
static func hint(on_pad: bool, cursor_mode: bool, panel: bool) -> String:
	if cursor_mode:
		return ("L-stick move the cursor · A set waypoint here · X back · LT / RT zoom · B close" if on_pad
			else "arrows move the cursor · wheel zoom · Enter set waypoint here · F back · Esc close")
	if panel:
		return ("D-pad pick · A toggle / go to · Y close · B close" if on_pad else "up / down pick · Enter toggle / go to · L close · Esc close")
	if on_pad:
		return "LT / RT zoom · L-stick pan · D-pad next place · Y filters + list · R3 car · L3 route · A set route · X waypoint · B close"
	return "wheel zoom · drag / WASD pan · Tab next place · 1-5 filters · L list · Home car · G route · Enter set route · F waypoint · Esc close"

# ================================================================================================ the view

## Opens on the car at the default zoom (or the whole area when that is smaller).
func open(b: Rect2, sz: Vector2, car: Vector2) -> void:
	bounds = b
	set_size(sz)
	goal_radius = minf(DEFAULT_RADIUS, max_radius())
	radius = goal_radius
	centre = clamp_centre(car, radius, aspect, bounds)
	gliding = false
	anchor_px = size * 0.5
	panel_open = false
	focus = 0

func set_size(sz: Vector2) -> void:
	size = sz
	aspect = sz.x / maxf(sz.y, 1.0)

func max_radius() -> float:
	return fit_radius(bounds, aspect)

func xy(p: Vector2) -> Vector2:
	return MapMarker.big_xy(p, centre, radius, aspect, size)

func world(q: Vector2) -> Vector2:
	return MapMarker.big_world(q, centre, radius, aspect, size)

## Zooms by `factor` (>1 in) about the pixel `at`, gliding there.
func zoom_by(factor: float, at := Vector2(-1, -1)) -> void:
	anchor_px = size * 0.5 if at.x < 0.0 else at
	goal_radius = clampf(goal_radius / factor, MIN_RADIUS, max_radius())
	gliding = false

func zoom_to(r: float) -> void:
	zoom_by(goal_radius / clampf(r, MIN_RADIUS, max_radius()), size * 0.5)

## Moves the view by `d` pixels of drag (the map follows the pointer).
func pan_px(d: Vector2) -> void:
	gliding = false
	centre = clamp_centre(centre - d * (radius / maxf(size.y * 0.5, 1.0)), radius, aspect, bounds)

## Moves the view `dir` (-1..1 per axis) screen-heights per second for `dt`.
func pan_dir(dir: Vector2, dt: float) -> void:
	gliding = false
	centre = clamp_centre(centre + dir * PAN_SPEED * 2.0 * radius * dt, radius, aspect, bounds)

## Glides the view to `p`, and to radius `r` when given.
func goto(p: Vector2, r := -1.0) -> void:
	goal_centre = p
	gliding = true
	anchor_px = size * 0.5
	if r > 0.0:
		goal_radius = clampf(r, MIN_RADIUS, max_radius())

func recentre() -> void:
	goto(car_pos)

func fit() -> void:
	goal_radius = max_radius()
	goto(bounds.get_center())

## The end of the route, or the car when none runs.
func destination() -> Vector2:
	return route[route.size() - 1] if route.size() >= 2 else car_pos

func to_destination() -> void:
	goto(destination())

## Eases the zoom and glide toward their goals; true while the view is still moving.
func step(dt: float) -> bool:
	var k := 1.0 - exp(-dt * 11.0)
	var moving := false
	if absf(log(goal_radius / radius)) > 0.002:
		var nr := exp(lerpf(log(radius), log(goal_radius), k))
		var z := zoom_about(centre, radius, aspect, size, anchor_px, radius / nr, MIN_RADIUS, max_radius())
		centre = z.centre
		radius = z.radius
		moving = true
	elif radius != goal_radius:
		radius = goal_radius
	if gliding:
		centre = centre.lerp(goal_centre, k)
		if centre.distance_to(goal_centre) < radius * 0.0015:
			centre = goal_centre
			gliding = false
		moving = true
	var c := clamp_centre(centre, radius, aspect, bounds)
	if c != centre:
		centre = c
		moving = true
	return moving

## Jumps straight to the goals (tests, and the first frame).
func snap() -> void:
	radius = goal_radius
	if gliding:
		centre = goal_centre
		gliding = false
	centre = clamp_centre(centre, radius, aspect, bounds)

# ================================================================================================ filters and list

func set_hidden(list: Array) -> void:
	hidden.clear()
	for id in list:
		hidden[str(id)] = true

func toggle_category(id: String) -> void:
	if hidden.has(id):
		hidden.erase(id)
	else:
		hidden[id] = true
	filters_changed.emit(hidden.keys())
	# a hidden marker can't stay the one selected
	if sel >= 0 and sel < markers.size() and not shown(markers[sel], hidden):
		var l := items(markers, hidden, car_pos)
		if not l.is_empty():
			select(int(l[0].i), false)

func current_items() -> Array:
	return items(markers, hidden, car_pos)

func select(i: int, go := true) -> void:
	sel = i
	if go and i >= 0 and i < markers.size() and markers[i].get("pos") is Vector2:
		goto(markers[i].pos)
	selected.emit(i)

func hop_by(dir: int) -> void:
	var i := hop(current_items(), sel, dir)
	if i >= 0:
		select(i)

func focus_rows() -> int:
	return CATS.size() + current_items().size()

func move_focus(d: int) -> void:
	focus = posmod(focus + d, maxi(focus_rows(), 1))

func panel_accept() -> void:
	if focus < CATS.size():
		toggle_category(String(CATS[focus].id))
		return
	var l := current_items()
	var k := focus - CATS.size()
	if k >= 0 and k < l.size():
		select(int(l[k].i))
		panel_open = false

# ================================================================================================ input

## Zoom and pan held down: the keys, the left stick and the triggers. {pan: Vector2 (-1..1), zoom: -1..1, in is +}.
func read_input() -> Dictionary:
	var pan_v := Vector2.ZERO
	if not panel_open:
		pan_v.x = (1.0 if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT) else 0.0) \
			- (1.0 if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT) else 0.0)
		pan_v.y = (1.0 if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) else 0.0) \
			- (1.0 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) else 0.0)
	var zoom_v := 0.0
	for dev in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if s.length() > 0.22:
			pan_v += s
			pad = true
		var t := Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
		if absf(t) > 0.1:
			zoom_v += t
			pad = true
	if pan_v.length() > 1.0:
		pan_v = pan_v.normalized()
	return {"pan": pan_v, "zoom": clampf(zoom_v, -1.0, 1.0)}

## Applies held input for `dt` seconds: moves the cursor (pushing the view at its edges) or the view, and zooms.
func apply_input(inp: Dictionary, dt: float) -> void:
	var pan_v: Vector2 = inp.pan
	var zoom_v: float = inp.zoom
	if zoom_v != 0.0:
		zoom_by(pow(2.2, zoom_v * dt), (xy(cursor) if cursor_on else size * 0.5))
		snap_zoom_rate()
	if pan_v != Vector2.ZERO:
		if cursor_on:
			cursor += pan_v * PAN_SPEED * 2.0 * radius * dt * 0.7
			cursor = Vector2(clampf(cursor.x, bounds.position.x, bounds.end.x), clampf(cursor.y, bounds.position.y, bounds.end.y))
			centre = clamp_centre(push_view(centre, cursor, radius, aspect), radius, aspect, bounds)
			gliding = false
		else:
			pan_dir(pan_v, dt)

## A held trigger moves the goal a little at a time: follow it at once rather than gliding behind the finger.
func snap_zoom_rate() -> void:
	var z := zoom_about(centre, radius, aspect, size, anchor_px, radius / goal_radius, MIN_RADIUS, max_radius())
	centre = z.centre
	radius = z.radius

## A key or pad press while the map is open; true when it was used (the open world then leaves it alone).
func handle_event(e: InputEvent) -> bool:
	if e is InputEventKey:
		if not e.pressed:
			return false
		pad = false
		return _key(e)
	if e is InputEventJoypadButton and e.pressed:
		pad = true
		return _pad(e)
	return false

func _key(e: InputEventKey) -> bool:
	var k: Key = e.physical_keycode
	var anchor := xy(cursor) if cursor_on else size * 0.5
	if e.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD] or k in [KEY_EQUAL, KEY_KP_ADD]:
		zoom_by(KEY_STEP, anchor)
		return true
	if e.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] or k in [KEY_MINUS, KEY_KP_SUBTRACT]:
		zoom_by(1.0 / KEY_STEP, anchor)
		return true
	if e.echo and k != KEY_TAB:
		return k in [KEY_UP, KEY_DOWN, KEY_W, KEY_A, KEY_S, KEY_D, KEY_LEFT, KEY_RIGHT]
	match k:
		KEY_0, KEY_KP_0:
			fit()
		KEY_HOME:
			recentre()
		KEY_END, KEY_G:
			to_destination()
		KEY_TAB:
			hop_by(-1 if e.shift_pressed else 1)
		KEY_L:
			panel_open = not panel_open
			focus = 0
		KEY_UP, KEY_W:
			if panel_open:
				move_focus(-1)
		KEY_DOWN, KEY_S:
			if panel_open:
				move_focus(1)
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			pass # held: read_input pans
		KEY_ESCAPE:
			if not panel_open:
				return false
			panel_open = false
		KEY_ENTER, KEY_KP_ENTER:
			if not panel_open:
				return false
			panel_accept()
		_:
			for i in CATS.size():
				if k == CATS[i].key:
					toggle_category(String(CATS[i].id))
					return true
			return false
	return true

func _pad(e: InputEventJoypadButton) -> bool:
	match e.button_index:
		JOY_BUTTON_Y:
			panel_open = not panel_open
			focus = 0
		JOY_BUTTON_B:
			if not panel_open:
				return false
			panel_open = false
		JOY_BUTTON_A:
			if not panel_open:
				return false
			panel_accept()
		JOY_BUTTON_RIGHT_STICK:
			recentre()
		JOY_BUTTON_LEFT_STICK:
			to_destination()
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER:
			hop_by(-1)
		JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER:
			hop_by(1)
		JOY_BUTTON_DPAD_UP:
			if panel_open:
				move_focus(-1)
			else:
				zoom_by(KEY_STEP, xy(cursor) if cursor_on else size * 0.5)
		JOY_BUTTON_DPAD_DOWN:
			if panel_open:
				move_focus(1)
			else:
				zoom_by(1.0 / KEY_STEP, xy(cursor) if cursor_on else size * 0.5)
		_:
			return false
	return true

## The marker nearest the pixel `q` within PICK_PX, or -1.
func pick(q: Vector2) -> int:
	var best := PICK_PX
	var bi := -1
	for i in markers.size():
		var m: Dictionary = markers[i]
		if not shown(m, hidden) or not m.get("pos") is Vector2:
			continue
		var d := xy(m.pos).distance_to(q)
		if d < best:
			best = d
			bi = i
	return bi

## Mouse input over the map (positions in the map's own pixels): the wheel and pinch zoom, a drag pans, a press that
## did not move is a click (clicked), and the panel's chips and rows take their own clicks. True when used.
func handle_mouse(e: InputEvent) -> bool:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_by(pow(WHEEL_STEP, mb.factor if mb.factor > 0.0 else 1.0), mb.position)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(1.0 / pow(WHEEL_STEP, mb.factor if mb.factor > 0.0 else 1.0), mb.position)
				return true
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					pad = false
					if mb.button_index == MOUSE_BUTTON_LEFT and _click_panel(mb.position):
						return true
					_pressed = true
					_press = mb.position
					_drag_moved = 0.0
					return true
				if _pressed:
					_pressed = false
					if _drag_moved < CLICK_SLOP and mb.button_index == MOUSE_BUTTON_LEFT:
						var i := pick(mb.position)
						clicked.emit(world(mb.position), i)
					return true
		return false
	if e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _pressed and mm.button_mask != 0:
			_drag_moved += mm.relative.length()
			if _drag_moved >= CLICK_SLOP:
				pan_px(mm.relative)
			return true
		_pressed = false
		if cursor_on:
			cursor = world(mm.position)
			return true
		return false
	if e is InputEventMagnifyGesture:
		zoom_by(maxf((e as InputEventMagnifyGesture).factor, 0.05), (e as InputEventMagnifyGesture).position)
		return true
	if e is InputEventPanGesture:
		pan_px(-(e as InputEventPanGesture).delta * 14.0)
		return true
	return false

func _click_panel(q: Vector2) -> bool:
	var l := current_items()
	var lay := layout(size, l.size() if panel_open else 0)
	for i in CATS.size():
		if (lay.chips[i] as Rect2).has_point(q):
			toggle_category(String(CATS[i].id))
			return true
	if panel_open:
		var first := list_first(focus, l.size())
		for k in lay.rows.size():
			if (lay.rows[k] as Rect2).has_point(q):
				select(int(l[first + k].i))
				return true
		return (lay.panel as Rect2).has_point(q)
	return false
