## Windowed probe (NOT part of the suite; run only with the user's OK): fly a scripted camera along the open world's Wola and
## Rajsko borders, stop at every road-end barrier for screenshots, and log frame times.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_border_walk_probe.gd -- [out dir] [region: wola|rajsko|both] [speed m/s]
## --audio-driver Dummy keeps it silent; --always-on-top keeps the window uncovered (a covered window stops rendering and the
## frame times mean nothing). The probe unpauses the tree every frame, since losing focus pauses a windowed run.
## Output in the out dir (default /tmp/border_walk):
##   <region>_<nnn>_<what>.png   fly-by stills along the outline and one view per barrier (looking out at it, and from the road)
##   border_frames.csv           region,leg,frame,x,y,frame_ms         every frame
##   border_summary.csv          region,frames,p50_ms,p95_ms,p99_ms,one_pct_low_fps,avg_fps,max_ms
## Frame time is measured between successive frame_post_draw signals with vsync off, so a machine at its refresh cap reads the cap.
extends SceneTree

const REGIONS := {
	"wola": {"place": "Wola", "reach": 2200.0},
	"rajsko": {"place": "Rajsko", "reach": 2000.0},
}
const EYE := 3.2 ## m above the ground for the fly-by camera
const INSET := 14.0 ## m inside the outline that the fly-by runs
const STILL_EVERY := 220.0 ## m between fly-by stills

var out := "/tmp/border_walk"
var speed := 22.0
var ow: OpenWorld
var frames_csv: FileAccess
var summary_csv: FileAccess
var shot_n := 0

func _wait(n: int) -> void:
	for k in n:
		paused = false # a window that loses focus pauses the tree; undo it every frame
		await process_frame

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var which: String = args[1] if args.size() > 1 else "both"
	if args.size() > 2:
		speed = float(args[2])
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _wait(1)
	root.size = Vector2i(1600, 900)
	ow = OpenWorld.new()
	root.add_child(ow)
	var t0 := Time.get_ticks_msec()
	await ow.open("industrial_sprint")
	print("OPEN %d ms" % (Time.get_ticks_msec() - t0))
	ow.hud.hide()
	ow.hour = 11.0
	ow.active = false # the probe drives the camera itself
	ow.camera.current = true
	frames_csv = FileAccess.open(out.path_join("border_frames.csv"), FileAccess.WRITE)
	frames_csv.store_line("region,leg,frame,x,y,frame_ms")
	summary_csv = FileAccess.open(out.path_join("border_summary.csv"), FileAccess.WRITE)
	summary_csv.store_line("region,frames,p50_ms,p95_ms,p99_ms,one_pct_low_fps,avg_fps,max_ms")
	for key in REGIONS:
		if which == "both" or which == key:
			await _region(key)
	frames_csv.close()
	summary_csv.close()
	print("DONE ", out)
	quit()

func _place_pos(name: String) -> Vector2:
	for pl in ow.map.places:
		if pl.name == name and String(pl.k).begins_with("place_"):
			return Vector2(float(pl.x), float(pl.y))
	return Vector2.INF

## Edge legs near the place: the outline's own edges clipped to those within reach, as [from, to] pairs.
func _legs(centre: Vector2, reach: float) -> Array:
	var poly := ow.map.play_inset
	var legs := []
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var c := Geometry2D.get_closest_point_to_segment(centre, a, b)
		if c.distance_to(centre) > reach:
			continue
		# keep the part of the edge within reach of the place
		var dir := (b - a).normalized()
		var half := sqrt(maxf(reach * reach - c.distance_squared_to(centre), 0.0))
		var s0 := maxf((c - a).dot(dir) - half, 0.0)
		var s1 := minf((c - a).dot(dir) + half, a.distance_to(b))
		if s1 - s0 > 40.0:
			legs.append([a + dir * s0, a + dir * s1])
	return legs

