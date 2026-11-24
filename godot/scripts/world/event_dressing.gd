## What an open-world event (a live event or a campaign mission on the map) brings with it while it is driven, and
## nothing else: a start-light gantry over the road at the line, and spectators along its route. OpenWorld hands the
## run over each frame (`update`); the dressing is built the frame a run begins, freed the frame it ends, is
## abandoned or restarts (a restart is a new run, so it builds again). Nothing here is part of the permanent map: the
## festival's own crowds (festival_dressing.gd) are a separate, permanent set.
##
## The gantry: two posts either side of the road (outside its half width, `TownMap.road_halves` through road_at), a beam,
## and five light columns that light one by one every LIGHT_STEP s from the first second of the countdown and all go out
## at GO (`lit_columns` is the whole timing: LiveEvents.COUNTDOWN is the countdown's length). A standing start only:
## drift zones start by driving through their gate and get none. A rally has one gantry per special stage, lit in its
## own countdown. One draw call a gantry (shaders/start_gantry.gdshader), the lit count an instance uniform.
##
## The spectators: MultiMesh crowds of the festival's own people (the SpectatorStand / Cheer / Wave meshes and
## shaders/spectator.gdshader: they cheer, wave and jump back as the car comes) at the start, the finish and the sharpest
## corners of the route, on both sides of the road where there is room, behind a strip of barrier tape. Every person
## stands off every road (half width + ROAD_MARGIN), outside every building (`TownMap.building_faces` and the footprint)
## and off water, rail and tunnel cuts. At most MAX_SPECTATORS people in all.
class_name EventDressing
extends Node3D

const SPECTATOR_SHADER := preload("res://shaders/spectator.gdshader")
const GANTRY_SHADER := preload("res://shaders/start_gantry.gdshader")

const COLUMNS := 5 ## light columns
const LIGHT_STEP := 0.5 ## s between one column and the next
const GANTRY_AHEAD := 5.5 ## m the gantry stands past the pole position's row
const POST_CLEAR := 0.8 ## m a post stands beyond the road's edge (at least)
const BEAM_Y := 6.0 ## m over the road: the beam's middle
const NO_GANTRY := ["drift_zone"] ## start by driving through a gate (LiveEvents.gates_ahead), not off a line
const GANTRY_RANGE := 320.0

const MAX_SPECTATORS := 320
const ROAD_MARGIN := 1.5 ## m beyond a road's half width nobody stands
const BUILDING_MARGIN := 0.6 ## m from a building's wall nobody stands
const SPECTATOR_RANGE := 215.0
const ROW_GAP := 0.95 ## m between two rows of a crowd
const FIRST_ROW := 1.9 ## m past the road's edge the first row stands (tape in front of it at TAPE_OFF)
const TAPE_OFF := 1.3
const START_PEOPLE := 26 ## people a side of the start / the finish / a corner's outside / its inside
const FINISH_PEOPLE := 26
const CORNER_OUT_PEOPLE := 22
const CORNER_IN_PEOPLE := 10
const CORNER_MIN_TURN := 0.55 ## rad over 30 m: a bend this sharp draws a crowd
const CORNER_SPACING := 70.0 ## m between two crowded corners
const CORNER_END_CLEAR := 45.0 ## m from the start / finish a corner must be to count

var map: TownMap
var builder: TownBuilder
var gantries: Array = [] ## {stage, pos, dir (travel), across, half, posts [Vector2, Vector2], node, lit}
var people: Array = [] ## {pos, face, pose, y, site}: every spectator placed
var groups: Array = [] ## {pos, tangent, kind, people, side}: a crowd (one side of one spot)
var tape: Array = [] ## [Vector2, Vector2]: one strip of barrier tape (its two ends)
var crowd_parts := {} ## the last crowd build's sites / placing / committing times (ms)
var stats := {} ## last build: gantries, spectators, groups, build_ms (the whole), gantry_ms, crowd_ms
var _run_ref: Variant = null ## the LiveEvents run this was built for
var _gantry_mat: ShaderMaterial
var _spec_mat: ShaderMaterial
var _own_spec_mat := false
var _tape_mat: StandardMaterial3D

func _init(town: TownMap = null, bld: TownBuilder = null) -> void:
	map = town
	builder = bld
	name = "EventDressing"
	top_level = true # world-placed, whatever it is hung under

