## The start-light gantry and the event-only spectators (scripts/world/event_dressing.gd) on the real Brzeszcze map, for a
## live street sprint (and every other live kind) and for campaign missions on the map: the gantry spans the road at the
## start (posts outside its edges, centred on its centre line, five columns, none for a drift zone, one per stage for a
## rally); the lights follow the run's countdown frame by frame (one more column every half second, all out at GO);
## every spectator stands off every road by its half width + a margin, outside every building (footprint and drawn
## walls), off water; the total stays under the cap even for a many-stage route; the tape stands clear too; and nothing
## of either remains once the event ends, is abandoned or is restarted (which builds it afresh).
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("data/world/%s.json did not load" % OpenWorld.MAP_KEY)
		completed = true
		return errors
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var home := Vector2(s[0], s[1])
	_timing(errors)
	await _live_kinds(map, home, errors)
	await _missions(map, errors)
	await _cap(map, home, errors)
	await _world(map, home, errors)
	completed = true
	return errors

## A dressing hung in the tree (the instance shader parameters need it), on no builder (its own spectator material).
func _dressing(map: TownMap) -> EventDressing:
	var tree := Engine.get_main_loop() as SceneTree
	var d := EventDressing.new(map, null)
	tree.root.add_child(d)
	return d

func _timing(errors: Array[String]) -> void:
	# one more column every LIGHT_STEP from the first moment of the count, five lit by the last second, all out at GO
	var want := {-3.0: 1, -2.99: 1, -2.51: 1, -2.5: 2, -2.01: 2, -2.0: 3, -1.51: 3, -1.5: 4, -1.01: 4, -1.0: 5, -0.5: 5, -0.001: 5,
		0.0: 0, 0.5: 0}
	for t in want:
		var got := EventDressing.lit_columns("countdown", float(t))
		if got != int(want[t]):
			errors.append("lit_columns(countdown, %.3f) = %d, want %d" % [float(t), got, int(want[t])])
	for st in ["running", "liaison", "done"]:
		if EventDressing.lit_columns(st, -1.5) != 0:
			errors.append("columns lit in the %s state" % st)
	if absf(EventDressing.LIGHT_STEP * (EventDressing.COLUMNS - 1) - (LiveEvents.COUNTDOWN - 1.0)) > 0.001:
		errors.append("the five columns are not all lit by the countdown's last second")

# ------------------------------------------------------------------------------------------------ one event

## The gantry and the crowd of every live kind round the festival, and the lights through the countdown.
func _live_kinds(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 777)
	var crowd_kinds := 0
	var worst_ms := 0.0
	for kind in LiveEvents.KINDS:
		var ev := {}
		for attempt in 4:
			ev = live.generate(home, PackedVector2Array(), kind)
			if not ev.is_empty():
				break
		if ev.is_empty():
			errors.append("no %s could be generated for the dressing" % kind)
			continue
		live.board.append(ev)
		var d := _dressing(map)
		live.begin(ev, "stock")
		d.update(live, 0.0)
		_check_event(map, live, ev, d, String(kind), errors)
		worst_ms = maxf(worst_ms, float(d.stats.get("build_ms", 0.0)))
		print("  %s: %d people in %d groups, %d tape, %d gantries; %.1f ms (gantry %.1f, crowd %.1f)" % [kind, d.people.size(), d.groups.size(),
			d.tape.size(), d.gantries.size(), d.stats.build_ms, d.stats.gantry_ms, d.stats.crowd_ms])
		if d.people.size() > 0:
			crowd_kinds += 1
		if not NO_GANTRY_KINDS.has(String(ev.kind)):
			_countdown(live, ev, d, String(kind), errors)
		# abandoned: nothing of it stays
		live.abandon()
		d.update(live, 0.0)
		_gone(d, "%s abandoned" % kind, errors)
		# a restart is a new run: built again
		live.begin(ev, "stock")
		d.update(live, 0.0)
		if d.people.is_empty() and crowd_kinds > 0 and d.gantries.is_empty():
			errors.append("%s: nothing built again after a restart" % kind)
		live.abandon()
		d.update(live, 0.0)
		_gone(d, "%s abandoned again" % kind, errors)
		d.free()
	if crowd_kinds < 4:
		errors.append("only %d live kinds got spectators" % crowd_kinds)
	print("  event dressing: worst build %.1f ms over the live kinds" % worst_ms)
	await (Engine.get_main_loop() as SceneTree).process_frame

