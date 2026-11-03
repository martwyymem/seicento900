## Windowed probe: the open world's grass and wheat from the chase camera, with and without vegetation, and the
## frame cost of it. godot --path godot --audio-driver Dummy --always-on-top -s tests/_grass_shots.gd -- [out dir]
extends SceneTree

const SHOTS_ALL := [
	# [name, x, y, heading, hour]
	["meadow_golden", 1500.0, -1200.0, 0.6, 19.4],
	["meadow_noon", 1500.0, -1200.0, 2.4, 13.0],
	["wheat_golden", -1640.0, -60.0, 0.3, 19.0],
	["verge_town", 0.0, 0.0, 1.2, 16.0],
]
const SHOTS := SHOTS_ALL

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/grass_shots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var size := Vector2i(1280, 720)
	var usable := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.end - size - Vector2i(8, 8))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	var veg: Node3D = ow.world.find_child("Vegetation", true, false)
	print("vegetation ", veg != null, " quality ", ow.quality)
	for shot in SHOTS:
		ow.drive.place(Vector2(shot[1], shot[2]), shot[3])
		ow.drive.respawn()
		ow.cam_pos = Vector3(ow.drive.car.x, ow.drive.z + 3.0, ow.drive.car.y)
		ow.active = true
		var frames := 0
		for i in 600:
			ow.hour = shot[4]
			await process_frame
			frames += 1
			if i > 30 and veg.queue.is_empty():
				break
		print("%s: planted in %d frames" % [shot[0], frames])
		var cam := ow.viewport.get_camera_3d()
		print("%s: car %s cam %s, %d cells, %d queued, %s" % [shot[0], Vector2(ow.drive.car.x, ow.drive.car.y), cam.global_position if cam else Vector3.ZERO, veg.cells.size(), veg.queue.size(), veg.counts])
		for pass_name in ["on", "off"]:
			veg.visible = pass_name == "on"
			var prims := 0
			var draws := 0
			var t0 := 0
			for i in 80:
				ow.hour = shot[4]
				await process_frame
				if i == 20:
					t0 = Time.get_ticks_usec()
				if i >= 20:
					prims += ow.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
					draws += ow.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			var ms := (Time.get_ticks_usec() - t0) / 60.0 / 1000.0
			print("%-14s veg %-3s  %.2f ms/frame, %d k primitives, %d draws" % [shot[0], pass_name, ms, prims / 60 / 1000, draws / 60])
			if pass_name == "on":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join(String(shot[0]) + ".png"))
		veg.visible = true
	print("counts ", veg.counts)
	quit()