func _exit_tree() -> void:
	if builder and _gantry_mat:
		builder.night_materials.erase(_gantry_mat)
	if builder and _own_spec_mat and _spec_mat:
		builder.night_materials.erase(_spec_mat)

## True while anything of an event stands.
func active() -> bool:
	return _run_ref != null

## Called every frame from OpenWorld._update_live with the run's step `dt` (s of simulation this frame, the same the
## run's own tick takes) and the car's world position and velocity (the spectators' shader reads them when the festival
## has no material to share): builds on a new run, lights the gantry, frees on the end of the run.
func update(live: LiveEvents, dt: float, car_pos := Vector3.ZERO, car_vel := Vector3.ZERO) -> void:
	if live == null or not live.is_running():
		if _run_ref != null:
			clear()
		return
	if not is_same(live.run, _run_ref):
		clear()
		build(live)
	if _own_spec_mat and _spec_mat:
		_spec_mat.set_shader_parameter("car_pos", car_pos)
		_spec_mat.set_shader_parameter("car_vel", car_vel)
	var run: Dictionary = live.run
	var t := float(run.t)
	if String(run.state) == "countdown":
		t += dt # the tick this frame is about to take: the lights follow the count it makes, not the one before it
	for g in gantries:
		var n := lit_columns(String(run.state), t) if int(g.stage) < 0 or int(g.stage) == int(run.stage) else 0
		if n != int(g.lit):
			g.lit = n
			(g.node as MeshInstance3D).set_instance_shader_parameter("lit", float(n))

## Columns lit at run time t (LiveEvents run.t: -COUNTDOWN at the start of the count, 0 at GO) in the run's state: one
## more every LIGHT_STEP from the first moment of the countdown, all five by the last second, all out at GO and after.
static func lit_columns(state: String, t: float) -> int:
	if state != "countdown" or t >= 0.0:
		return 0
	return clampi(int(floorf((t + LiveEvents.COUNTDOWN) / LIGHT_STEP)) + 1, 0, COLUMNS)

## Frees everything of the event (gantries, crowds, tape). Cheap to call when nothing stands.
func clear() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	gantries.clear()
	people.clear()
	groups.clear()
	tape.clear()
	stats = {}
	_run_ref = null

# ---------------------------------------------------------------------------------------------------- building

## Builds the gantries and the crowds of the run being driven (clear() first when one stands).
func build(live: LiveEvents) -> void:
	_run_ref = live.run
	var t0 := Time.get_ticks_usec()
	var ev: Dictionary = live.run.ev
	var starts := []
	if String(ev.kind) == "rally":
		for k in (ev.stages as Array).size():
			var pose: Array = live.stage_pose(k)
			starts.append({"stage": k, "pos": pose[0], "heading": float(pose[1]), "route": ev.stages[k].path})
	else:
		var pose: Array = live.grid_pose(ev)
		starts.append({"stage": -1, "pos": pose[0], "heading": float(pose[1]), "route": ev.path})
	var t1 := Time.get_ticks_usec()
	if not NO_GANTRY.has(String(ev.kind)):
		_build_gantries(starts, ev.get("color", Color("#ff3d8b")))
	var t2 := Time.get_ticks_usec()
	_build_crowds(starts)
	var t3 := Time.get_ticks_usec()
	stats = {"gantries": gantries.size(), "spectators": people.size(), "groups": groups.size(), "tape": tape.size(),
		"build_ms": (t3 - t0) / 1000.0, "gantry_ms": (t2 - t1) / 1000.0, "crowd_ms": (t3 - t2) / 1000.0}

func _ground_y(p: Vector2) -> float:
	return map.ground(p.x, p.y) + map.kerb_at(p.x, p.y)

func _ensure_gantry_mat(col: Color) -> void:
	if _gantry_mat == null:
		_gantry_mat = ShaderMaterial.new()
		_gantry_mat.shader = GANTRY_SHADER
		if builder:
			builder.night_materials.append(_gantry_mat)
	_gantry_mat.set_shader_parameter("accent", col)