const NO_GANTRY_KINDS := ["drift_zone"]

## Everything the brief asks of one built dressing.
func _check_event(map: TownMap, live: LiveEvents, ev: Dictionary, d: EventDressing, label: String, errors: Array[String]) -> void:
	var stages: int = (ev.stages as Array).size() if String(ev.kind) == "rally" else 1
	var drift := NO_GANTRY_KINDS.has(String(ev.kind))
	if drift:
		if not d.gantries.is_empty():
			errors.append("%s: a gantry at a drift zone (it starts by its gate)" % label)
	elif d.gantries.size() != stages:
		errors.append("%s: %d gantries for %d starts" % [label, d.gantries.size(), stages])
	for g in d.gantries:
		_check_gantry(map, live, g, label, errors)
	var n := d.people.size()
	if n > EventDressing.MAX_SPECTATORS:
		errors.append("%s: %d spectators (cap %d)" % [label, n, EventDressing.MAX_SPECTATORS])
	if n == 0:
		errors.append("%s: no spectators at all" % label)
	var bad_road := 0
	var bad_bld := 0
	var bad_water := 0
	for p in d.people:
		var pos: Vector2 = p.pos
		if not map.road_at(pos.x, pos.y, -INF, EventDressing.ROAD_MARGIN - 0.05).is_empty():
			bad_road += 1
		if _in_or_near_building(map, pos, EventDressing.BUILDING_MARGIN - 0.05):
			bad_bld += 1
		if not is_nan(map.water_at(pos)):
			bad_water += 1
		if not map.in_play(pos):
			bad_water += 1
	if bad_road > 0 or bad_bld > 0 or bad_water > 0:
		errors.append("%s: spectators on a road (%d), in/at a building (%d), in water or off the map (%d) of %d" % [label, bad_road, bad_bld, bad_water, n])
	for seg in d.tape:
		for q in [seg[0], seg[1], (seg[0] as Vector2).lerp(seg[1], 0.5)]:
			if not map.road_at(q.x, q.y, -INF, 0.7).is_empty() or _in_or_near_building(map, q, 0.1):
				errors.append("%s: barrier tape on a road or in a building at %s" % [label, q])
				break
	# crowds at the start and the finish where the verge allows (a street with houses to the kerb may have none)
	var near_start := 0
	var start: Vector2 = live.grid_pose(ev)[0]
	for p in d.people:
		if (p.pos as Vector2).distance_to(start) < 25.0:
			near_start += 1
	if near_start == 0 and not drift:
		print("  (%s: no spectators within 25 m of the start: the verge is built up)" % label)
	if d.stats.get("build_ms", 0.0) > 60.0:
		errors.append("%s: the dressing took %.0f ms to build" % [label, d.stats.build_ms])

func _in_or_near_building(map: TownMap, p: Vector2, margin: float) -> bool:
	for bi in map.buildings_near(p, margin):
		if TownMap.inside(p, map.bld_rings[bi]):
			return true
		var faces := map.building_faces(bi)
		var k := 0
		while k + 5 < faces.size():
			var a := Vector2(faces[k], faces[k + 1])
			var b := Vector2(faces[k + 2], faces[k + 3])
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < margin:
				return true
			k += 6
	return false

