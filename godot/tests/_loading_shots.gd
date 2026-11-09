## Windowed probe: renders the race loader's hero stills (LoadingScreen.HERO) into textures/loading/hero_<key>.png.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_loading_shots.gd -- [out dir]
## Env: ONLY (comma list of track keys), SX / SY (where the car stands in the frame), SIZE ("1920x1080"), HOUR / WEATHER (override the table), A / B / H / FOV (override the camera).
## The stock Seicento sits on the grid at the track's flattering hour, seen low from the front three-quarter with the circuit
## and the field behind it, lit by the race world itself (no HUD, no retro filter). The window stays small in the corner; the
## picture is drawn into a SubViewport of SIZE. Afterwards convert to JPEG: sips -s format jpeg -s formatOptions 82 X.png --out X.jpg
extends SceneTree

## [key, hour, weather, camera ahead of the car (m), sideways (m, + is the car's right), height over the road (m), fov, s of the car, field size]
## Open circuits take a long lens from far back (14 m, 20 degrees: no wide-angle stretch); street circuits, with walls close by, 11 m and 26 degrees.
const SHOTS := [
	["gp", 18.3, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["nordschleife@1500", 17.6, "dry", 14.0, -5.0, 0.6, 20.0, 0.0, 0],
	["monaco", 19.2, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["indy", 17.4, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["lemans", 21.3, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["monza", 17.8, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["silverstone", 18.2, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["spa", 17.2, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["suzuka", 18.6, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["zandvoort", 18.4, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 8],
	["fiat", 17.6, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["tokyo", 21.6, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["bielsko", 17.9, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["krakow", 20.4, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["oswiecim", 18.1, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["wilamowice", 17.7, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["brzeszcze", 18.5, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["pszczyna", 17.5, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["bor", 17.3, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["goliath", 17.9, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["s1_sprint", 19.6, "dry", 11.0, -4.2, 0.55, 26.0, -9.0, 8],
	["maly_bor", 17.0, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 0],
	["kolonia_stawowa", 17.4, "dry", 14.0, -5.0, 0.6, 20.0, -9.0, 0],
	["babudy_gora", 19.5, "wet", 14.0, -5.0, 0.6, 20.0, -9.0, 0],
	["rajsko_wilczkowice", 10.0, "snow", 14.0, -5.0, 0.6, 20.0, -9.0, 0],
	["lipowiec_kobylec", 17.5, "snow", 14.0, -5.0, 0.6, 20.0, -9.0, 0],
]

func _env_f(k: String, d: float) -> float:
	return float(OS.get_environment(k)) if OS.get_environment(k) != "" else d

func _initialize() -> void:
	Brain.use_disk = false
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://textures/loading")
	DirAccess.make_dir_recursive_absolute(out)
	var size := Vector2i(1920, 1080)
	if OS.get_environment("SIZE") != "":
		var p := OS.get_environment("SIZE").split("x")
		size = Vector2i(int(p[0]), int(p[1]))
	await process_frame
	root.size = Vector2i(640, 360)
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(screen.position + screen.size - Vector2i(660, 400))
	var only := OS.get_environment("ONLY").split(",", false)
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var world = load("res://ui/race_world.tscn").instantiate()
	sv.add_child(world)
	await process_frame
	world.apply_graphics(3)
	var shots: Array = SHOTS
	if OS.get_environment("CANDIDATES") != "":
		shots = str_to_var(FileAccess.get_file_as_string(OS.get_environment("CANDIDATES")))
	for shot in shots:
		var tag: String = shot[0] # "key" or "key@s": the car alone at s metres along the lap instead of on the grid
		var key: String = tag.get_slice("@", 0)
		if not only.is_empty() and not only.has(tag):
			continue
		print("building ", tag)
		var rs := RaceSettings.new()
		rs.track = key
		rs.opponents = 0 if tag.contains("@") else int(shot[8])
		rs.laps = 3
		rs.grid = "pole"
		rs.start_hour = _env_f("HOUR", float(shot[1]))
		rs.weather = OS.get_environment("WEATHER") if OS.get_environment("WEATHER") != "" else String(shot[2])
		rs.starting_tyre = "W" if rs.weather in ["wet", "snow", "hail"] else "M"
		var race := Race.new(rs, null, 7)
		var pl: RaceCar = race.player
		var s0 := float(tag.get_slice("@", 1)) if tag.contains("@") else float(shot[7])
		if s0 != pl.s:
			var dd := pl.d
			pl.s = s0
			var pp := race.track.pos(s0, dd)
			pl.x = pp[0]
			pl.y = pp[1]
			pl.heading = race.track.heading(s0)
		world.set_race(race)
		world.camera_mode = 0
		if is_instance_valid(world.racing_line_node):
			world.racing_line_node.visible = false
		world.set_process(false)
		print("built ", key, " car at ", pl.x, ",", pl.y)
		var fov := _env_f("FOV", float(shot[6]))
		var ahead := _env_f("A", float(shot[3]))
		var side := _env_f("B", float(shot[4]))
		var up := _env_f("H", float(shot[5]))
		var sx := _env_f("SX", 0.22)
		var sy := _env_f("SY", -0.1)
		var cam: Camera3D = world.camera
		# which of the four three-quarter views looks most into the light (the sun low over the car's far side makes the
		# paint glow and the tarmac shine); a front view is preferred, a rear one needs to win by a clear margin
		var ahead_sign := 1.0
		var side_sign := 1.0
		for f in 8:
			world._process(1.0 / 60.0)
			await process_frame
		if OS.get_environment("LIGHT") != "off" and is_instance_valid(world.sun):
			var to_sun := Vector2(world.sun.global_transform.basis.z.x, world.sun.global_transform.basis.z.z).normalized()
			var h := Vector2(cos(pl.heading), sin(pl.heading))
			var best := INF
			for a: float in [1.0, -1.0]:
				for b: float in [1.0, -1.0]:
					var look: Vector2 = (-h * a * ahead - Vector2(-h.y, h.x) * b * absf(side)).normalized() # camera to car
					# the least into the light wins (sun behind the camera and to one side models the body); a rear view only when every
					# front view would be backlit
					var score: float = look.dot(to_sun) + (0.0 if a > 0.0 else 0.6)
					if score < best:
						best = score
						ahead_sign = a
						side_sign = b
			print("  sun toward ", to_sun, " -> ahead ", ahead_sign, " side ", side_sign)
		if ahead_sign < 0.0:
			# seen from behind, the rest of the field would stand round the camera: send it home
			for car in race.cars:
				if car != pl:
					car.recovered = true
		ahead *= ahead_sign
		side = absf(side) * side_sign
		var attrs := CameraAttributesPractical.new()
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = absf(ahead) * 1.4 + 14.0
		attrs.dof_blur_far_transition = 55.0
		attrs.dof_blur_near_enabled = true # the tarmac in front of the lens goes soft too: shallow focus, and a lighter JPEG
		attrs.dof_blur_near_distance = maxf(absf(ahead) * 0.7, 1.0)
		attrs.dof_blur_near_transition = absf(ahead) * 0.55
		attrs.dof_blur_amount = 0.07
		cam.attributes = attrs
		cam.fov = fov
		for f in 120:
			world._process(1.0 / 60.0)
			var fwd := Vector3(cos(pl.heading), 0.0, sin(pl.heading))
			var right := Vector3(-fwd.z, 0.0, fwd.x)
			var car_p: Vector3 = world._focus_pos
			var cam_p := car_p + fwd * ahead + right * side
			cam_p.y = car_p.y + up
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.global_position = cam_p
			var aim := car_p + Vector3.UP * 0.62 + fwd * 0.3
			cam.look_at(aim, Vector3.UP)
			# the car stands right of centre (SX of the half width) and above it (SY of the half height), so the type fits on
			# the left and under it, and a crop to 4:3 or 21:9 keeps it
			var half_h := cam_p.distance_to(aim) * tan(deg_to_rad(fov) * 0.5)
			aim -= cam.global_transform.basis.x * half_h * (float(size.x) / size.y) * sx
			aim -= cam.global_transform.basis.y * half_h * sy
			cam.look_at(aim, Vector3.UP)
			cam.fov = fov
			await process_frame
			if f % 40 == 0:
				print("  frame ", f)
		await RenderingServer.frame_post_draw
		var img := sv.get_texture().get_image()
		var path := out.path_join("hero_%s.png" % tag.replace("@", "_at_"))
		img.save_png(path)
		print("saved ", path, " ", img.get_size())
		world.release_race()
		race.dispose()
	quit()
