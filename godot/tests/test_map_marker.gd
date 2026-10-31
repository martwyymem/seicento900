## The waypoint/map marker maths (MapMarker): minimap projection (ahead, behind, left/right, rotated),
## the rim clamp for markers beyond the minimap, the big map's pixel <-> metre round trip, keeping a
## placed waypoint inside the play area, and the HUD replacing (not stacking) the waypoint marker.
extends RefCounted

var completed := false
const SZ := Vector2(250, 250)

func run() -> Array:
	var errors: Array[String] = []
	_check_projection(errors)
	_check_rim(errors)
	_check_big_map(errors)
	_check_inside(errors)
	await _check_hud(errors, Engine.get_main_loop() as SceneTree)
	completed = true
	return errors

static func _near(a: Vector2, b: Vector2, e := 0.01) -> bool:
	return a.distance_to(b) <= e

func _check_projection(errors: Array[String]) -> void:
	var car := Vector2(1000, 2000)
	# heading east (0 rad; +y is south): ahead is up, the car's right (south) is right, behind is down
	var cases := [
		["ahead", Vector2(100, 0), 0.0, Vector2(125, 125 - 125 * 100.0 / 250.0)],
		["behind", Vector2(-100, 0), 0.0, Vector2(125, 125 + 125 * 100.0 / 250.0)],
		["right", Vector2(0, 100), 0.0, Vector2(125 + 125 * 100.0 / 250.0, 125)],
		["left", Vector2(0, -100), 0.0, Vector2(125 - 125 * 100.0 / 250.0, 125)],
		# heading south (PI/2): ahead is +y, its right-hand side is west
		["ahead facing south", Vector2(0, 100), PI * 0.5, Vector2(125, 125 - 125 * 100.0 / 250.0)],
		["right facing south", Vector2(-100, 0), PI * 0.5, Vector2(125 + 125 * 100.0 / 250.0, 125)],
		["behind facing north", Vector2(0, 100), -PI * 0.5, Vector2(125, 125 + 125 * 100.0 / 250.0)],
		["on the car", Vector2.ZERO, 1.234, Vector2(125, 125)]]
	for c in cases:
		var got := MapMarker.mini_xy(car + c[1], car, c[2], 250.0, SZ)
		if not _near(got, c[3]):
			errors.append("minimap %s: %s, expected %s" % [c[0], got, c[3]])
	# turning the car turns the map: a marker 100 m ahead stays at the same pixel at any heading
	for h in [0.3, 1.9, -2.5, 3.0]:
		var f := Vector2(cos(h), sin(h))
		if not _near(MapMarker.mini_xy(car + f * 100.0, car, h, 250.0, SZ), Vector2(125, 75)):
			errors.append("a marker dead ahead drifts at heading %s" % h)
	# a zero or negative radius does not blow up
	var z := MapMarker.mini_xy(car + Vector2(50, 0), car, 0.0, 0.0, SZ)
	if not (is_finite(z.x) and is_finite(z.y)):
		errors.append("a zero minimap radius gives %s" % z)

func _check_rim(errors: Array[String]) -> void:
	var inside := MapMarker.rim_clamp(Vector2(125, 60), SZ)
	if inside.edge or inside.pos != Vector2(125, 60):
		errors.append("a marker inside the rim is left alone: %s" % [inside])
	var out := MapMarker.rim_clamp(Vector2(125 + 1000, 125 - 1000), SZ)
	var lim := SZ.x * 0.44
	if not out.edge or absf((out.pos as Vector2).distance_to(SZ * 0.5) - lim) > 0.01:
		errors.append("a far marker lands on the rim circle (%f): %s" % [lim, out])
	if not _near(out.dir, Vector2(1, -1).normalized(), 0.001):
		errors.append("the rim marker keeps its direction: %s" % out.dir)
	# on the boundary stays put; just past it is pulled in
	if MapMarker.rim_clamp(Vector2(125 + lim, 125), SZ).edge:
		errors.append("a marker exactly on the rim is not an edge marker")
	if not MapMarker.rim_clamp(Vector2(125 + lim + 1.0, 125), SZ).edge:
		errors.append("a marker 1 px past the rim is an edge marker")
	var centre := MapMarker.rim_clamp(SZ * 0.5, SZ)
	if centre.edge or not is_finite((centre.dir as Vector2).x):
		errors.append("a marker at the centre has a finite direction: %s" % [centre])
	# the waypoint far behind the car (the camera/minimap looks forward): clamped to the bottom of the rim
	var car := Vector2(0, 0)
	var behind := MapMarker.rim_clamp(MapMarker.mini_xy(Vector2(-5000, 0), car, 0.0, 250.0, SZ), SZ)
	if not behind.edge or (behind.pos as Vector2).y <= SZ.y * 0.5 or absf((behind.pos as Vector2).x - SZ.x * 0.5) > 0.5:
		errors.append("a waypoint straight behind clamps to the bottom of the rim: %s" % [behind])