func _check_gantry(map: TownMap, live: LiveEvents, g: Dictionary, label: String, errors: Array[String]) -> void:
	var pos: Vector2 = g.pos
	var across: Vector2 = g.across
	var half := float(g.half)
	var hit := map.road_at(pos.x, pos.y, -INF, 0.5)
	if hit.is_empty():
		errors.append("%s: the gantry's centre is not on a road" % label)
		return
	if absf(float(hit.dist)) > 1.2:
		errors.append("%s: the gantry is %.1f m off the road's centre line" % [label, float(hit.dist)])
	var posts: Array = g.posts
	var l: Vector2 = posts[0]
	var r: Vector2 = posts[1]
	# one post each side, both outside the road's own half width there, and across the route's direction
	if (l - pos).dot(across) >= 0.0 or (r - pos).dot(across) <= 0.0:
		errors.append("%s: the gantry's posts are not on opposite sides of the road" % label)
	var span := l.distance_to(r)
	if span < 2.0 * half - 0.01 or span > 2.0 * half + 10.0:
		errors.append("%s: the gantry spans %.1f m for a road %.1f m wide" % [label, span, 2.0 * half])
	for q in [l, r]:
		var h2 := map.road_at(q.x, q.y, -INF, 0.0)
		if not h2.is_empty() and float(h2.road) == float(hit.road):
			errors.append("%s: a gantry post stands on the road it spans" % label)
	if absf((l - pos).dot((g.dir as Vector2))) > 0.2 or absf((r - pos).dot((g.dir as Vector2))) > 0.2:
		errors.append("%s: the gantry is not square across the route" % label)
	var mi := g.node as MeshInstance3D
	var box := mi.mesh.get_aabb()
	if box.size.x < 2.0 * half:
		errors.append("%s: the gantry's beam is %.1f m, the road %.1f m" % [label, box.size.x, 2.0 * half])
	if box.position.y + box.size.y < 5.5 or box.position.y + box.size.y > 8.5:
		errors.append("%s: the gantry is %.1f m high" % [label, box.position.y + box.size.y])
	if mi.mesh.get_surface_count() != 1:
		errors.append("%s: the gantry is %d draw calls" % [label, mi.mesh.get_surface_count()])
	# it stands just past where the player waits on the grid (stage k's start for a rally)
	var pose: Array = live.stage_pose(int(g.stage)) if int(g.stage) >= 0 else live.grid_pose(live.run.ev)
	var ahead := (pos - (pose[0] as Vector2)).dot(Vector2(cos(float(pose[1])), sin(float(pose[1]))))
	if ahead < 3.0 or ahead > 9.0:
		errors.append("%s: the gantry stands %.1f m past the player's grid spot" % [label, ahead])

## The lights through a real countdown, frame by frame, against the run's own state: what the gantry shows after each
## step is lit_columns of the run after that step's tick, and the frame the run says GO is the frame they go out.
func _countdown(live: LiveEvents, ev: Dictionary, d: EventDressing, label: String, errors: Array[String]) -> void:
	live.begin(ev, "stock")
	d.update(live, 0.0)
	var pose: Array = live.grid_pose(ev)
	var p: Vector2 = pose[0]
	var g: Dictionary = d.gantries[0]
	var dt := 1.0 / 60.0
	var frames := 0
	var went := false
	var prev := -1
	var lit_frames := [0, 0, 0, 0, 0, 0]
	while frames < 600:
		frames += 1
		d.update(live, dt)
		var r := live.tick(dt, p, 0.0, 0.0, false, false)
		var shown := int(g.lit)
		var should := EventDressing.lit_columns(String(live.run.state), float(live.run.t))
		if shown != should:
			errors.append("%s: frame %d shows %d columns, the run (%s at %.3f) says %d" % [label, frames, shown, live.run.state, float(live.run.t), should])
			return
		if shown < prev and r != "go":
			errors.append("%s: the columns went back down mid-count (%d -> %d)" % [label, prev, shown])
			return
		prev = shown
		lit_frames[shown] += 1
		if r == "go":
			went = true
			if shown != 0:
				errors.append("%s: GO with %d columns still lit" % [label, shown])
			break
	if not went:
		errors.append("%s: the countdown never reached GO" % label)
		return
	if not is_equal_approx(float(frames) * dt, LiveEvents.COUNTDOWN) and absf(float(frames) * dt - LiveEvents.COUNTDOWN) > 0.05:
		errors.append("%s: GO came after %.2f s, the countdown is %.1f s" % [label, frames * dt, LiveEvents.COUNTDOWN])
	if lit_frames[5] < int(0.9 / dt) or lit_frames[5] > int(1.1 / dt):
		errors.append("%s: all five columns were lit for %.2f s (the last second)" % [label, lit_frames[5] * dt])
	for k in range(1, 5):
		if lit_frames[k] < int(0.4 / dt) or lit_frames[k] > int(0.6 / dt):
			errors.append("%s: %d column(s) were lit for %.2f s (every half second)" % [label, k, lit_frames[k] * dt])
	# after GO the columns stay out
	for i in 30:
		d.update(live, dt)
		live.tick(dt, p, 0.0, 0.0, false, false)
		if int(g.lit) != 0:
			errors.append("%s: columns lit after GO" % label)
			break

