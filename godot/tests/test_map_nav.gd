## The big map's view controls (scripts/ui/map_nav.gd): zoom about a point, pan clamping, projection round trips at
## 4:3 / 16:9 / 21:9, the scale bar, filters hiding exactly their category, the item list's order, hopping, the route's
## remaining length, and keys, mouse and pad events driving a MapNav (and the HUD carrying it, drawing without errors).
extends RefCounted

var completed := false
const ASPECTS := [4.0 / 3.0, 16.0 / 9.0, 21.0 / 9.0]
const BOUNDS := Rect2(-4000, -3000, 8000, 6000)

func run() -> Array:
	var errors: Array[String] = []
	_zoom(errors)
	_round_trip(errors)
	_clamp(errors)
	_bar(errors)
	_filters(errors)
	_nav_events(errors)
	_mouse(errors)
	await _hud(errors, Engine.get_main_loop() as SceneTree)
	completed = true
	return errors

static func _near(a: Vector2, b: Vector2, e := 0.01) -> bool:
	return a.distance_to(b) <= e

static func _key(code: Key, shift := false, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	e.echo = echo
	return e

static func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	return e

static func _markers() -> Array:
	return [
		{"pos": Vector2(100, 0), "color": Color.ORANGE, "label": "1. Fiat", "info": "Fiat · near · Open"},
		{"pos": Vector2(900, 0), "color": Color.ORANGE, "label": "2. Golf", "info": "Golf · Done"},
		{"pos": Vector2(300, 0), "color": Color.GOLD, "label": "Sprint", "info": "Sprint · Open", "kind": "mission"},
		{"pos": Vector2(-500, 0), "color": Color.PINK, "label": "Drift", "info": "Drift", "kind": "live"},
		{"pos": Vector2(0, 200), "color": Color.BLUE, "label": "Speed trap", "info": "trap", "kind": "poi", "poi": "trap", "state": 1},
		{"pos": Vector2(0, -700), "color": Color.GREEN, "label": "", "info": "landmark", "kind": "poi", "poi": "landmark", "state": 0},
		{"pos": Vector2(0, -50), "color": Color.PURPLE, "label": "WAYPOINT", "info": "Your waypoint", "kind": "waypoint"}]

func _zoom(errors: Array[String]) -> void:
	for asp: float in ASPECTS:
		var sz := Vector2(900.0 * asp, 900.0)
		for r: float in [80.0, 900.0, 3000.0]:
			for px: Vector2 in [Vector2(10, 10), sz * 0.5, Vector2(sz.x - 5, sz.y * 0.8), Vector2(sz.x * 0.3, sz.y * 0.1)]:
				var c := Vector2(123, -456)
				var before := MapMarker.big_world(px, c, r, asp, sz)
				for f: float in [2.0, 0.5, 1.35, 7.0]:
					var z := MapNav.zoom_about(c, r, asp, sz, px, f, 1.0, 1e6)
					var after := MapMarker.big_world(px, z.centre, z.radius, asp, sz)
					if not _near(before, after, 0.01) or absf(float(z.radius) - r / f) > 0.001:
						errors.append("zoom x%.2f about %s at aspect %.2f moved the point under it: %s -> %s" % [f, px, asp, before, after])
	var z := MapNav.zoom_about(Vector2.ZERO, 100.0, 1.78, Vector2(1600, 900), Vector2(800, 450), 100.0, 70.0, 5000.0)
	if z.radius != 70.0:
		errors.append("zoom in stops at street level (%s)" % z.radius)
	z = MapNav.zoom_about(Vector2.ZERO, 100.0, 1.78, Vector2(1600, 900), Vector2(800, 450), 0.0001, 70.0, 5000.0)
	if z.radius != 5000.0:
		errors.append("zoom out stops at the whole area (%s)" % z.radius)

func _round_trip(errors: Array[String]) -> void:
	for asp: float in ASPECTS:
		var sz := Vector2(900.0 * asp, 900.0)
		for r: float in [MapNav.MIN_RADIUS, 250.0, 900.0, 4500.0]:
			var c := Vector2(-300, 1200)
			for p: Vector2 in [c, c + Vector2(30, -20), c + Vector2(-r * asp * 0.9, r * 0.9), Vector2(5000, -5000)]:
				var q := MapMarker.big_xy(p, c, r, asp, sz)
				if not _near(MapMarker.big_world(q, c, r, asp, sz), p, 0.05):
					errors.append("round trip failed at aspect %.2f radius %.0f for %s" % [asp, r, p])
		# metres per pixel is the same both ways: a circle stays a circle
		var a := MapMarker.big_xy(Vector2(100, 0), Vector2.ZERO, 500.0, asp, sz)
		var b := MapMarker.big_xy(Vector2(0, 100), Vector2.ZERO, 500.0, asp, sz)
		if absf((a - sz * 0.5).length() - (b - sz * 0.5).length()) > 0.01:
			errors.append("100 m east and 100 m south differ in pixels at aspect %.2f" % asp)

func _clamp(errors: Array[String]) -> void:
	for asp: float in ASPECTS:
		for r: float in [100.0, 900.0, 2500.0]:
			var half := Vector2(r * asp, r)
			for want: Vector2 in [Vector2(99999, 99999), Vector2(-99999, -99999), Vector2(0, 0), Vector2(3900, -2900)]:
				var c := MapNav.clamp_centre(want, r, asp, BOUNDS)
				for ax in 2:
					if half[ax] * 2.0 < BOUNDS.size[ax]:
						if c[ax] - half[ax] < BOUNDS.position[ax] - 0.001 or c[ax] + half[ax] > BOUNDS.end[ax] + 0.001:
							errors.append("the view left the area on axis %d (aspect %.2f, radius %.0f, wanted %s): %s" % [ax, asp, r, want, c])
					elif absf(c[ax] - BOUNDS.get_center()[ax]) > 0.001:
						errors.append("a view larger than the area is centred (axis %d, aspect %.2f, radius %.0f)" % [ax, asp, r])
	if MapNav.clamp_centre(Vector2(10, 20), 100.0, 1.0, BOUNDS) != Vector2(10, 20):
		errors.append("a centre well inside the area is left alone")
	# a cursor pushes the view only as far as it must
	var c := MapNav.push_view(Vector2.ZERO, Vector2(100, 0), 1000.0, 1.78)
	if c != Vector2.ZERO:
		errors.append("a cursor inside the middle of the view does not move it")
	c = MapNav.push_view(Vector2.ZERO, Vector2(5000, 0), 1000.0, 1.78)
	var half := Vector2(1000.0 * 1.78, 1000.0) * 0.76
	if absf(c.x - (5000.0 - half.x)) > 0.01 or c.y != 0.0:
		errors.append("a cursor beyond the edge drags the view just far enough: %s" % c)

func _bar(errors: Array[String]) -> void:
	var last := 0.0
	for r: float in [4500.0, 2000.0, 900.0, 450.0, 160.0, 70.0]:
		var b := MapNav.scale_bar(r, 900.0)
		if float(b.px) > 180.0 + 0.01 or float(b.px) < 60.0:
			errors.append("scale bar at radius %.0f is %.0f px" % [r, b.px])
		if absf(float(b.px) * (r / 450.0) - float(b.m)) > 0.01 * float(b.m):
			errors.append("scale bar at radius %.0f: %d m over %.1f px is not the map's scale" % [r, b.m, b.px])
		if float(b.m) > last and last > 0.0 and float(b.m) > 0.0:
			errors.append("zooming in lengthened the bar's metres (%d -> %d)" % [last, b.m])
		last = float(b.m)
	if MapNav.scale_bar(900.0, 900.0).text != "200 m" or MapNav.scale_bar(4500.0, 900.0).text != "1 km":
		errors.append("scale bar text: %s, %s" % [MapNav.scale_bar(900.0, 900.0).text, MapNav.scale_bar(4500.0, 900.0).text])
	if MapNav.fmt_dist(42.0) != "42 m" or MapNav.fmt_dist(1234.0) != "1.2 km" or MapNav.fmt_dist(340.0) != "340 m":
		errors.append("distance text: %s %s %s" % [MapNav.fmt_dist(42.0), MapNav.fmt_dist(1234.0), MapNav.fmt_dist(340.0)])

func _filters(errors: Array[String]) -> void:
	var ms := _markers()
	var want := ["stage", "stage", "mission", "live", "trap", "landmark", "waypoint"]
	for i in ms.size():
		if MapNav.category(ms[i]) != want[i]:
			errors.append("marker %d is a %s, not a %s" % [i, MapNav.category(ms[i]), want[i]])
	if MapNav.category({"kind": "mystery"}) != "other" or not MapNav.shown({"kind": "mystery"}, {"stage": true}):
		errors.append("a kind with no filter is always shown")
	for cat in MapNav.CATS:
		var hid := {cat.id: true}
		var left := MapNav.items(ms, hid, Vector2.ZERO)
		var gone := 0
		for i in ms.size():
			var cat_i := MapNav.category(ms[i])
			var in_list := left.any(func(it: Dictionary) -> bool: return it.i == i)
			if cat_i == cat.id:
				gone += 1
				if in_list:
					errors.append("%s is switched off yet marker %d is listed" % [cat.id, i])
			elif not in_list:
				errors.append("switching %s off also hid marker %d (%s)" % [cat.id, i, cat_i])
		if left.size() != ms.size() - gone:
			errors.append("hiding %s leaves %d of %d (hid %d)" % [cat.id, left.size(), ms.size(), gone])
	var c := MapNav.counts(ms)
	if c.stage != 2 or c.mission != 1 or c.live != 1 or c.trap != 1 or c.landmark != 1:
		errors.append("counts: %s" % c)
	# the list is nearest the car first, ties by index
	var list := MapNav.items(ms, {}, Vector2(0, 0))
	var order: Array = list.map(func(it: Dictionary) -> int: return it.i)
	if order != [6, 0, 4, 2, 3, 5, 1]:
		errors.append("list order: %s" % [order])
	for k in list.size() - 1:
		if list[k].dist > list[k + 1].dist:
			errors.append("the list is not sorted by distance at %d" % k)
	if list[order.find(5)].name != "Undiscovered landmark" or list[order.find(5)].state != "undiscovered":
		errors.append("an unknown landmark reads as one: %s" % list[order.find(5)])
	if list[order.find(1)].state != "done" or list[order.find(4)].state != "not driven":
		errors.append("item states: %s / %s" % [list[order.find(1)].state, list[order.find(4)].state])
	# hop wraps both ways and starts sensibly from nothing
	if MapNav.hop(list, 6, 1) != 0 or MapNav.hop(list, 6, -1) != int(list[list.size() - 1].i) or MapNav.hop(list, 99, 1) != 6 or MapNav.hop([], 0, 1) != -1:
		errors.append("hop: %d %d %d %d" % [MapNav.hop(list, 6, 1), MapNav.hop(list, 6, -1), MapNav.hop(list, 99, 1), MapNav.hop([], 0, 1)])
	# what is left of a route
	var rt := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	if absf(MapNav.route_left(rt, Vector2(0, 5)) - 200.0) > 0.01 or absf(MapNav.route_left(rt, Vector2(100, 40)) - 60.0) > 0.01 or MapNav.route_left(PackedVector2Array(), Vector2.ZERO) != 0.0:
		errors.append("route left: %s %s" % [MapNav.route_left(rt, Vector2(0, 5)), MapNav.route_left(rt, Vector2(100, 40))])
	# district labels: towns far out, hamlets nearer, nothing at street level
	if MapNav.district_tier("place_village", 4500.0) != 1 or MapNav.district_tier("place_hamlet", 4500.0) != 0 \
			or MapNav.district_tier("place_hamlet", 1500.0) != 2 or MapNav.district_tier("place_town", 100.0) != 0:
		errors.append("district tiers")

func _nav() -> MapNav:
	var n := MapNav.new()
	n.open(BOUNDS, Vector2(1600, 900), Vector2(100, 100))
	n.markers = _markers()
	n.car_pos = Vector2(100, 100)
	n.sel = 0
	return n

func _nav_events(errors: Array[String]) -> void:
	var n := _nav()
	if n.radius != MapNav.DEFAULT_RADIUS or n.centre != Vector2(100, 100):
		errors.append("opens on the car at the default zoom: %s %s" % [n.centre, n.radius])
	# keys: + zooms in, - out, 0 shows everything
	n.handle_event(_key(KEY_EQUAL))
	n.snap()
	if absf(n.radius - MapNav.DEFAULT_RADIUS / MapNav.KEY_STEP) > 0.01:
		errors.append("+ zooms in one step: %s" % n.radius)
	n.handle_event(_key(KEY_MINUS))
	n.snap()
	if absf(n.radius - MapNav.DEFAULT_RADIUS) > 0.01:
		errors.append("- zooms back out: %s" % n.radius)
	for i in 40:
		n.handle_event(_key(KEY_EQUAL))
	n.snap()
	if n.radius != MapNav.MIN_RADIUS:
		errors.append("zoom in stops at street level: %s" % n.radius)
	n.handle_event(_key(KEY_0))
	for i in 200:
		n.step(0.05)
	if absf(n.radius - n.max_radius()) > 1.0 or not _near(n.centre, BOUNDS.get_center(), 1.0):
		errors.append("0 fits the whole area: %s at %s" % [n.radius, n.centre])
	# an eased zoom ends where the target says and holds the anchor on the way
	n = _nav()
	var at := Vector2(1200, 300)
	var w := n.world(at)
	n.zoom_by(3.0, at)
	for i in 8:
		n.step(1.0 / 60.0)
		if not _near(n.world(at), w, 0.5) and n.radius > MapNav.DEFAULT_RADIUS / 3.0 + 1.0:
			errors.append("a gliding zoom let the point under the pointer drift: %s vs %s" % [n.world(at), w])
			break
	for i in 120:
		n.step(1.0 / 60.0)
	if absf(n.radius - MapNav.DEFAULT_RADIUS / 3.0) > 0.5:
		errors.append("the eased zoom reaches its goal: %s" % n.radius)
	# panning: held keys / stick move the view, clamped; Home comes back to the car
	n = _nav()
	n.apply_input({"pan": Vector2(1, 0), "zoom": 0.0}, 0.5)
	if n.centre.x <= 100.0 or n.centre.y != 100.0:
		errors.append("pan right moves the view east only: %s" % n.centre)
	n.apply_input({"pan": Vector2(-1, -1), "zoom": 0.0}, 100.0)
	if n.centre.x - n.radius * n.aspect < BOUNDS.position.x - 0.01 or n.centre.y - n.radius < BOUNDS.position.y - 0.01:
		errors.append("panning far left and up stays inside the area: %s" % n.centre)
	n.handle_event(_key(KEY_HOME))
	for i in 200:
		n.step(0.05)
	if not _near(n.centre, Vector2(100, 100), 1.0):
		errors.append("Home recentres on the car: %s" % n.centre)
	n.apply_input({"pan": Vector2.ZERO, "zoom": 1.0}, 0.3)
	if n.radius >= MapNav.DEFAULT_RADIUS - 1.0:
		errors.append("the right trigger zooms in: %s" % n.radius)
	n.apply_input({"pan": Vector2.ZERO, "zoom": -1.0}, 1.0)
	if n.radius <= MapNav.DEFAULT_RADIUS - 1.0 and n.radius < 0.0:
		errors.append("the left trigger zooms out")
	# the cursor pushes the view at its edge
	n = _nav()
	n.cursor_on = true
	n.cursor = n.centre
	for i in 60:
		n.apply_input({"pan": Vector2(1, 0), "zoom": 0.0}, 0.1)
	var vis := Rect2(n.centre - Vector2(n.radius * n.aspect, n.radius), Vector2(n.radius * n.aspect, n.radius) * 2.0)
	if not vis.grow(0.01).has_point(n.cursor) or n.centre.x <= 100.0:
		errors.append("the cursor stays on screen and the view follows it: cursor %s centre %s" % [n.cursor, n.centre])
	# Tab / pad hop through what is shown, nearest first; the view goes to it and `selected` fires
	n = _nav()
	n.car_pos = Vector2.ZERO
	var picked := []
	n.selected.connect(func(i: int) -> void: picked.append(i))
	n.sel = 6
	n.handle_event(_key(KEY_TAB))
	n.handle_event(_key(KEY_TAB))
	n.handle_event(_key(KEY_TAB, true))
	if picked != [0, 4, 0]:
		errors.append("Tab hops nearest first, Shift+Tab back: %s" % [picked])
	n.snap()
	if not _near(n.centre, Vector2(100, 0), 1.0):
		errors.append("hopping moves the map to the item: %s" % n.centre)
	picked.clear()
	n.sel = 6
	n.handle_event(_btn(JOY_BUTTON_DPAD_RIGHT))
	n.handle_event(_btn(JOY_BUTTON_RIGHT_SHOULDER))
	n.handle_event(_btn(JOY_BUTTON_DPAD_LEFT))
	if picked != [0, 4, 0] or not n.pad:
		errors.append("pad D-pad / bumpers hop: %s" % [picked])
	# filters by key 1-5 and by the panel, remembered through the signal
	n = _nav()
	var saved := []
	n.filters_changed.connect(func(h: Array) -> void: saved.append(h.duplicate()))
	n.handle_event(_key(KEY_4))
	n.handle_event(_key(KEY_1))
	if not n.hidden.has("trap") or not n.hidden.has("stage") or saved.size() != 2 or "trap" not in saved[1] or "stage" not in saved[1]:
		errors.append("keys 4 and 1 switch speed traps and stages off: %s %s" % [n.hidden, saved])
	if n.current_items().size() != 4:
		errors.append("with two categories off 4 of 7 remain: %d" % n.current_items().size())
	n.set_hidden(["live"])
	if n.hidden.size() != 1 or not n.hidden.has("live"):
		errors.append("set_hidden restores a saved filter list")
	n.handle_event(_key(KEY_3))
	if n.hidden.has("live"):
		errors.append("a second press switches the category back on")
	# a selected marker that gets hidden is replaced by one that is shown
	n.sel = 4
	n.handle_event(_key(KEY_4))
	if n.sel == 4:
		errors.append("hiding the selected marker's category moves the selection")
	# the panel: L opens it; up/down moves focus; Enter toggles a filter or goes to an item; Esc closes it first
	n = _nav()
	n.handle_event(_key(KEY_L))
	if not n.panel_open:
		errors.append("L opens the list")
	n.handle_event(_key(KEY_DOWN))
	n.handle_event(_key(KEY_ENTER))
	if not n.hidden.has("mission"):
		errors.append("Enter on the second filter row switches missions off: %s" % n.hidden)
	n.focus = MapNav.CATS.size() # the nearest item
	var first: int = n.current_items()[0].i
	n.handle_event(_key(KEY_ENTER))
	n.snap()
	if n.sel != first or n.panel_open:
		errors.append("Enter on a list row selects it and closes the list: %d vs %d" % [n.sel, first])
	n.panel_open = true
	if not n.handle_event(_key(KEY_ESCAPE)) or n.panel_open:
		errors.append("Esc closes the list first")
	if n.handle_event(_key(KEY_ESCAPE)):
		errors.append("with the list closed Esc is left for the map to close")
	n.handle_event(_btn(JOY_BUTTON_Y))
	if not n.panel_open or not n.pad:
		errors.append("Y opens the filters / list on a pad")
	n.handle_event(_btn(JOY_BUTTON_DPAD_UP))
	if n.focus != n.focus_rows() - 1:
		errors.append("D-pad up from the first row wraps to the last: %d of %d" % [n.focus, n.focus_rows()])
	n.handle_event(_btn(JOY_BUTTON_B))
	if n.panel_open:
		errors.append("B closes the list")
	# R3 / L3
	n = _nav()
	n.route = PackedVector2Array([Vector2(0, 0), Vector2(2000, 1500)])
	n.handle_event(_btn(JOY_BUTTON_LEFT_STICK))
	n.snap()
	if not _near(n.centre, Vector2(2000, 1500), 1.0):
		errors.append("L3 / G goes to the route's destination: %s" % n.centre)
	n.handle_event(_btn(JOY_BUTTON_RIGHT_STICK))
	n.snap()
	if not _near(n.centre, Vector2(100, 100), 1.0):
		errors.append("R3 goes back to the car: %s" % n.centre)
	if n.handle_event(_key(KEY_ENTER)) or n.handle_event(_btn(JOY_BUTTON_A)) or n.handle_event(_key(KEY_F)) or n.handle_event(_btn(JOY_BUTTON_X)):
		errors.append("Enter, A, F and X are left to the map's own handling")
	# the hint follows the device
	if MapNav.hint(true, false, false) == MapNav.hint(false, false, false) or not MapNav.hint(true, false, false).contains("LT"):
		errors.append("the hint names the pad's buttons on a pad")

func _wheel(up: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.position = at
	e.factor = 1.0
	e.pressed = true
	return e

func _mb(pressed: bool, at: Vector2, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.position = at
	e.pressed = pressed
	return e

func _mouse(errors: Array[String]) -> void:
	var n := _nav()
	var at := Vector2(1100, 250)
	var w := n.world(at)
	n.handle_mouse(_wheel(true, at))
	n.handle_mouse(_wheel(true, at))
	n.snap_zoom_rate()
	if absf(n.radius - MapNav.DEFAULT_RADIUS / (MapNav.WHEEL_STEP * MapNav.WHEEL_STEP)) > 0.01 or not _near(n.world(at), w, 0.01):
		errors.append("two wheel notches zoom two steps about the pointer: %s, %s vs %s" % [n.radius, n.world(at), w])
	n.handle_mouse(_wheel(false, at))
	n.snap_zoom_rate()
	if n.radius <= MapNav.DEFAULT_RADIUS / (MapNav.WHEEL_STEP * MapNav.WHEEL_STEP):
		errors.append("the wheel back zooms out")
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 2.0
	pinch.position = at
	var r0 := n.goal_radius
	n.handle_mouse(pinch)
	if absf(n.goal_radius - r0 / 2.0) > 0.01:
		errors.append("a pinch of 2 halves the radius: %s -> %s" % [r0, n.goal_radius])
	# a drag pans the map with the pointer; a short press is a click
	n = _nav()
	var clicks := []
	n.clicked.connect(func(wp: Vector2, i: int) -> void: clicks.append([wp, i]))
	var p0 := Vector2(800, 450)
	var g := n.world(p0)
	n.handle_mouse(_mb(true, p0))
	var mm := InputEventMouseMotion.new()
	mm.position = p0 + Vector2(120, 0)
	mm.relative = Vector2(120, 0)
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	n.handle_mouse(mm)
	n.handle_mouse(_mb(false, p0 + Vector2(120, 0)))
	if not _near(n.world(p0 + Vector2(120, 0)), g, 0.01) or not clicks.is_empty():
		errors.append("dragging 120 px carries the map with it and is not a click: %s" % [clicks])
	n.handle_mouse(_mb(true, Vector2(500, 500)))
	n.handle_mouse(_mb(false, Vector2(500, 500)))
	if clicks.size() != 1 or clicks[0][1] != -1:
		errors.append("a press without a drag on bare map is a click: %s" % [clicks])
	# a click on a marker picks it
	clicks.clear()
	n.centre = Vector2(100, 0)
	n.radius = 400.0
	n.goal_radius = 400.0
	var mp := n.xy(Vector2(100, 0))
	n.handle_mouse(_mb(true, mp + Vector2(3, 2)))
	n.handle_mouse(_mb(false, mp + Vector2(3, 2)))
	if clicks.size() != 1 or clicks[0][1] != 0:
		errors.append("a click within reach of marker 0 reports it: %s" % [clicks])
	n.hidden["stage"] = true
	clicks.clear()
	n.handle_mouse(_mb(true, mp))
	n.handle_mouse(_mb(false, mp))
	if clicks.size() != 1 or clicks[0][1] == 0:
		errors.append("a hidden marker can't be clicked: %s" % [clicks])
	# the filter chips take clicks
	n = _nav()
	var chip: Rect2 = MapNav.layout(n.size, 0).chips[3]
	n.handle_mouse(_mb(true, chip.get_center()))
	if not n.hidden.has("trap"):
		errors.append("clicking the speed-trap chip switches traps off")

func _hud(errors: Array[String], tree: SceneTree) -> void:
	var host := Control.new()
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	var hud := OpenWorldHud.new()
	host.add_child(hud)
	await tree.process_frame
	await tree.process_frame
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("the map did not load")
		host.free()
		return
	hud.map = map
	hud.map_rect = Rect2(map.tx0, map.ty0, 8000, 8000)
	var ms := _markers()
	hud.set_markers(ms)
	hud.car_pos = map.bounds.get_center()
	hud.set_route(PackedVector2Array([hud.car_pos, hud.car_pos + Vector2(500, 300)]))
	hud.big_overlay.size = Vector2(1600, 900)
	hud.toggle_map(true)
	if hud.nav.centre != hud.car_pos or hud.big_map_mat.get_shader_parameter("radius_m") != hud.nav.radius:
		errors.append("the map opens on the car and the shader follows the view")
	# draw at the opening zoom, at street level (names), and the whole area (districts), panel closed and open
	for r: float in [MapNav.DEFAULT_RADIUS, 150.0, hud.nav.max_radius()]:
		hud.nav.goal_radius = r
		hud.nav.snap()
		for open: bool in [false, true]:
			hud.nav.panel_open = open
			hud.big_overlay.queue_redraw()
			await tree.process_frame
	hud.nav.hidden = {"stage": true, "trap": true}
	hud.map_sel = 2
	hud.big_overlay.queue_redraw()
	await tree.process_frame
	# events reach the nav through the HUD, and a click on a marker selects it, a second on it asks to route
	var accepted := [0]
	hud.map_accept.connect(func() -> void: accepted[0] += 1)
	hud.nav.hidden.clear()
	var r0: float = hud.nav.goal_radius
	if not hud.map_event(_key(KEY_EQUAL)) or hud.nav.goal_radius >= r0:
		errors.append("HUD.map_event gives + to the view")
	hud.nav.snap()
	hud.map_tick(0.016)
	if hud.big_map_mat.get_shader_parameter("radius_m") != hud.nav.radius:
		errors.append("a frame later the shader has the new radius")
	hud.map_sel = 0
	var q: Vector2 = hud.nav.xy(ms[1].pos)
	hud.nav.goto(ms[1].pos)
	hud.nav.snap()
	q = hud.nav.xy(ms[1].pos)
	hud._big_map_input(_mb(true, q))
	hud._big_map_input(_mb(false, q))
	if hud.map_sel != 1:
		errors.append("a click on a marker selects it (%d)" % hud.map_sel)
	hud._big_map_input(_mb(true, q))
	hud._big_map_input(_mb(false, q))
	if accepted[0] != 1:
		errors.append("a second click on the selected marker asks for the route (%d)" % accepted[0])
	var wps := []
	hud.waypoint_picked.connect(func(p: Vector2) -> void: wps.append(p))
	var bare := Vector2(40, 840)
	hud._big_map_input(_mb(true, bare))
	hud._big_map_input(_mb(false, bare))
	if wps.size() != 1 or not _near(wps[0], hud.nav.world(bare), 0.01):
		errors.append("a click on bare map still places a waypoint: %s" % [wps])
	hud.toggle_cursor(true)
	if hud.cursor != hud.nav.centre:
		errors.append("the cursor starts in the middle of the view")
	hud.toggle_cursor(false)
	host.free()