func _region(key: String) -> void:
	var cfg: Dictionary = REGIONS[key]
	var centre := _place_pos(cfg.place)
	if centre == Vector2.INF:
		push_warning("no place %s" % cfg.place)
		return
	var times := PackedFloat64Array()
	var legs := _legs(centre, cfg.reach)
	print("%s: %d edge legs" % [key, legs.size()])
	var leg_n := 0
	var last_still := -STILL_EVERY
	for leg in legs:
		var a: Vector2 = leg[0]
		var b: Vector2 = leg[1]
		var dir := (b - a).normalized()
		var inward := _inward(a, dir)
		var len := a.distance_to(b)
		var s := 0.0
		var f := 0
		while s < len:
			var p := a + dir * s + inward * INSET
			# look along the edge and out over it
			_aim(p, p + dir * 40.0 - inward * 30.0)
			if s - last_still >= STILL_EVERY or (s == 0.0 and leg_n == 0):
				last_still = s
				times.append_array(await _frame(key, leg_n, f, p))
				_still("%s_%03d_edge" % [key, shot_n])
				f += 1
			var dt := await _frame(key, leg_n, f, p)
			times.append_array(dt)
			f += 1
			s += speed * maxf(dt[0] / 1000.0, 0.001)
		last_still = -STILL_EVERY
		leg_n += 1
	# every barrier in reach: one frame sequence looking out at it, one from 30 m back along the road
	for c in ow.map.closures:
		var cp := Vector2(float(c[0]), float(c[1]))
		if cp.distance_to(centre) > cfg.reach:
			continue
		var h := float(c[2])
		var out_dir := Vector2(cos(h), sin(h))
		var eye := cp - out_dir * 28.0
		_aim(eye, cp + out_dir * 25.0)
		await _wait(12) # let the streamed chunks arrive
		times.append_array(await _frame(key, 100 + shot_n, 0, eye))
		_still("%s_%03d_barrier_%d_%d" % [key, shot_n, int(cp.x), int(cp.y)])
		var eye2 := cp - out_dir * 8.0
		_aim(eye2, cp + out_dir * 25.0)
		await _wait(4)
		times.append_array(await _frame(key, 100 + shot_n, 1, eye2))
		_still("%s_%03d_closeup" % [key, shot_n])
	_summarise(key, times)

func _inward(a: Vector2, dir: Vector2) -> Vector2:
	var n := Vector2(-dir.y, dir.x)
	return n if ow.map.in_play(a + n * (INSET + 4.0)) else -n

func _aim(from: Vector2, to: Vector2) -> void:
	var g := ow.map.ground(from.x, from.y)
	ow.camera.position = Vector3(from.x, g + EYE, from.y)
	ow.camera.look_at(Vector3(to.x, ow.map.ground(to.x, to.y) + 1.5, to.y), Vector3.UP)
	ow.drive.place(from, 0.0) # the car follows so anything keyed to it (minimap, streaming) stays with the camera
	ow.car_visual.position = Vector3(from.x, g, from.y)

## One drawn frame; returns [frame ms] and writes the CSV row.
func _frame(region: String, leg: int, frame: int, p: Vector2) -> PackedFloat64Array:
	paused = false
	var t := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	frames_csv.store_line("%s,%d,%d,%.1f,%.1f,%.3f" % [region, leg, frame, p.x, p.y, ms])
	return PackedFloat64Array([ms])

func _still(label: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(label + ".png"))
	shot_n += 1

func _summarise(region: String, times: PackedFloat64Array) -> void:
	if times.is_empty():
		return
	var s := times.duplicate()
	s.sort()
	var n := s.size()
	var total := 0.0
	for v in s:
		total += v
	var worst_n := maxi(1, n / 100)
	var worst_sum := 0.0
	for i in worst_n:
		worst_sum += s[n - 1 - i]
	var line := "%s,%d,%.3f,%.3f,%.3f,%.1f,%.1f,%.3f" % [region, n, s[n / 2], s[int(n * 0.95)], s[mini(int(n * 0.99), n - 1)],
		1000.0 / (worst_sum / worst_n), 1000.0 / (total / n), s[n - 1]]
	summary_csv.store_line(line)
	print("RESULT ", line)
