## Windowed probe (NOT part of the suite; run only with the user's OK): a scripted autopilot drives the open-world car over
## and under several bridges in both directions at speed, saves screenshots and records the car's height trace.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_bridge_drive_probe.gd -- [out dir] [km/h] [max bridges]
## --audio-driver Dummy keeps it silent; --always-on-top keeps the window uncovered (a covered window stops rendering). The
## probe unpauses the tree every frame, since losing focus pauses a windowed run. OpenWorld is left inactive and the probe steps
## FreeCar itself (like tests/test_open_world_bridges.gd) with a pure-pursuit autopilot, then syncs the car and chase camera.
## Output in the out dir (default /tmp/bridge_drive):
##   bridge_<road>_<fwd|rev>_<on|under>_<k>.png   stills on approach, at the deck's middle and on exit
##   height_trace.csv    run,road,name,dir,layer,t,s_along,x,y,car_z,ground,deck,support,speed_kmh,airborne
##   bridge_summary.csv  run,road,name,dir,layer,max_step_m,max_above_support_m,min_clear_to_deck_m,hit_count,verdict
## "layer" is "on" when the autopilot follows the bridge road itself, "under" when it follows a street that passes beneath
## the deck. A verdict of JUMP means the height changed more than MAX_STEP in one 1/60 s tick; STUCK means the car made no
## progress; HIT means a collision was logged on the way.
extends SceneTree

const TICK := 1.0 / 120.0
const MAX_STEP := 0.35 ## m of car height per 1/60 s before it counts as a jump
const MIN_BRIDGE_DECK := 2.0 ## m above the ground: skip culvert-sized "bridges"
const LEAD := 90.0 ## m driven before the bridge
const AFTER := 60.0 ## m driven past it

var out := "/tmp/bridge_drive"
var kmh := 60.0
var max_bridges := 8
var ow: OpenWorld
var trace: FileAccess
var summary: FileAccess
var run_n := 0

func _wait(n: int) -> void:
	for k in n:
		paused = false
		await process_frame

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		kmh = float(args[1])
	if args.size() > 2:
		max_bridges = int(args[2])
	DirAccess.make_dir_recursive_absolute(out)
	await _wait(1)
	root.size = Vector2i(1600, 900)
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.hud.hide()
	ow.hour = 12.0
	ow.active = false
	ow.camera.current = true
	trace = FileAccess.open(out.path_join("height_trace.csv"), FileAccess.WRITE)
	trace.store_line("run,road,name,dir,layer,t,s_along,x,y,car_z,ground,deck,support,speed_kmh,airborne")
	summary = FileAccess.open(out.path_join("bridge_summary.csv"), FileAccess.WRITE)
	summary.store_line("run,road,name,dir,layer,max_step_m,max_above_support_m,min_clear_to_deck_m,hit_count,verdict")
	var picks := _pick_bridges()
	print("driving %d bridges at %.0f km/h" % [picks.size(), kmh])
	for ri in picks:
		for reverse in [false, true]:
			await _run(ri, reverse, "on", ow.map.road_pts[ri])
			var under := _street_under(ri)
			if not under.is_empty():
				await _run(ri, reverse, "under", under)
	trace.close()
	summary.close()
	print("DONE ", out)
	quit()

## Bridges spread over the map: the longest of each distinct name, deck at least MIN_BRIDGE_DECK above the ground.
func _pick_bridges() -> Array:
	var m := ow.map
	var cands := []
	for ri in m.road_pts.size():
		if m.road_bridge[ri] != 1 or m.road_z[ri].is_empty() or m.road_len[ri] < 40.0:
			continue
		var peak := 0.0
		for z in m.road_z[ri]:
			peak = maxf(peak, z)
		if peak >= MIN_BRIDGE_DECK:
			cands.append(ri)
	cands.sort_custom(func(a: int, b: int) -> bool: return m.road_len[a] > m.road_len[b])
	var picks := []
	var spots := []
	for ri in cands:
		var mid: Vector2 = m.along(ri, m.road_len[ri] * 0.5)[0]
		var near := false
		for s in spots:
			if mid.distance_to(s) < 400.0:
				near = true
		if near:
			continue
		spots.append(mid)
		picks.append(ri)
		if picks.size() >= max_bridges:
			break
	return picks

## A street that crosses beneath the bridge's middle, as a path through the crossing (empty if there is none).
func _street_under(ri: int) -> PackedVector2Array:
	var m := ow.map
	var mid: Array = m.along(ri, m.road_len[ri] * 0.5)
	var p: Vector2 = mid[0]
	var best := -1
	var best_d := 40.0
	for rj in m.road_pts.size():
		if rj == ri or m.road_bridge[rj] == 1 or not m.road_z[rj].is_empty():
			continue
		var pts := m.road_pts[rj]
		for i in pts.size() - 1:
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]))
			if d < best_d:
				best_d = d
				best = rj
	return m.road_pts[best] if best >= 0 else PackedVector2Array()

## Cumulative distance along a path to its point closest to p.
func _s_at(path: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	var s_best := 0.0
	var acc := 0.0
	for i in path.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])
		if p.distance_to(c) < best:
			best = p.distance_to(c)
			s_best = acc + path[i].distance_to(c)
		acc += path[i].distance_to(path[i + 1])
	return s_best

func _point_at(path: PackedVector2Array, s: float) -> Vector2:
	var acc := 0.0
	for i in path.size() - 1:
		var l := path[i].distance_to(path[i + 1])
		if acc + l >= s:
			return path[i].lerp(path[i + 1], (s - acc) / maxf(l, 0.001))
		acc += l
	return path[path.size() - 1]