## Nothing of an event stands: no node, no record, nothing active.
func _gone(d: EventDressing, label: String, errors: Array[String]) -> void:
	if d.get_child_count() != 0 or not d.people.is_empty() or not d.gantries.is_empty() or not d.tape.is_empty() or d.active():
		errors.append("%s: %d nodes, %d people, %d gantries, %d tape strips remain" % [label, d.get_child_count(), d.people.size(),
			d.gantries.size(), d.tape.size()])

# ------------------------------------------------------------------------------------------------ missions

## Every campaign mission on the map is dressed the same way: a street sprint, a drag, a knockout and the rally.
func _missions(map: TownMap, errors: Array[String]) -> void:
	var worst_ms := 0.0
	var with_crowd := 0
	var live := LiveEvents.new(map, 5)
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		var ev := MapMissions.event(idx)
		if ev.is_empty():
			continue
		var d := _dressing(map)
		live.begin(ev, "stock")
		d.update(live, 0.0)
		var label := "mission %s" % String(Missions.MISSIONS[k].id)
		_check_event(map, live, ev, d, label, errors)
		worst_ms = maxf(worst_ms, float(d.stats.get("build_ms", 0.0)))
		print("  %s (%s): %d people in %d groups, %d gantries; %.1f ms %s" % [label, ev.kind, d.people.size(), d.groups.size(), d.gantries.size(), d.stats.build_ms, d.crowd_parts])
		if d.people.size() > 0:
			with_crowd += 1
		if not NO_GANTRY_KINDS.has(String(ev.kind)) and String(ev.kind) != "rally":
			_countdown(live, ev, d, label, errors)
		live.abandon()
		d.update(live, 0.0)
		_gone(d, "%s abandoned" % label, errors)
		d.free()
	if with_crowd == 0:
		errors.append("no campaign mission got spectators")
	print("  event dressing: worst build %.1f ms over the %d missions" % [worst_ms, Missions.MISSIONS.size()])
	await (Engine.get_main_loop() as SceneTree).process_frame

# ------------------------------------------------------------------------------------------------ cap

## A many-stage route would put thousands on the verges: the cap holds, and every stage still gets a share.
func _cap(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 91)
	var ev := {}
	for kind in ["sprint", "offroad", "rally"]:
		for attempt in 4:
			ev = live.generate(home, PackedVector2Array(), kind)
			if not ev.is_empty() and LiveEvents.path_length(ev.path) > 800.0:
				break
		if not ev.is_empty():
			break
	if ev.is_empty():
		errors.append("no long route for the cap check")
		return
	live.begin(ev, "stock")
	var d := _dressing(map)
	var starts := []
	var path: PackedVector2Array = ev.path
	for k in 8: # eight stages along the same long route
		var i := mini(k * 12, path.size() - 4)
		starts.append({"stage": k, "pos": path[i], "heading": (path[i + 2] - path[i]).angle(), "route": path})
	d._build_crowds(starts)
	if d.people.size() > EventDressing.MAX_SPECTATORS:
		errors.append("eight stages put %d spectators up (cap %d)" % [d.people.size(), EventDressing.MAX_SPECTATORS])
	if d.people.size() < 40:
		errors.append("eight stages put only %d spectators up" % d.people.size())
	d.clear()
	_gone(d, "the cap check", errors)
	d.free()
	await (Engine.get_main_loop() as SceneTree).process_frame

# ------------------------------------------------------------------------------------------------ in the open world

