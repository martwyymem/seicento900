## Windowed probe: the Seicento model with its decals from door, front, rear and bonnet views.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_car_decal_shots.gd -- [out dir]
extends SceneTree

func _wait(n: int) -> void:
	for k in n:
		paused = false
		await process_frame

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/car_decals"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1200, 800)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#8a9099")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var car: Node3D = load("res://scripts/ui/race_car_visual.gd").new()
	car.car_number = 7
	root.add_child(car)
	car.set_paint(Color("#4aa0d8"))
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var views := {
		"door": [Vector3(2.6, 1.0, -0.02), Vector3(0, 0.65, -0.02)],
		"sill": [Vector3(1.8, 0.5, 0.25), Vector3(0, 0.38, 0.25)],
		"hood": [Vector3(0, 2.0, 1.0), Vector3(0, 0.8, -1.2)],
		"front": [Vector3(1.8, 1.1, -3.0), Vector3(0, 0.75, -1.0)],
		"rear": [Vector3(-2.0, 1.2, 3.8), Vector3(0, 0.8, 1.2)],
		"sun": [Vector3(0, 1.9, -2.4), Vector3(0, 1.2, -0.2)]}
	for k in views:
		cam.look_at_from_position(views[k][0], views[k][1])
		await _wait(6)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "/" + k + ".png")
	quit()
