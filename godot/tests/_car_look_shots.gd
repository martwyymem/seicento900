## Windowed probe: the player's Seicento from chase, rear, front, side and wheel views in the open world.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_car_look_shots.gd -- [out dir]
## Env: ONLY (comma list of "<set>" names: day, dusk, night), PAINT (hex colour, default the game's red), BRAKE (1: brake lights on).
extends SceneTree

const SETS := {
	"day": ["industrial_sprint", 13.0],
	"dusk": ["festival", 19.6],
	"night": ["station", 22.6],
}
## camera offsets in the car's frame: x right, y up, z behind (the car drives towards -z); aim point
const VIEWS := {
	"chase": [Vector3(0, 2.0, 5.2), Vector3(0, 0.9, 0)],
	"rear_close": [Vector3(0.6, 0.95, 3.1), Vector3(0, 0.55, 1.4)],
	"rear34": [Vector3(-2.6, 1.3, 3.8), Vector3(0, 0.6, 0.4)],
	"front34": [Vector3(2.6, 1.2, -4.0), Vector3(0, 0.55, -0.6)],
	"side": [Vector3(4.2, 0.9, 0.0), Vector3(0, 0.6, 0)],
	"wheel": [Vector3(1.9, 0.45, -1.4), Vector3(0.7, 0.3, -1.1)],
	"nose": [Vector3(1.0, 0.8, -3.0), Vector3(0.1, 0.55, -1.7)],
	"exhaust": [Vector3(1.0, 0.45, 2.7), Vector3(0.1, 0.3, 1.6)],
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/car_look"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1600, 900)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	if ow.get("hud") != null:
		ow.hud.visible = false
	if OS.get_environment("PROBE") == "0": # diagnostic: the car's reflection probe off
		for pr in root.find_children("*", "ReflectionProbe", true, false):
			pr.visible = false
	var only := OS.get_environment("ONLY").split(",", false)
	var brake := OS.get_environment("BRAKE") == "1"
	for k in SETS:
		if not only.is_empty() and not only.has(k):
			continue
		var spot: Array = ow.map.spots[SETS[k][0]]
		ow.drive.place(Vector2(spot[0], spot[1]), float(spot[2]))
		ow.drive.respawn()
		ow.hour = SETS[k][1]
		ow.cam_pos = Vector3(ow.drive.car.x, ow.drive.z + 3.0, ow.drive.car.y)
		ow.active = true
		for i in 50:
			ow.hour = SETS[k][1]
			await process_frame
		ow.active = false
		if OS.get_environment("PAINT") != "":
			ow.car_visual.set_paint(Color(OS.get_environment("PAINT")))
		for v in VIEWS:
			var cv: Node3D = ow.car_visual
			var b := cv.global_transform.basis
			# the car's local -Z is forward, so "behind" is +Z in its frame
			var pos: Vector3 = cv.global_position + b * VIEWS[v][0]
			ow.camera.position = pos
			ow.camera.look_at(cv.global_position + b * VIEWS[v][1], Vector3.UP)
			ow.camera.fov = 55.0 if v != "wheel" else 40.0
			for i in 12:
				ow.drive.car.brake_on = brake
				ow.car_visual.sync(ow.drive.car, 0.016, 0.0, ow.night, false)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [k, v]))
			print("saved ", k, "_", v)
	quit()
