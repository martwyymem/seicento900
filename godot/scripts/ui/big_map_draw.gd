class_name BigMapDraw
extends RefCounted
## Draws the big map's overlay for OpenWorldHud: the play-area outline, the route with what is left of it, street
## names up close and district names from afar, the markers (the same pixel size at every zoom, those off screen
## skipped), the car, the cursor, the filter chips and list, the scale bar, the north mark and the info card.
## What is where comes from the HUD's MapNav view.

var _road_boxes: Array[Rect2] = []
var _boxes_for: Object = null
var _streets: Array = [] ## [{pos, angle, text}] for the view in _streets_key
var _streets_key := ""

func draw(hud: OpenWorldHud) -> void:
	var map := hud.map
	if map == null:
		return
	var cv := hud.big_overlay
	var nav: MapNav = hud.nav
	var sz := cv.size
	var view := Rect2(-30, -30, sz.x + 60, sz.y + 60)
	if map.play.size() > 2:
		# the edge of the world: the map picture is dimmed beyond it, and a road ends in a barrier
		var e := PackedVector2Array()
		for p in map.play:
			e.append(nav.xy(p))
		e.append(e[0])
		cv.draw_polyline(e, Color(1, 1, 1, 0.35), 2.0, true)
		for c in map.closures:
			var q := nav.xy(Vector2(c[0], c[1]))
			if view.has_point(q):
				cv.draw_circle(q, 4.0, Color(0.85, 0.15, 0.12, 0.9))
	if map.boundary.size() > 2:
		var b := PackedVector2Array()
		for p in map.boundary:
			b.append(nav.xy(p))
		b.append(b[0])
		cv.draw_polyline(b, Color(OpenWorldHud.ORANGE, 0.55), 2.0, true)
	if hud.route.size() >= 2:
		var pts := PackedVector2Array()
		for p in hud.route:
			pts.append(nav.xy(p))
		cv.draw_polyline(pts, Color(CmrStyle.PLATE, 0.7), 8.0, true)
		cv.draw_polyline(pts, OpenWorldHud.PURPLE.lightened(0.25), 4.5, true)
	var taken: Array[Rect2] = []
	_draw_streets(hud, taken)
	_draw_districts(hud, taken)
	_draw_markers(hud)
	# the car, a fixed size whatever the zoom, pointing the way it faces (north is up)
	hud._draw_car_pointer(cv, nav.xy(hud.car_pos), hud.car_heading, hud._ui_s * 1.5, true)
	if hud.cursor_on:
		var q := nav.xy(hud.cursor)
		cv.draw_line(q - Vector2(16, 0), q + Vector2(16, 0), Color.WHITE, 2.5)
		cv.draw_line(q - Vector2(0, 16), q + Vector2(0, 16), Color.WHITE, 2.5)
		cv.draw_arc(q, 9.0, 0.0, TAU, 24, OpenWorldHud.PURPLE.lightened(0.3), 2.5, true)
	_draw_header(hud)
	_draw_panel(hud)
	_draw_corner(hud)
	_draw_info(hud)

# ------------------------------------------------------------------------------------------ names

func _fits(rect: Rect2, taken: Array[Rect2]) -> bool:
	for t in taken:
		if t.intersects(rect):
			return false
	taken.append(rect)
	return true

func _draw_districts(hud: OpenWorldHud, taken: Array[Rect2]) -> void:
	var nav: MapNav = hud.nav
	if hud.map.places.is_empty() or nav.radius < 350.0:
		return
	var cv := hud.big_overlay
	var view := Rect2(Vector2.ZERO, cv.size)
	for tier in [1, 2]:
		for pl in hud.map.places:
			var k := String(pl.k)
			if not k.begins_with("place_") or MapNav.district_tier(k, nav.radius) != tier:
				continue
			var q := nav.xy(Vector2(float(pl.x), float(pl.y)))
			if not view.has_point(q):
				continue
			var fs := 22 if tier == 1 else 13
			var font := CmrStyle.font(900 if tier == 1 else 700)
			var text := String(pl.name).to_upper() if tier == 1 else String(pl.name)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if not _fits(Rect2(q - Vector2(w * 0.5, fs), Vector2(w, fs * 1.3)), taken):
				continue
			var a := 0.8 if tier == 1 else 0.55
			cv.draw_string_outline(font, q + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, a))
			cv.draw_string(font, q + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))

