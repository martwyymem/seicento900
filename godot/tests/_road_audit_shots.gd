## Windowed probe: views of the open world's streets at given map points (the road audit's worst spots,
## tests/_road_audit_probe.gd). Each spot: "x,y,mode[,heading deg]" with mode "top" (orthographic plan, 50 m across)
## or "eye" (perspective from 14 m back along the heading, 3 m up). Saves <out>/<tag>_<k>.png.
## godot --path godot --audio-driver Dummy --always-on-top -s tests/_road_audit_shots.gd -- <out dir> <tag> "x,y,mode[,hdg];..."
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/road_audit"
	var tag: String = args[1] if args.size() > 1 else "spot"
	var spots: PackedStringArray = (args[2] if args.size() > 2 else "0,0,top").split(";", false)
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var size := Vector2i(960, 600)
	var usable := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.end - size - Vector2i(8, 8))
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("")
	var map: TownMap = ow.map
	var k := 0
	for spot in spots:
		var f := spot.split(",")
		var p := Vector2(float(f[0]), float(f[1]))
		var mode := f[2] if f.size() > 2 else "top"
		var hdg := deg_to_rad(float(f[3])) if f.size() > 3 else 0.0
		var d := Vector2(cos(hdg), sin(hdg))
		# park the car out of the way so the world streams in round the spot
		ow.drive.place(p - d * 40.0, hdg)
		ow.drive.z = ow.drive.support(p.x - d.x * 40.0, p.y - d.y * 40.0)
		ow.active = true
		var cam := Camera3D.new()
		ow.world.add_child(cam)
		var gy := map.ground(p.x, p.y)
		var hit := map.road_at(p.x, p.y)
		if not hit.is_empty():
			gy = float(hit.height)
		if mode == "top":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(f[4]) if f.size() > 4 else 50.0
			cam.global_position = Vector3(p.x, gy + 120.0, p.y)
			cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
			cam.far = 400.0
		else:
			cam.global_position = Vector3(p.x - d.x * 14.0, gy + 3.0, p.y - d.y * 14.0)
			cam.look_at(Vector3(p.x + d.x * 6.0, gy, p.y + d.y * 6.0), Vector3.UP)
		cam.make_current()
		for i in 90:
			paused = false
			ow.hour = 13.0
			cam.make_current()
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out.path_join("%s_%d.png" % [tag, k])
		root.get_texture().get_image().save_png(path)
		print("SHOT %s at %s %s" % [path, p, mode])
		cam.queue_free()
		k += 1
	quit()
