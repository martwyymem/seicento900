## Windowed probe: the streets' dead ends (TownBuilder._street_meshes rounds them off). Counts them and saves the chase
## view of SHOTS of them (default 4), the car 9 m short of the end. Env: OUT, SHOTS.
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 --position 2140,1390 -s tests/_dead_end_shots.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")
var game

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _wait(frames: int) -> void:
	for k in frames:
		if game:
			game._app_focused = true
			if game.paused:
				game._set_paused(false)
		await process_frame

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	var out := _env("OUT", "/tmp/qa/deadends")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_aspect_selected(1)
	game._on_preset_selected(2)
	await _wait(5)
	await game._enter_open_world("")
	await _wait(90)
	var ow: OpenWorld = game.open_world
	var map: TownMap = ow.map
	var n_ends := 0
	var shots := 0
	var home := Vector2(ow.drive.car.x, ow.drive.car.y)
	var ends := []
	for ri in map.road_pts.size():
		var pts := map.road_pts[ri]
		var n := pts.size()
		if n < 2:
			continue
		for e in 2:
			var ei := 0 if e == 0 else n - 1
			var d := (pts[ei] - pts[1 if e == 0 else n - 2]).normalized()
			var b := pts[ei] + d * (map.road_w[ri] * 0.5 + 0.6)
			if map.road_at(b.x, b.y).is_empty() and map.kerb_at(b.x, b.y) == 0.0 and (map.road_z[ri].is_empty() or map.road_z[ri][ei] <= 0.05):
				n_ends += 1
				ends.append([pts[ei] - d * 30.0, d.angle(), pts[ei].distance_to(home), map.road_kind[ri], pts[ei], d])
	ends.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	print("DEADENDS %d street ends rounded off" % n_ends)
	for k in mini(int(_env("SHOTS", "4")), ends.size()):
		var f: Array = ends[k * 3]
		ow.drive.place(f[0], f[1])
		ow.drive.respawn()
		ow.snap_camera()
		var e2: Vector2 = f[4]
		var d2: Vector2 = f[5]
		var cam := Camera3D.new()
		ow.world.add_child(cam)
		var gy: float = map.ground(e2.x, e2.y)
		cam.global_position = Vector3(e2.x - d2.x * 9.0, gy + 4.0, e2.y - d2.y * 9.0)
		cam.look_at(Vector3(e2.x, gy, e2.y), Vector3.UP)
		cam.make_current()
		for i in 60:
			ow.hour = 14.0
			await _wait(1)
		await RenderingServer.frame_post_draw
		var path := "%s/end_%d.png" % [out, k]
		root.get_texture().get_image().save_png(path)
		cam.queue_free()
		print("DEADENDS saved %s (%s)" % [path, f[3]])
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()
