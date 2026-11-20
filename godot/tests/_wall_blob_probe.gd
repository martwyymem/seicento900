## Windowed probe: the white blob on a Rajsko wall at night (TASKS.md "Lamp blob on a Rajsko wall"). Parks the car on
## the road DIST m (default 4) from building walls near PLACE (default Rajsko) at HOUR (default 22.5), facing the wall
## through the chase camera, and shoots each spot four ways: all lights, headlights off, street lamps off, both off.
## Prints the share of near-white pixels (luma > 0.85) and the mean luma of the frame's middle third per variant.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_wall_blob_probe.gd -- [out dir]
extends SceneTree

var ow: OpenWorld

func _initialize() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("!! watchdog")
		quit(1))
	await _main()
	quit()

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _main() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/wall_blob"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(960, 540)
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(Vector2i(960, 540))
	DisplayServer.window_set_position(screen.position + screen.size - Vector2i(980, 580))
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open("festival")
	create_timer(50.0, true, false, true).timeout.connect(func() -> void:
		print("!! 50 s watchdog after load")
		quit(2))
	if ow.traffic:
		ow.traffic.clear()
	ow.hud.visible = false
	var hour := float(_env("HOUR", "22.5"))
	var dist := float(_env("DIST", "4"))
	var centre := Vector2.ZERO
	for pl in ow.map.places:
		if String(pl.get("name", "")) == _env("PLACE", "Rajsko"):
			centre = Vector2(pl.x, pl.y)
	if centre == Vector2.ZERO:
		print("!! place not found")
		return
	var spots := _spots(centre, dist, 4)
	print("%d spots near %s, %.0f m from a wall, hour %.1f" % [spots.size(), _env("PLACE", "Rajsko"), dist, hour])
	for k in spots.size():
		var p: Vector2 = spots[k][0]
		var h: float = spots[k][1]
		ow.drive.place(p, h)
		ow.snap_camera()
		ow.hour = hour
		ow.set_process(true)
		for f in 40:
			ow.drive.place(p, h)
			ow.hour = hour
			paused = false
			ow.paused = false
			await process_frame
		ow.set_process(false) # the lights stay as set below
		var line := "spot %d (%.0f, %.0f):" % [k, p.x, p.y]
		for v in [["all", true, true], ["no_head", false, true], ["no_lamps", true, false], ["none", false, false]]:
			for hl in ow.headlights:
				hl.visible = bool(v[1])
			for l in ow.lamp_lights:
				if not bool(v[2]):
					l.visible = false
			if bool(v[2]):
				ow._place_lamp_lights()
			for f in 4:
				paused = false
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png(out.path_join("spot%d_%s.png" % [k, v[0]]))
			line += "  %s white %.2f%% mid %.3f" % [v[0], _white(img) * 100.0, _mid(img)]
		print(line)
	ow.set_process(true)

## Road points DIST m off a building wall, facing it: [pos, heading].
func _spots(centre: Vector2, dist: float, want: int) -> Array:
	var outl := []
	for bi in ow.map.buildings_near(centre, 350.0):
		var ring: PackedVector2Array = ow.map.bld_rings[bi]
		if ring.size() < 3:
			continue
		var c := Vector2.ZERO
		for q in ring:
			c += q
		c /= ring.size()
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			if a.distance_to(b) < 8.0:
				continue
			var m := (a + b) * 0.5
			var n := Vector2(-(b - a).y, (b - a).x).normalized()
			if n.dot(m - c) < 0.0:
				n = -n
			var q := m + n * dist
			if ow.map.road_at(q.x, q.y, -INF, 0.5).is_empty():
				continue
			var ok := true
			for o in outl:
				if (o[0] as Vector2).distance_to(q) < 120.0:
					ok = false
			if ok:
				outl.append([q, (-n).angle()])
			if outl.size() >= want:
				return outl
	return outl

func _white(img: Image) -> float:
	var n := 0
	var w := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			n += 1
			if img.get_pixel(x, y).get_luminance() > 0.85:
				w += 1
	return float(w) / maxf(n, 1)

func _mid(img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(img.get_height() / 3, img.get_height() * 2 / 3, 3):
		for x in range(img.get_width() / 3, img.get_width() * 2 / 3, 3):
			s += img.get_pixel(x, y).get_luminance()
			n += 1
	return s / maxf(n, 1)