func _ensure_crowd_mats() -> void:
	if _spec_mat == null:
		if builder and builder.festival and builder.festival.spectator_mat:
			_spec_mat = builder.festival.spectator_mat # the festival's own: it drives the car and the night
		else:
			_spec_mat = ShaderMaterial.new()
			_spec_mat.shader = SPECTATOR_SHADER
			_own_spec_mat = true
			if builder:
				builder.night_materials.append(_spec_mat)
	if _tape_mat == null:
		_tape_mat = StandardMaterial3D.new()
		_tape_mat.vertex_color_use_as_albedo = true
		_tape_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tape_mat.roughness = 0.7
		_tape_mat.emission_enabled = true
		_tape_mat.emission = Color(0.16, 0.16, 0.16)

# ---------------------------------------------------------------------------------------------------- gantry

func _build_gantries(starts: Array, col: Color) -> void:
	_ensure_gantry_mat(col)
	for s in starts:
		var g := _gantry_site(s)
		if g.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "StartGantry" if int(s.stage) < 0 else "StartGantry%d" % int(s.stage)
		mi.mesh = _gantry_mesh(g)
		mi.material_override = _gantry_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = GANTRY_RANGE
		mi.extra_cull_margin = 4.0
		var d: Vector2 = g.dir
		var fwd := Vector3(d.x, 0.0, d.y)
		var across := Vector3(g.across.x, 0.0, g.across.y)
		mi.transform = Transform3D(Basis(across, Vector3.UP, fwd), Vector3(g.pos.x, g.y, g.pos.y))
		add_child(mi)
		mi.set_instance_shader_parameter("lit", 0.0)
		g["node"] = mi
		g["lit"] = 0
		g["stage"] = int(s.stage)
		gantries.append(g)

## Where the gantry for a start {pos, heading} stands: GANTRY_AHEAD m on from the pole position, on the road's centre line,
## square across the route; its posts outside the road's edges. {} when no road is found there.
func _gantry_site(s: Dictionary) -> Dictionary:
	var h := float(s.heading)
	var d := Vector2(cos(h), sin(h))
	var at: Vector2 = (s.pos as Vector2) + d * GANTRY_AHEAD
	var near := map.nearest_road(at, 12.0)
	if near.is_empty():
		return {}
	var centre: Vector2 = near.pos
	var hit := map.road_at(centre.x, centre.y, -INF, 0.5)
	if hit.is_empty():
		return {}
	var half := float(hit.half)
	var across := Vector2(d.y, -d.x)
	var posts := []
	var offs := []
	for side in [-1.0, 1.0]:
		var off := half + POST_CLEAR
		var best := off
		var found := false
		for k in 6: # out from the kerb until the post does not stand in a wall or on another road
			var p: Vector2 = centre + across * side * off
			if map.road_at(p.x, p.y, -INF, 0.3).is_empty() and not map.inside_building(p) and map.buildings_near(p, 0.3).is_empty():
				best = off
				found = true
				break
			off += 0.6
		if not found:
			best = half + POST_CLEAR
		offs.append(best)
		posts.append(centre + across * side * best)
	var y: float = float(hit.height)
	return {"pos": centre, "dir": d, "across": across, "half": half, "posts": posts, "offs": offs, "y": y}

func _gantry_mesh(g: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var offs: Array = g.offs
	var y0: float = g.y
	var xl := -float(offs[0]) # the left post's x across the road (local), the right one's
	var xr := float(offs[1])
	var grey := 0.16
	# posts: from below the lower of the road and the ground at the foot up to the beam
	var posts: Array = g.posts
	for k in 2:
		var p: Vector2 = posts[k]
		var base := minf(y0, _ground_y(p)) - 0.25
		var x := xl if k == 0 else xr
		var ph := BEAM_Y + 0.3 - (base - y0)
		_box(st, Vector3(x, (base - y0) + ph * 0.5, 0.0), Vector3(0.5, ph, 0.5), Color(grey, 0.0, 0.0))
	var mid := (xl + xr) * 0.5
	var len := xr - xl + 0.9
	_box(st, Vector3(mid, BEAM_Y, 0.0), Vector3(len, 0.55, 0.6), Color(grey * 1.3, 0.0, 0.0))
	_box(st, Vector3(mid, BEAM_Y, 0.0), Vector3(len - 0.5, 0.16, 0.66), Color(0.0, 0.5, 0.0)) # the event's colour stripe (part code 0.5)
	# the five pods hung under the beam, centred on the road's centre line
	var span := minf(-xl, xr)
	var gap := clampf(span * 0.34, 1.1, 2.1)
	var pod_h := 1.5
	for k in COLUMNS:
		var x := (float(k) - 2.0) * gap
		var top := BEAM_Y - 0.28
		_box(st, Vector3(x, top - pod_h * 0.5, 0.0), Vector3(gap * 0.82, pod_h, 0.5), Color(0.05, 0.0, 0.0))
		for j in 3:
			var ly := top - 0.32 - j * 0.42
			_lamp(st, Vector3(x, ly, 0.27), 1.0, k)
			_lamp(st, Vector3(x, ly, -0.27), -1.0, k)
	return st.commit()

## An axis-aligned box in the gantry's local space, vertex colour `col` (R: shade, G: part code: 0 frame, 0.5 accent stripe).
func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corners := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)], [4, 0, 3, 7, Vector3(-1, 0, 0)],
		[1, 5, 6, 2, Vector3(1, 0, 0)], [3, 2, 6, 7, Vector3(0, 1, 0)], [4, 5, 1, 0, Vector3(0, -1, 0)]]
	for f in faces:
		var n: Vector3 = f[4]
		st.set_color(col)
		st.set_normal(n)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c + (corners[f[idx]] as Vector3))

