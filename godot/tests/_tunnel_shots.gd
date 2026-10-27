## Windowed probe: chase views of the underpasses and bridges.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_tunnel_shots.gd -- [out dir]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/tunnel_shots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1280, 720)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	var shots := []
	for k in [11, 9, 2, 6]:
		var t: Dictionary = ow.map.tunnels[k]
		shots.append(["tunnel%d_approach" % k, t.c - t.v * 34.0, t.v.angle(), 20.5])
		shots.append(["tunnel%d_inside" % k, t.c - t.v * 4.0, t.v.angle(), 20.5])
	shots.append(["bridge_s1_under", Vector2(-1456, 1440) - Vector2(30, 0), 0.0, 14.0])
	shots.append(["bridge_s1_chase", Vector2(-1456, 1440), 1.2, 14.0])
	for shot in shots:
		ow.drive.place(shot[1], shot[2])
		ow.drive.respawn()
		ow.drive.place(shot[1], shot[2])
		ow.hour = shot[3]
		ow.cam_pos = Vector3(shot[1].x, ow.drive.z + 3.0, shot[1].y)
		ow.active = true
		for i in 40:
			ow.hour = shot[3]
			ow.drive.place(shot[1], shot[2])
			ow.get_tree().root.get_window().mode = Window.MODE_WINDOWED
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(String(shot[0]) + ".png"))
		print("saved ", shot[0], " z ", ow.drive.z)
	quit()
