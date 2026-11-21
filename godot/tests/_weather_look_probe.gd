## Windowed probe: buildings, trees and roads in the open world under each weather (dry, rain, snow) at one spot, the
## chase camera looking along the street; then the car beside a raised road's side slope (SLOPE, map x,y). Saves shots.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_weather_look_probe.gd -- [out dir]
## Env: SPOT (a map spot, default festival), HOUR (default 13), SLOPE (default "-2580.7,1950.8").
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
	var out: String = args[0] if args.size() > 0 else "/tmp/weather_look"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(960, 540)
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(Vector2i(960, 540))
	DisplayServer.window_set_position(screen.position + screen.size - Vector2i(980, 580))
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open(_env("SPOT", "festival"))
	create_timer(50.0, true, false, true).timeout.connect(func() -> void:
		print("!! 50 s watchdog after load")
		quit(2))
	ow.hud.visible = false
	ow.progress.weather_dynamic = false # the free-roam cycle (WorldWeather) would overwrite the weather set here every frame
	if ow.traffic:
		ow.traffic.clear()
	var hour := float(_env("HOUR", "13"))
	var s: Array = ow.map.spots[_env("SPOT", "festival")]
	var p := Vector2(s[0], s[1])
	var h := float(s[2])
	for mode in ["dry", "rain", "snow"]:
		ow.set_weather(MapMissions.weather_state(mode))
		await _hold(p, h, hour, 40)
		await _shot(out, "weather_" + mode)
	ow.set_weather(MapMissions.weather_state("dry"))
	var sl := _env("SLOPE", "-2580.7,1950.8").split(",")
	var q := Vector2(float(sl[0]), float(sl[1]))
	var road := ow.map.nearest_road(q, 40.0)
	ow.drive.place(q, h)
	ow.drive.respawn()
	var cp := Vector2(ow.drive.car.x, ow.drive.car.y)
	await _hold(cp, ow.drive.car.heading + PI / 2.0, hour, 40) # side on, looking across the slope
	await _shot(out, "slope")

func _hold(p: Vector2, h: float, hour: float, n: int) -> void:
	ow.drive.place(p, h)
	ow.snap_camera()
	for i in n:
		ow.drive.place(p, h)
		ow.hour = hour
		paused = false
		ow.paused = false
		await process_frame

func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