## A round lamp (a 10-gon) of column k facing `face` (+1 / -1 along z), vertex colour R = k / 4, G = 1.
func _lamp(st: SurfaceTool, c: Vector3, face: float, k: int) -> void:
	const N := 10
	const R := 0.2
	var col := Color(float(k) / float(COLUMNS - 1), 1.0, 0.0)
	for i in N:
		var a0 := TAU * i / N
		var a1 := TAU * (i + 1) / N
		var p0 := c + Vector3(cos(a0) * R, sin(a0) * R, 0.0)
		var p1 := c + Vector3(cos(a1) * R, sin(a1) * R, 0.0)
		st.set_color(col)
		st.set_normal(Vector3(0, 0, face))
		if face > 0.0:
			st.add_vertex(c)
			st.add_vertex(p0)
			st.add_vertex(p1)
		else:
			st.add_vertex(c)
			st.add_vertex(p1)
			st.add_vertex(p0)

# ---------------------------------------------------------------------------------------------------- crowds

func _build_crowds(starts: Array) -> void:
	var t0 := Time.get_ticks_usec()
	_ensure_crowd_mats()
	var sites := crowd_sites(map, starts)
	var t1 := Time.get_ticks_usec()
	var routes := maxi(starts.size(), 1)
	var per_route := MAX_SPECTATORS / routes
	var used := {}
	var taken := 0
	for site in sites:
		var r := int(site.route)
		var room := mini(per_route - int(used.get(r, 0)), MAX_SPECTATORS - taken)
		if room <= 0:
			continue
		for side in [-1.0, 1.0]:
			if room <= 0:
				break
			var n := _place_group(site, side, room)
			room -= n
			taken += n
			used[r] = int(used.get(r, 0)) + n
	var t2 := Time.get_ticks_usec()
	_commit_crowds()
	var t3 := Time.get_ticks_usec()
	crowd_parts = {"sites_ms": (t1 - t0) / 1000.0, "place_ms": (t2 - t1) / 1000.0, "commit_ms": (t3 - t2) / 1000.0}

## The spots a crowd stands at, in the order they are filled: the start and the finish of every route, then the route's
## sharpest corners (largest turn first). A site is {pos, tangent (the road's direction there), kind, route, score,
## outer (the side the crowd stands on first: a corner's outside; Vector2.ZERO for both), people}.
static func crowd_sites(town: TownMap, starts: Array) -> Array:
	var first := []
	var corners := []
	for r in starts.size():
		var s: Dictionary = starts[r]
		var route: PackedVector2Array = s.route
		if route.size() < 2:
			continue
		var heading := float(s.heading)
		var gantry_at: Vector2 = (s.pos as Vector2) + Vector2(cos(heading), sin(heading)) * GANTRY_AHEAD
		var near := town.nearest_road(gantry_at, 12.0)
		var sp: Vector2 = near.pos if not near.is_empty() else gantry_at
		first.append({"pos": sp, "tangent": Vector2(cos(heading), sin(heading)), "kind": "start", "route": r, "score": 99.0,
			"outer": Vector2.ZERO, "people": START_PEOPLE})
		var end := route[route.size() - 1]
		if end.distance_to(route[0]) > 60.0: # a lap's finish is its start
			var back := route[maxi(route.size() - 4, 0)]
			var tg := (end - back).normalized()
			if tg.length_squared() < 0.5:
				tg = Vector2(1, 0)
			first.append({"pos": end, "tangent": tg, "kind": "finish", "route": r, "score": 98.0, "outer": Vector2.ZERO,
				"people": FINISH_PEOPLE})
		corners.append_array(_corners(route, r, end))
	corners.sort_custom(func(a, b): return float(a.score) > float(b.score))
	return first + corners