func _check_big_map(errors: Array[String]) -> void:
	var sz := Vector2(1600, 900)
	var centre := Vector2(-300, 1200)
	for aspect in [1.0, 16.0 / 9.0, 21.0 / 9.0]:
		for p in [Vector2(0, 0), Vector2(-2500, 3000), Vector2(4000, -900)]:
			var q := MapMarker.big_xy(p, centre, 3200.0, aspect, sz)
			var back := MapMarker.big_world(q, centre, 3200.0, aspect, sz)
			if not _near(back, p, 0.01):
				errors.append("big map round trip at aspect %.2f: %s -> %s -> %s" % [aspect, p, q, back])
	if not _near(MapMarker.big_xy(centre, centre, 3200.0, 1.78, sz), sz * 0.5):
		errors.append("the map centre sits mid-screen")
	if not _near(MapMarker.big_xy(centre + Vector2(0, 3200), centre, 3200.0, 1.78, sz), Vector2(800, 900)):
		errors.append("`radius` metres south is the bottom edge")
	if not _near(MapMarker.big_xy(centre + Vector2(3200 * 1.78, 0), centre, 3200.0, 1.78, sz), Vector2(1600, 450)):
		errors.append("`radius * aspect` metres east is the right edge")

func _check_inside(errors: Array[String]) -> void:
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 500), Vector2(500, 1000), Vector2(0, 500)])
	if MapMarker.keep_inside(Vector2(300, 300), poly) != Vector2(300, 300):
		errors.append("a waypoint inside the play area stays where it was put")
	for far in [Vector2(3000, 200), Vector2(-400, -400), Vector2(900, 900), Vector2(500, 5000)]:
		var q := MapMarker.keep_inside(far, poly)
		if not Geometry2D.is_point_in_polygon(q, poly):
			errors.append("%s lands at %s, outside the play area" % [far, q])
		# and it is the nearest edge, not somewhere arbitrary
		if q.distance_to(far) > far.distance_to(Vector2(500, 400)) + 0.1:
			errors.append("%s moved further than the centre would be: %s" % [far, q])
	if MapMarker.keep_inside(Vector2(9, 9), PackedVector2Array()) != Vector2(9, 9):
		errors.append("no outline: the waypoint is left alone")

## Changing the waypoint replaces its marker; the HUD keeps one waypoint, and every marker has a place.
func _check_hud(errors: Array[String], tree: SceneTree) -> void:
	var hud := OpenWorldHud.new()
	hud.size = Vector2(1600, 900)
	tree.root.add_child(hud)
	await tree.process_frame
	var events := [{"pos": Vector2(100, 100), "color": Color.ORANGE, "label": "1. Fiat"}]
	for wp in [Vector2(5, 5), Vector2(900, -300), Vector2(-60000, 9000)]:
		hud.set_markers(events + [{"pos": wp, "color": OpenWorldHud.PURPLE, "label": "WAYPOINT", "kind": "waypoint", "info": "Your waypoint"}])
		hud.car_pos = Vector2(10, 10)
		hud.car_heading = 2.0
		hud.overlay.set_meta("radius", 250.0)
		hud.overlay.size = Vector2(250, 250)
		hud.overlay.queue_redraw() # (draws without errors even for a marker far off the map)
		await tree.process_frame
		var pins := hud.markers.filter(func(m: Dictionary) -> bool: return m.get("kind", "") == "waypoint")
		if pins.size() != 1 or pins[0].pos != wp:
			errors.append("the HUD keeps exactly the latest waypoint (%s): %s" % [wp, pins])
	hud.free()