## Street names, slanted along their street, once the view is close enough to read them.
func _draw_streets(hud: OpenWorldHud, taken: Array[Rect2]) -> void:
	var nav: MapNav = hud.nav
	if nav.radius > MapNav.STREET_RADIUS or hud.map.road_pts.is_empty():
		return
	var key := "%d:%d:%d:%d" % [roundi(nav.centre.x / 2.0), roundi(nav.centre.y / 2.0), roundi(nav.radius), int(nav.aspect * 100.0)]
	if key != _streets_key:
		_streets_key = key
		_streets = _collect_streets(hud)
	var cv := hud.big_overlay
	var font := CmrStyle.font(800)
	for s in _streets:
		var q := nav.xy(s.pos)
		var w: float = s.w
		if not _fits(Rect2(q - Vector2(w * 0.5, 10.0), Vector2(w, 20.0)), taken):
			continue
		cv.draw_set_transform(q, float(s.angle), Vector2.ONE)
		cv.draw_string_outline(font, Vector2(-w * 0.5, 4.0), String(s.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0, 0, 0, 0.85))
		cv.draw_string(font, Vector2(-w * 0.5, 4.0), String(s.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _collect_streets(hud: OpenWorldHud) -> Array:
	var map := hud.map
	var nav: MapNav = hud.nav
	if _boxes_for != map:
		_boxes_for = map
		_road_boxes.clear()
		for pts in map.road_pts:
			var bb := Rect2(pts[0], Vector2.ZERO) if pts.size() > 0 else Rect2()
			for p in pts:
				bb = bb.expand(p)
			_road_boxes.append(bb)
	var vw := Rect2(nav.centre - Vector2(nav.radius * nav.aspect, nav.radius), Vector2(nav.radius * nav.aspect, nav.radius) * 2.0)
	var font := CmrStyle.font(800)
	var out := []
	var seen := {}
	var ppm := nav.size.y * 0.5 / nav.radius
	for ri in map.road_pts.size():
		var text := String(map.road_name[ri]) if ri < map.road_name.size() else ""
		if text == "" or not _road_boxes[ri].intersects(vw):
			continue
		var pts: PackedVector2Array = map.road_pts[ri]
		# the run of the street inside the view: its middle, its direction, its length in pixels
		var inside := PackedVector2Array()
		for p in pts:
			if vw.has_point(p):
				inside.append(p)
		if inside.size() < 2:
			continue
		var run := 0.0
		for k in inside.size() - 1:
			run += inside[k].distance_to(inside[k + 1])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if run * ppm < w + 16.0:
			continue
		var half := run * 0.5
		var at := inside[0]
		var dir := Vector2.RIGHT
		for k in inside.size() - 1:
			var l := inside[k].distance_to(inside[k + 1])
			if half <= l:
				dir = (inside[k + 1] - inside[k]) / maxf(l, 0.001)
				at = inside[k].lerp(inside[k + 1], half / maxf(l, 0.001))
				break
			half -= l
		var ang := dir.angle()
		if absf(ang) > PI * 0.5:
			ang = wrapf(ang + PI, -PI, PI)
		var sk := "%s:%d:%d" % [text, roundi(at.x / 200.0), roundi(at.y / 200.0)]
		if seen.has(sk):
			continue
		seen[sk] = true
		out.append({"pos": at, "angle": ang, "text": text, "w": w})
		if out.size() >= 70:
			break
	return out

# ------------------------------------------------------------------------------------------ markers

func _draw_markers(hud: OpenWorldHud) -> void:
	var nav: MapNav = hud.nav
	var cv := hud.big_overlay
	var font := CmrStyle.font(800)
	var view := Rect2(-40, -40, cv.size.x + 80, cv.size.y + 80)
	var show_poi_labels := nav.radius <= MapNav.POI_LABEL_RADIUS
	var drawn_sel := false
	for pass_sel in [false, true]:
		for i in hud.markers.size():
			var m: Dictionary = hud.markers[i]
			var sel := i == hud.map_sel
			if sel != pass_sel or not m.get("pos") is Vector2 or not MapNav.shown(m, nav.hidden):
				continue
			var q := nav.xy(m.pos)
			if not view.has_point(q):
				continue
			drawn_sel = drawn_sel or sel
			var label := String(m.get("label", ""))
			if String(m.get("kind", "")) == "poi":
				hud._draw_poi(cv, q, m, 9.0 if sel else 6.5, sel)
				if sel or (show_poi_labels and label != ""):
					cv.draw_string_outline(font, q + Vector2(14, 5), label if label != "" else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if sel else 12, 4, Color(0, 0, 0, 0.8))
					cv.draw_string(font, q + Vector2(14, 5), label if label != "" else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if sel else 12, Color.WHITE if sel else Color(1, 1, 1, 0.7))
				continue
			var col: Color = m.get("color", Color.WHITE)
			cv.draw_circle(q, 13.0 if sel else 10.0, Color(0, 0, 0, 0.7))
			cv.draw_circle(q, 10.0 if sel else 7.0, col)
			if sel:
				cv.draw_arc(q, 18.0, 0.0, TAU, 32, Color.WHITE, 2.5, true)
			elif String(m.get("kind", "")) == "waypoint":
				cv.draw_arc(q, 12.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)
			if label != "":
				cv.draw_string_outline(font, q + Vector2(16, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if sel else 13, 4, Color(0, 0, 0, 0.8))
				cv.draw_string(font, q + Vector2(16, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if sel else 13, Color.WHITE if sel else Color(1, 1, 1, 0.8))
	# the route's end: a flag-like ring with what is left of the way
	if hud.route.size() >= 2:
		var e := nav.xy(hud.route[hud.route.size() - 1])
		if view.has_point(e):
			cv.draw_arc(e, 15.0, 0.0, TAU, 28, OpenWorldHud.PURPLE.lightened(0.35), 3.0, true)

# ------------------------------------------------------------------------------------------ chrome

func _draw_header(hud: OpenWorldHud) -> void:
	var cv := hud.big_overlay
	var nav: MapNav = hud.nav
	cv.draw_string(CmrStyle.font(900), Vector2(40, 60), "BRZESZCZE · MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	cv.draw_string(CmrStyle.font(600), Vector2(40, 92), MapNav.hint(nav.pad, hud.cursor_on, nav.panel_open),
		HORIZONTAL_ALIGNMENT_LEFT, maxf(cv.size.x - 340.0, 300.0), 16, Color(1, 1, 1, 0.75))
	if hud.summary != "":
		cv.draw_string(CmrStyle.font(800), Vector2(40, 118), hud.summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		hud._draw_map_legend(Vector2(40 + CmrStyle.font(800).get_string_size(hud.summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 36.0, 113.0))

## The filter chips (always, compact) and, when open, the list under them.
func _draw_panel(hud: OpenWorldHud) -> void:
	var cv := hud.big_overlay
	var nav: MapNav = hud.nav
	var list := nav.current_items()
	var lay := MapNav.layout(cv.size, list.size() if nav.panel_open else 0)
	var counts := MapNav.counts(hud.markers)
	var font := CmrStyle.font(800)
	if nav.panel_open:
		var pr: Rect2 = lay.panel
		cv.draw_rect(pr, Color(CmrStyle.PLATE, 0.82))
	for i in MapNav.CATS.size():
		var cat: Dictionary = MapNav.CATS[i]
		var r: Rect2 = lay.chips[i]
		var on := not nav.hidden.has(cat.id)
		var foc: bool = nav.panel_open and nav.focus == i
		cv.draw_rect(r, Color(CmrStyle.PLATE, 0.78 if on else 0.5))
		cv.draw_rect(Rect2(r.position, Vector2(5, r.size.y)), cat.color if on else Color(1, 1, 1, 0.25))
		if foc:
			cv.draw_rect(r, Color.WHITE, false, 2.0)
		var a := 1.0 if on else 0.4
		cv.draw_string(font, r.position + Vector2(14, 19), "%d  %s" % [i + 1, cat.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, a))
		cv.draw_string(font, r.position + Vector2(0, 19), str(counts.get(cat.id, 0)), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10.0, 14, Color(1, 1, 1, a))
	if not nav.panel_open:
		return
	var first := MapNav.list_first(nav.focus, list.size())
	for k in lay.rows.size():
		var it: Dictionary = list[first + k]
		var r: Rect2 = lay.rows[k]
		var foc: bool = nav.focus == MapNav.CATS.size() + first + k
		if foc:
			cv.draw_rect(r, Color(1, 1, 1, 0.16))
			cv.draw_rect(r, Color.WHITE, false, 1.5)
		elif int(it.i) == hud.map_sel:
			cv.draw_rect(r, Color(1, 1, 1, 0.08))
		var col := Color.WHITE
		for cat in MapNav.CATS:
			if cat.id == it.cat:
				col = cat.color
		cv.draw_circle(r.position + Vector2(9, r.size.y * 0.5), 4.0, col)
		var dist := MapNav.fmt_dist(float(it.dist))
		var state := String(it.state)
		cv.draw_string(CmrStyle.font(600), r.position + Vector2(20, 17), String(it.name) + ("  · " + state if state != "" else ""),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 82.0, 13, Color(1, 1, 1, 0.9))
		cv.draw_string(font, r.position + Vector2(0, 17), dist, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0, 13, Color(1, 1, 1, 0.8))
	if list.size() > MapNav.LIST_ROWS:
		var last: Rect2 = lay.rows[lay.rows.size() - 1]
		cv.draw_string(CmrStyle.font(600), last.position + Vector2(0, 40), "%d of %d" % [first + MapNav.LIST_ROWS, list.size()],
			HORIZONTAL_ALIGNMENT_RIGHT, last.size.x, 12, Color(1, 1, 1, 0.55))
	if list.is_empty():
		cv.draw_string(CmrStyle.font(600), (lay.chips[MapNav.CATS.size() - 1] as Rect2).position + Vector2(6, 54), "nothing shown: switch a filter on",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))

## North, the scale bar and the route's remaining distance, bottom right.
func _draw_corner(hud: OpenWorldHud) -> void:
	var cv := hud.big_overlay
	var nav: MapNav = hud.nav
	var sz := cv.size
	# north mark, top right
	var n := Vector2(sz.x - 60.0, 62.0)
	cv.draw_colored_polygon(PackedVector2Array([n + Vector2(0, -16), n + Vector2(8, 4), n + Vector2(0, 0), n + Vector2(-8, 4)]), Color.WHITE)
	cv.draw_string(CmrStyle.font(900), n + Vector2(-8, 24), "N", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 15, Color.WHITE)
	var bar := MapNav.scale_bar(nav.radius, sz.y)
	var x1 := sz.x - 40.0
	var y := sz.y - 44.0
	var x0: float = x1 - float(bar.px)
	cv.draw_line(Vector2(x0, y), Vector2(x1, y), Color(0, 0, 0, 0.8), 6.0)
	cv.draw_line(Vector2(x0, y - 6), Vector2(x0, y + 6), Color(0, 0, 0, 0.8), 6.0)
	cv.draw_line(Vector2(x1, y - 6), Vector2(x1, y + 6), Color(0, 0, 0, 0.8), 6.0)
	cv.draw_line(Vector2(x0, y), Vector2(x1, y), Color.WHITE, 2.5)
	cv.draw_line(Vector2(x0, y - 5), Vector2(x0, y + 5), Color.WHITE, 2.5)
	cv.draw_line(Vector2(x1, y - 5), Vector2(x1, y + 5), Color.WHITE, 2.5)
	cv.draw_string_outline(CmrStyle.font(800), Vector2(x0, y - 12), String(bar.text), HORIZONTAL_ALIGNMENT_RIGHT, float(bar.px), 14, 4, Color(0, 0, 0, 0.8))
	cv.draw_string(CmrStyle.font(800), Vector2(x0, y - 12), String(bar.text), HORIZONTAL_ALIGNMENT_RIGHT, float(bar.px), 14, Color.WHITE)
	if hud.route.size() >= 2:
		var t := "ROUTE  %s left" % MapNav.fmt_dist(MapNav.route_left(hud.route, hud.car_pos))
		cv.draw_string_outline(CmrStyle.font(900), Vector2(sz.x - 340.0, y - 36), t, HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 17, 5, Color(0, 0, 0, 0.8))
		cv.draw_string(CmrStyle.font(900), Vector2(sz.x - 340.0, y - 36), t, HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 17, OpenWorldHud.PURPLE.lightened(0.45))

## What the selected place is, how far, and what Enter does; wraps upwards from the foot of the map.
func _draw_info(hud: OpenWorldHud) -> void:
	var cv := hud.big_overlay
	var nav: MapNav = hud.nav
	if hud.map_sel < 0 or hud.map_sel >= hud.markers.size() or not MapNav.shown(hud.markers[hud.map_sel], nav.hidden):
		return
	var m: Dictionary = hud.markers[hud.map_sel]
	var info := String(m.get("info", ""))
	if m.get("pos") is Vector2:
		info += "  ·  %s away" % MapNav.fmt_dist((m.pos as Vector2).distance_to(hud.car_pos))
	var ifont := CmrStyle.font(800)
	var wrap := maxf(cv.size.x - 460.0, 200.0)
	var h := ifont.get_multiline_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, wrap, 18).y
	cv.draw_multiline_string(ifont, Vector2(40, cv.size.y - 66 - h + ifont.get_ascent(18)), info, HORIZONTAL_ALIGNMENT_LEFT, wrap, 18, -1, OpenWorldHud.GOLD)
	var act := "A  set route" if nav.pad else "Enter  set route"
	if hud.cursor_on:
		act = "A  waypoint at the cursor" if nav.pad else "Enter  waypoint at the cursor"
	cv.draw_string(CmrStyle.font(700), Vector2(40, cv.size.y - 40), act, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7))