## The sharpest bends of a route: turning (rad) over a 30 m window, local maxima at least CORNER_SPACING m apart, none
## within CORNER_END_CLEAR of the start or the finish, at most one per 220 m of route.
static func _corners(route: PackedVector2Array, r: int, end: Vector2) -> Array:
	var pts := LiveEvents.resample(route, 3.0)
	var w := 5
	var cand := []
	for i in range(w, pts.size() - w):
		var a := pts[i] - pts[i - w]
		var b := pts[i + w] - pts[i]
		if a.length_squared() < 1e-3 or b.length_squared() < 1e-3:
			continue
		var turn := a.angle_to(b)
		if absf(turn) >= CORNER_MIN_TURN and pts[i].distance_to(route[0]) > CORNER_END_CLEAR and pts[i].distance_to(end) > CORNER_END_CLEAR:
			cand.append({"i": i, "turn": turn, "a": a.normalized(), "b": b.normalized()})
	cand.sort_custom(func(x, y): return absf(float(x.turn)) > absf(float(y.turn)))
	var keep := maxi(1, int(LiveEvents.path_length(route) / 220.0))
	var out := []
	var chosen := []
	for c in cand:
		var p := pts[int(c.i)]
		var ok := true
		for q in chosen:
			if p.distance_to(q) < CORNER_SPACING:
				ok = false
				break
		if not ok:
			continue
		chosen.append(p)
		# the outside of the bend is the way the route is turning from: opposite the change of heading
		var out_dir: Vector2 = -((c.b as Vector2) - (c.a as Vector2)).normalized()
		var tang: Vector2 = Vector2(-out_dir.y, out_dir.x)
		out.append({"pos": p, "tangent": tang, "kind": "corner", "route": r, "score": absf(float(c.turn)), "outer": out_dir,
			"people": CORNER_OUT_PEOPLE})
		if out.size() >= keep:
			break
	return out

const H_WATER := 1
const H_RAIL := 2
const H_DECK := 4
const H_TUNNEL := 8
const H_ALL := 15

## Whether a person may stand at p: inside the play area, off every road by its half width + `road_margin` (road_at reads
## the per-point halves of TownMap.road_halves), outside every building (footprint and drawn walls, `bld_margin` clear of
## them), off water, the railway, a tunnel's cut and a bridge's deck. `hazards` (H_* bits) names the last four tests to
## run: a caller that knows from hazards_near that none lies round p can skip the slowest ones.
static func spot_ok(town: TownMap, p: Vector2, road_margin := ROAD_MARGIN, bld_margin := BUILDING_MARGIN, hazards := H_ALL) -> bool:
	if not town.in_play(p):
		return false
	if not town.road_at(p.x, p.y, -INF, road_margin).is_empty():
		return false
	if building_near(town, p, bld_margin):
		return false
	if hazards & H_WATER and not is_nan(town.water_at(p)):
		return false
	if hazards & H_RAIL and town.rail_distance(p, 5.5) <= 4.5:
		return false
	if hazards & H_TUNNEL and town.in_tunnel_cut(p):
		return false
	if hazards & H_DECK and not town.decks_at(p.x, p.y, 1.8).is_empty():
		return false
	return true

## Which of the H_* hazards (water, a railway, a tunnel's cut, a raised road: bridge or embankment) lie within `r` of p.
static func hazards_near(town: TownMap, p: Vector2, r: float) -> int:
	var bits := 0
	var box := Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)
	var boxp := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
	for k in town.water_rects.size():
		# the water's polygon can have thousands of corners, and a point test against it costs tens of microseconds:
		# one clip of it against the crowd's box (in C++) says whether any spot of the crowd can be in it
		if box.intersects(town.water_rects[k]) and not Geometry2D.intersect_polygons(boxp, town.water_rings[k]).is_empty():
			bits |= H_WATER
			break
	if town.rail_distance(p, r) < r:
		bits |= H_RAIL
	if not town.decks_at(p.x, p.y, r).is_empty():
		bits |= H_DECK
	for t in town.tunnels:
		if p.distance_to(t.c) < float(t.cut_len) + float(t.cut_half) + r:
			bits |= H_TUNNEL
			break
	return bits

