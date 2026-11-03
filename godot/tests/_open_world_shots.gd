## Windowed probe: screenshots of the open world of Brzeszcze (it needs a real renderer, so not headless).
##   godot --path godot --audio-driver Dummy -s tests/_open_world_shots.gd -- [out dir]
## Env: ONLY (comma list of shot names), QUALITY (graphics preset 0-3, default High).
## Saves chase-camera views at a few places and hours, and aerial views over the town, with the HUD.
extends SceneTree

const SHOTS := [
	# [name, spot, hour, camera: "chase" | "aerial" | "high", extra metres along the road]
	["dworcowa_day", "industrial_sprint", 13.0, "chase", 0.0],
	["festival_golden", "festival", 19.6, "chase", 0.0],
	["bor_golden", "bor_stage", 19.9, "chase", 0.0],
	["station_night", "station", 22.6, "chase", 0.0],
	["s1_morning", "exit_wilamowice", 7.5, "chase", -260.0],
	["town_aerial", "industrial_sprint", 17.5, "aerial", 0.0],
	["mine_high", "industrial_sprint", 16.0, "high", 0.0],
	["festival_stage", "festival", 20.2, "festival", 0.0],
	# facing the low sun (flare, haze, shafts on Ultra)
	["bor_into_sun", "bor_stage", 19.6, "sun", 0.0],
	["s1_into_sun", "exit_wilamowice", 19.9, "sun", -260.0],
	["town_into_sun", "industrial_sprint", 19.3, "sun", 0.0],
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/open_world_shots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1600, 900)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	if OS.get_environment("QUALITY") != "":
		ow.apply_graphics(int(OS.get_environment("QUALITY")))
	var only := OS.get_environment("ONLY").split(",", false)
	for shot in SHOTS:
		if not only.is_empty() and not only.has(shot[0]):
			continue
		var spot: Array = ow.map.spots[shot[1]]
		var p := Vector2(spot[0], spot[1])
		var h := float(spot[2])
		p += Vector2(cos(h), sin(h)) * float(shot[4])
		if shot[3] == "sun":
			var az := deg_to_rad(lerpf(50.0, 310.0, clampf((float(shot[2]) - 4.75) / 16.0, 0.0, 1.0)))
			h = atan2(-cos(az), sin(az))
		ow.drive.place(p, h)
		ow.drive.respawn()
		ow.hour = shot[2]
		ow.cam_pos = Vector3(ow.drive.car.x, ow.drive.z + 3.0, ow.drive.car.y)
		ow.active = true
		for i in 50:
			ow.hour = shot[2]
			await process_frame
		if shot[3] != "chase" and shot[3] != "sun":
			ow.active = false # stop the camera follow; aim it by hand
			var c := Vector3(ow.drive.car.x, ow.drive.z, ow.drive.car.y)
			if shot[3] == "aerial":
				ow.camera.position = c + Vector3(-260, 230, 320)
			elif shot[3] == "festival":
				c = ow.builder.festival_pos
				ow.camera.position = c + Vector3(-38, 14, -30)
			else:
				ow.camera.position = c + Vector3(120, 70, -90)
			ow.camera.look_at(c + Vector3.UP * 4.0, Vector3.UP)
			ow.camera.fov = 60.0
			for i in 40:
				await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(out.path_join(String(shot[0]) + ".png"))
		print("saved ", shot[0])
	quit()