func _length(path: PackedVector2Array) -> float:
	var l := 0.0
	for i in path.size() - 1:
		l += path[i].distance_to(path[i + 1])
	return l

func _run(ri: int, reverse: bool, layer: String, path_in: PackedVector2Array) -> void:
	var m := ow.map
	var path := path_in.duplicate()
	if reverse:
		path.reverse()
	var total := _length(path)
	var mid: Vector2 = m.along(ri, m.road_len[ri] * 0.5)[0]
	var s_mid := _s_at(path, mid)
	var s0 := maxf(s_mid - maxf(LEAD, 0.0), 0.0)
	var s_end := minf(s_mid + AFTER + m.road_len[ri] * 0.5, total)
	var start := _point_at(path, s0)
	var ahead := _point_at(path, s0 + 5.0)
	var fc := ow.drive
	fc.place(start, (ahead - start).angle())
	if layer == "on": # a bridge road sits on its deck; a street beneath stays on the ground
		var near_start: Dictionary = m.nearest_road(start, 80.0, 1)
		if not near_start.is_empty():
			fc.z = m.ground(start.x, start.y) + m.deck_at(int(near_start.road), int(near_start.i), float(near_start.t))
	fc.car.vx = cos(fc.car.heading) * kmh / 3.6
	fc.car.vy = sin(fc.car.heading) * kmh / 3.6
	fc.car.gear = 2
	fc.hits.clear()
	ow.cam_pos = Vector3(start.x, fc.z + 3.0, start.y)
	run_n += 1
	var tag := "bridge_%d_%s_%s" % [ri, "rev" if reverse else "fwd", layer]
	var dirname := "rev" if reverse else "fwd"
	var t := 0.0
	var last_z := fc.z
	var max_step := 0.0
	var max_above := 0.0
	var min_clear := INF
	var hits := 0
	var s_car := s0
	var still_t := 0.0
	var verdict := "ok"
	var shots := {25: false, 50: false, 75: false}
	while s_car < s_end - 1.0 and t < (total / (kmh / 3.6)) + 30.0:
		paused = false
		# several fixed ticks per rendered frame at the real frame time
		var frame_dt := 1.0 / 60.0 # fixed: the trace must not depend on the machine's frame rate
		var n := int(round(frame_dt / TICK))
		for k in n:
			var p := Vector2(fc.car.x, fc.car.y)
			s_car = _s_at(path, p)
			var target := _point_at(path, s_car + 14.0 + kmh * 0.12)
			var steer := clampf(wrapf((target - p).angle() - fc.car.heading, -PI, PI) * 2.0, -1.0, 1.0)
			var v: float = fc.car.speed * 3.6
			var thr := 1.0 if v < kmh else 0.0
			var brk := 0.0 if v < kmh + 6.0 else 0.4
			var z_before := fc.z
			fc.step(TICK, thr, brk, steer)
			t += TICK
			max_step = maxf(max_step, absf(fc.z - z_before) * (1.0 / 60.0 / TICK))
		hits += fc.hits.size()
		fc.hits.clear()
		var p2 := Vector2(fc.car.x, fc.car.y)
		var g := m.ground(p2.x, p2.y)
		var support := fc.support(p2.x, p2.y)
		var deck_here := 0.0
		var near: Dictionary = m.nearest_road(p2, 12.0, 1)
		if layer == "on" and not near.is_empty() and int(near.road) == ri:
			deck_here = m.deck_at(ri, int(near.i), float(near.t))
		max_above = maxf(max_above, fc.z - support)
		if layer == "under":
			var over := _deck_over(p2, ri)
			if over > 0.0:
				min_clear = minf(min_clear, g + over - fc.z) # headroom between the car's contact and the deck above
		trace.store_line("%d,%d,%s,%s,%s,%.3f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.3f,%.1f,%d" % [run_n, ri, m.road_name[ri].replace(",", " "), dirname,
			layer, t, s_car, p2.x, p2.y, fc.z, g, deck_here, support, fc.speed_kmh(), 1 if fc.airborne else 0])
		if absf(fc.z - last_z) > MAX_STEP:
			verdict = "JUMP"
		last_z = fc.z
		still_t = 0.0 if fc.speed_kmh() > 5.0 else still_t + frame_dt
		if still_t > 4.0:
			verdict = "STUCK" if verdict == "ok" else verdict
			break
		ow._sync_car(frame_dt)
		ow._update_camera(frame_dt)
		await process_frame
		var frac := (s_car - s0) / maxf(s_end - s0, 1.0)
		for key in shots:
			if not shots[key] and frac * 100.0 >= key:
				shots[key] = true
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join("%s_%d.png" % [tag, key]))
	if hits > 0 and verdict == "ok":
		verdict = "HIT"
	summary.store_line("%d,%d,%s,%s,%s,%.3f,%.3f,%.3f,%d,%s" % [run_n, ri, m.road_name[ri].replace(",", " "), dirname, layer, max_step,
		max_above, min_clear if min_clear < INF else -1.0, hits, verdict])
	print("%-30s %-5s max step %.2f m  clear %.2f m  hits %d" % [tag, verdict, max_step, min_clear if min_clear < INF else -1.0, hits])

## Height of the bridge deck above the ground over this point, 0 if the bridge is not overhead.
func _deck_over(p: Vector2, ri: int) -> float:
	for e in ow.map.decks_at(p.x, p.y, 0.0):
		if int(e[0]) == ri:
			return float(e[1])
	return 0.0