## True when p is inside a building (its footprint ring, or the polygon of the walls it is drawn with) or within `margin`
## of one of its walls (`TownMap.building_faces`).
static func building_near(town: TownMap, p: Vector2, margin: float) -> bool:
	for bi in town.buildings_near(p, margin):
		if TownMap.inside(p, town.bld_rings[bi]):
			return true
		var faces := town.building_faces(bi)
		var custom := town.bld_faces.has(bi) # walls drawn off the footprint: their outline is a polygon of its own
		var poly := PackedVector2Array()
		var k := 0
		while k + 5 < faces.size():
			var a := Vector2(faces[k], faces[k + 1])
			var b := Vector2(faces[k + 2], faces[k + 3])
			if custom:
				poly.append(a)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < margin:
				return true
			k += 6
		if poly.size() >= 3 and TownMap.inside(p, poly):
			return true
	return false

## Fills one side of a site with up to `room` (and the site's own) people in rows from FIRST_ROW past the road's edge,
## and puts a strip of tape in front of them. Returns how many stood.
func _place_group(site: Dictionary, side: float, room: int) -> int:
	var pos: Vector2 = site.pos
	var tang: Vector2 = site.tangent
	var normal := Vector2(-tang.y, tang.x)
	var kind := String(site.kind)
	var outer: Vector2 = site.outer
	var rows := 3
	var want := int(site.people)
	if kind == "corner":
		var on_outer := outer.dot(normal * side) > 0.0
		rows = 3 if on_outer else 2
		want = CORNER_OUT_PEOPLE if on_outer else CORNER_IN_PEOPLE
	want = mini(want, room)
	var hit := map.road_at(pos.x, pos.y, -INF, 6.0)
	var half := float(hit.half) if not hit.is_empty() else 3.6
	var along_w := 7.0 if kind != "corner" else 6.0
	var out_dir := normal * side
	var placed := []
	if not site.has("hz"): # which slow tests the spots need: once a site, whatever the side (the site dictionary keeps it)
		site["hz"] = hazards_near(map, pos, 8.5 + half + FIRST_ROW + 3.0 * ROW_GAP + 2.0)
	var wet := int(site.hz)
	# along-track offsets, the start's crowd either side of the gantry's posts (never on them)
	var offsets := []
	var a := -along_w * 0.5
	while a <= along_w * 0.5 + 0.01:
		offsets.append(a)
		a += 1.15
	if kind == "start":
		offsets = []
		for x in range(-8, 9):
			if absf(float(x)) >= 1.4:
				offsets.append(float(x) * 1.0)
	for r in rows:
		for off: float in offsets:
			if placed.size() >= want:
				break
			var jx := (_hash(pos.x + off, pos.y + r, 3.1) - 0.5) * 0.4
			var jy := (_hash(pos.x + off, pos.y + r, 4.7) - 0.5) * 0.3
			var lat := half + FIRST_ROW + r * ROW_GAP + jy
			var sp := pos + tang * (off + jx) + out_dir * lat
			if spot_ok(map, sp, ROAD_MARGIN, BUILDING_MARGIN, wet):
				placed.append(sp)
	if placed.is_empty():
		return 0
	var idx := groups.size()
	for sp: Vector2 in placed:
		var face := -out_dir
		var rnd := _hash(sp.x, sp.y, 1.7)
		people.append({"pos": sp, "face": face, "pose": 0 if rnd < 0.28 else (1 if rnd < 0.68 else 2), "y": _ground_y(sp), "site": idx,
			"col": int(_hash(sp.x * 1.37, sp.y * 1.91, 2.9) * 997.0) % FestivalDressing.SHIRT_COLORS.size(),
			"seed": clampf(_hash(sp.x * 1.73, sp.y * 1.29, 8.3), 0.01, 0.99)})
	groups.append({"pos": pos, "tangent": tang, "kind": kind, "people": placed.size(), "side": side})
	# tape in front of the first row, as long as the crowd, kept only where its ends and middle stand clear
	var lo := INF
	var hi := -INF
	for sp: Vector2 in placed:
		var t := (sp - pos).dot(tang)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	var ta := pos + tang * (lo - 0.4) + out_dir * (half + TAPE_OFF)
	var tb := pos + tang * (hi + 0.4) + out_dir * (half + TAPE_OFF)
	if hi - lo >= 1.5 and spot_ok(map, ta, 0.8, 0.2, wet) and spot_ok(map, tb, 0.8, 0.2, wet) and spot_ok(map, ta.lerp(tb, 0.5), 0.8, 0.2, wet):
		tape.append([ta, tb])
	return placed.size()