## The hooks in OpenWorld: a live sprint started from the board builds the dressing in the countdown, the lights follow
## it, finishing and abandoning free it, a restart builds it again, and the world keeps nothing of it.
func _world(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var ow := OpenWorld.new()
	ow.size = Vector2(1600, 900)
	tree.root.add_child(ow)
	await tree.process_frame
	ow.map = map
	ow.progress = WorldProgress.new()
	ow.world = Node3D.new()
	ow.add_child(ow.world)
	ow.route_mesh = MeshInstance3D.new()
	ow.world.add_child(ow.route_mesh)
	ow.builder = TownBuilder.new(map, ow.world)
	ow.drive = FreeCar.new(map)
	ow.drive.place(home, 0.0)
	ow.live = LiveEvents.new(map, 4242)
	ow._live_open()
	var sp := {}
	for attempt in 4:
		sp = ow.live.generate(home + Vector2(400.0, 0.0), ow._beacon_points(), "sprint")
		if not sp.is_empty():
			break
	if sp.is_empty():
		errors.append("OpenWorld: no sprint for the dressing flow")
		ow.queue_free()
		return
	ow.live.board.append(sp)
	ow._live_sync()
	if ow.event_dressing != null and ow.event_dressing.active():
		errors.append("OpenWorld: dressing standing before any event")
	ow._begin_live(String(sp.id))
	ow._update_live(0.0)
	var d := ow.event_dressing
	if d == null or d.gantries.size() != 1 or d.people.is_empty():
		errors.append("OpenWorld: starting a live sprint built no gantry or crowd")
		ow.queue_free()
		return
	if d.get_parent() != ow.world:
		errors.append("OpenWorld: the dressing hangs under the wrong node")
	var g: Dictionary = d.gantries[0]
	var seen := {}
	for i in 12: # the countdown in quarter seconds
		ow._update_live(0.25)
		var got := int(g.lit)
		var want := EventDressing.lit_columns(String(ow.live.run.state), float(ow.live.run.t))
		if got != want:
			errors.append("OpenWorld: %d columns at %s %.2f, expected %d" % [got, ow.live.run.state, float(ow.live.run.t), want])
		seen[got] = true
		if not ow.live.holding():
			break
	if not (seen.has(1) or seen.has(2)) or not seen.has(5) or not seen.has(0):
		errors.append("OpenWorld: the countdown showed columns %s (every stage up to five, then out, expected)" % [seen.keys()])
	var built := d.people.size()
	# the result: abandoned from the pause menu
	ow._end_run("EVENT ABANDONED", "")
	if d.active() or d.get_child_count() != 0 or not d.people.is_empty():
		errors.append("OpenWorld: the dressing stands after the event was abandoned")
	ow._update_live(0.1)
	if d.get_child_count() != 0:
		errors.append("OpenWorld: the dressing came back by itself")
	# restart: a fresh build
	ow._begin_live(String(sp.id))
	ow._update_live(0.0)
	if d.gantries.size() != 1 or d.people.size() != built:
		errors.append("OpenWorld: the restart built %d people and %d gantries (was %d)" % [d.people.size(), d.gantries.size(), built])
	# finished: a run through every checkpoint
	var lev := ow.live.find(String(sp.id))
	ow._update_live(3.2)
	var cps: PackedVector2Array = lev.cps
	var quick := LiveEvents.pace_time(lev.path, "stock") * 0.7
	for i in cps.size():
		ow.drive.place(cps[i], 0.0)
		ow._update_live(quick / cps.size())
	if ow.live.is_running():
		errors.append("OpenWorld: the run did not finish")
	if d.active() or d.get_child_count() != 0 or not d.people.is_empty() or not d.gantries.is_empty():
		errors.append("OpenWorld: the dressing stands after the event ended")
	if ow.world.get_node_or_null("EventDressing") != null and ow.world.get_node("EventDressing").get_child_count() != 0:
		errors.append("OpenWorld: nodes of the event stay in the world")
	# a campaign mission on the map
	var begun := -1
	for k in Missions.MISSIONS.size():
		if String(Missions.MISSIONS[k].kind) == "sprint" and ow._begin_mission(Missions.BASE + k):
			begun = k
			break
	if begun >= 0:
		ow._update_live(0.0)
		if d.gantries.size() != 1 or d.people.is_empty():
			errors.append("OpenWorld: the sprint mission built %d gantries and %d people" % [d.gantries.size(), d.people.size()])
		ow._end_run()
		if d.active() or d.get_child_count() != 0:
			errors.append("OpenWorld: the mission's dressing stands after it was abandoned")
	else:
		errors.append("OpenWorld: no sprint mission could be begun on the map")
	ow.queue_free()
	await tree.process_frame
