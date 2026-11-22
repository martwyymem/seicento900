## Windowed probe (NOT part of the suite): drives the open-world car down the longest road and saves a still slow and
## one fast, so the speed FOV, the speed blur, the bloom and the rear-view mirror can be seen working on the map.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_view_fx_shots.gd -- [out dir] [hour]
extends SceneTree

const TICK := 1.0 / 120.0
var out := "/tmp/view_fx"
var ow: OpenWorld

func _wait(n: int) -> void:
	for k in n:
		paused = false
		await process_frame

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await _wait(1)
	root.size = Vector2i(1600, 900)
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.hour = float(args[1]) if args.size() > 1 else 12.0
	ow.active = false
	ow.camera.current = true
	GfxFx.speed_blur = true
	GfxFx.speed_fov = true
	GfxFx.rear_mirror = true
	var m := ow.map
	var ri := 0
	for i in m.road_pts.size():
		if m.road_len[i] > m.road_len[ri] and m.road_bridge[i] != 1:
			ri = i
	var path: PackedVector2Array = m.road_pts[ri]
	var fc := ow.drive
	fc.place(path[0], (path[1] - path[0]).angle())
	ow.cam_pos = Vector3(path[0].x, fc.z + 3.0, path[0].y)
	var t := 0.0
	var shot_slow := false
	var frames := 0
	while t < 40.0:
		var want := 40.0 if t < 6.0 else 190.0
		for k in 2:
			var p := Vector2(fc.car.x, fc.car.y)
			var target := _ahead(path, p, 20.0 + fc.car.speed * 0.5)
			var steer := clampf(wrapf((target - p).angle() - fc.car.heading, -PI, PI) * 2.0, -1.0, 1.0)
			var v: float = fc.speed_kmh()
			fc.step(TICK, 1.0 if v < want else 0.0, 0.0 if v < want + 6.0 else 0.5, steer)
			t += TICK
		ow._sync_car(1.0 / 60.0)
		ow._update_camera(1.0 / 60.0)
		await _wait(1)
		frames += 1
		if not shot_slow and t > 5.5:
			shot_slow = true
			await _shot("slow")
		if fc.speed_kmh() > 95.0 and frames % 20 == 0:
			await _shot("fast")
			break
	print("speed %.0f km/h fov %.1f blur %.2f mirror %s" % [fc.speed_kmh(), ow.camera.fov, GfxFx.blur, str(ow.get_children().any(func(c): return c is RearMirror and c.visible))])
	print("DONE ", out)
	quit()

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s.png" % tag))
	print(tag, " km/h ", ow.drive.speed_kmh(), " fov ", ow.camera.fov, " blur ", GfxFx.blur)

func _ahead(path: PackedVector2Array, p: Vector2, dist: float) -> Vector2:
	var best := 0
	var bd := INF
	for i in path.size():
		var d := p.distance_to(path[i])
		if d < bd:
			bd = d
			best = i
	var acc := 0.0
	for i in range(best, path.size() - 1):
		acc += path[i].distance_to(path[i + 1])
		if acc >= dist:
			return path[i + 1]
	return path[path.size() - 1] + (path[path.size() - 1] - path[maxi(path.size() - 2, 0)]) * 10.0