static func _hash(x: float, y: float, salt: float) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
	return v - floorf(v)

func _spec_mesh(pose: int) -> Array:
	var names := ["SpectatorStand", "SpectatorCheer", "SpectatorWave"]
	if builder and builder.has_model(names[pose]):
		return builder.models[names[pose]]
	return [FestivalDressing._fallback_spectator(), Transform3D.IDENTITY]

func _commit_crowds() -> void:
	var xfs := [[], [], []]
	var cust := [[], [], []]
	for p in people:
		var pose := int(p.pose)
		var face: Vector2 = p.face
		var yaw := atan2(-face.x, -face.y)
		var pos: Vector2 = p.pos
		xfs[pose].append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, float(p.y), pos.y)))
		var c := Color(FestivalDressing.SHIRT_COLORS[int(p.col)]).srgb_to_linear()
		cust[pose].append(Color(c.r, c.g, c.b, float(p.seed)))
	var pose_names := ["Stand", "Cheer", "Wave"]
	for pose in 3:
		if (xfs[pose] as Array).is_empty():
			continue
		var sm := _spec_mesh(pose)
		var local: Transform3D = sm[1]
		var placed := []
		for xf in xfs[pose]:
			placed.append((xf as Transform3D) * local)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.use_custom_data = true
		mm.mesh = sm[0]
		mm.instance_count = placed.size()
		mm.buffer = TownBuilder.instance_buffer(placed, cust[pose])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Spectators" + pose_names[pose]
		mmi.multimesh = mm
		mmi.material_override = _spec_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 2.0
		mmi.visibility_range_end = SPECTATOR_RANGE
		mmi.visibility_range_end_margin = 20.0
		add_child(mmi)
	if not tape.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "BarrierTape"
		mi.mesh = _tape_mesh()
		mi.material_override = _tape_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = SPECTATOR_RANGE
		mi.visibility_range_end_margin = 20.0
		add_child(mi)

## One mesh for every strip: a post every 3 m and a red and white ribbon between them at 0.9..1.05 m.
func _tape_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var red := Color(0.85, 0.08, 0.06)
	var white := Color(0.92, 0.92, 0.9)
	var post := Color(0.9, 0.75, 0.1)
	for seg in tape:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var l := a.distance_to(b)
		var n := maxi(int(ceil(l / 3.0)), 1)
		var pts := []
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			pts.append(Vector3(p.x, _ground_y(p), p.y))
			_world_box(st, pts[i] + Vector3(0, 0.55, 0), Vector3(0.07, 1.1, 0.07), post)
		for i in n:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var pieces := maxi(int(ceil(p0.distance_to(p1) / 0.6)), 1)
			for k in pieces:
				var q0 := p0.lerp(p1, float(k) / pieces)
				var q1 := p0.lerp(p1, float(k + 1) / pieces)
				var col := red if k % 2 == 0 else white
				st.set_color(col)
				st.set_normal(Vector3.UP)
				var y0 := 0.9
				var y1 := 1.05
				for v in [Vector3(q0.x, q0.y + y0, q0.z), Vector3(q1.x, q1.y + y0, q1.z), Vector3(q1.x, q1.y + y1, q1.z),
						Vector3(q0.x, q0.y + y0, q0.z), Vector3(q1.x, q1.y + y1, q1.z), Vector3(q0.x, q0.y + y1, q0.z)]:
					st.add_vertex(v)
	return st.commit()

func _world_box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var corners := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3, Vector3(0, 0, -1)], [5, 4, 7, 6, Vector3(0, 0, 1)], [4, 0, 3, 7, Vector3(-1, 0, 0)],
		[1, 5, 6, 2, Vector3(1, 0, 0)], [3, 2, 6, 7, Vector3(0, 1, 0)]]
	st.set_color(col)
	for f in faces:
		st.set_normal(f[4])
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c + (corners[f[idx]] as Vector3))
