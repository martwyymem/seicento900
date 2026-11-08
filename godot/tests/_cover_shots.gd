## Windowed probe: renders the open-world loading cover's stills (OpenWorldCover.SHOTS) into textures/loading/.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_cover_shots.gd -- [out dir]
## Env: ONLY (comma list of shot numbers 1-3). Renders the world's own viewport at 1920x1080 (no HUD, no retro
## filter) with the stock red Seicento parked at an angle; the window itself stays small in the corner.
## Afterwards convert to JPEG: sips -s format jpeg -s formatOptions 82 X.png --out X.jpg
extends SceneTree

const SIZE := Vector2i(1920, 1080)
## [file stem, spot (a map spot's name or a map point), hour, what is behind the car: "shaft" | "sun" | "road", metres along the road,
##  camera distance, sideways, height, fov, car yaw off the camera line (rad)]
const SHOTS := [
	["ow_cover_1", Vector2(900, 300), 19.5, "shaft", 0.0, 7.0, -2.4, 0.7, 34.0, -0.75],
	["ow_cover_2", "bor_stage", 19.85, "sun", 0.0, 6.8, -2.2, 0.9, 36.0, -0.7],
	["ow_cover_3", "exit_wilamowice", 20.4, "road", -260.0, 7.0, 2.6, 0.8, 36.0, 0.8],
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://textures/loading")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(640, 360)
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(screen.position + screen.size - Vector2i(660, 400))
	var ow := OpenWorld.new()
	ow.render_size = func(_px: Vector2i) -> Vector2i: return SIZE
	root.add_child(ow)
	await ow.open("industrial_sprint", {"quality": 3})
	ow.apply_graphics(3)
	ow.hud.hide()
	if ow.route_mesh:
		ow.route_mesh.visible = false
	for b in ow.builder.beacon_nodes.values():
		(b as Node3D).visible = false
	var shots: Array = SHOTS
	if OS.get_environment("CANDIDATES") != "":
		shots = str_to_var(FileAccess.get_file_as_string(OS.get_environment("CANDIDATES")))
	if ow.traffic:
		ow.traffic.clear()
	var only := OS.get_environment("ONLY").split(",", false)
	for i in shots.size():
		var shot: Array = shots[i]
		if not only.is_empty() and not only.has(str(i + 1)):
			continue
		# a named spot [x, y, heading], or a map point (Vector2) snapped to its nearest road
		var spot: Array = ow.map.spots[shot[1]] if shot[1] is String else [shot[1].x, shot[1].y, 0.0]
		var p := Vector2(spot[0], spot[1])
		var road_h := float(spot[2])
		p += Vector2(cos(road_h), sin(road_h)) * float(shot[4])
		ow.drive.place(p, road_h)
		ow.drive.respawn()
		p = Vector2(ow.drive.car.x, ow.drive.car.y)
		# the direction the camera looks across the car
		var look := Vector2(cos(road_h), sin(road_h))
		match String(shot[3]):
			"shaft":
				var best := INF
				for pl in ow.map.places:
					if String(pl.k) == "mineshaft" and p.distance_to(Vector2(pl.x, pl.y)) < best:
						best = p.distance_to(Vector2(pl.x, pl.y))
						look = (Vector2(pl.x, pl.y) - p).normalized()
			"sun":
				var az := deg_to_rad(lerpf(50.0, 310.0, clampf((float(shot[2]) - 4.75) / 16.0, 0.0, 1.0)))
				look = Vector2(cos(atan2(-cos(az), sin(az))), sin(atan2(-cos(az), sin(az))))
		print(shot[0], " look ", look, " at ", p)
		var side := Vector2(-look.y, look.x)
		var cam2 := p - look * float(shot[5]) + side * float(shot[6])
		var to_cam := (cam2 - p).normalized()
		ow.drive.car.heading = atan2(to_cam.y, to_cam.x) + float(shot[9])
		ow.hour = shot[2]
		ow.cam_pos = Vector3(p.x, ow.drive.z + 3.0, p.y)
		ow.active = true
		for f in 40:
			ow.hour = shot[2]
			ow.throttle = 0.0
			ow.brake = 1.0
			await process_frame
		ow.active = false # hold the car and aim the camera by hand
		var car3 := Vector3(p.x, ow.drive.z, p.y)
		var cam_y := maxf(ow.map.ground(cam2.x, cam2.y), ow.drive.z) + float(shot[7])
		ow.camera.position = Vector3(cam2.x, cam_y, cam2.y)
		ow.camera.look_at(car3 + Vector3(look.x, 0.0, look.y) * 2.5 + Vector3.UP * 0.75, Vector3.UP)
		ow.camera.fov = float(shot[8])
		for f in 30:
			ow.hour = shot[2]
			await process_frame
		await RenderingServer.frame_post_draw
		var img := ow.viewport.get_texture().get_image()
		var path := out.path_join(String(shot[0]) + ".png")
		img.save_png(path)
		print("saved ", path, " ", img.get_size())
	quit()
