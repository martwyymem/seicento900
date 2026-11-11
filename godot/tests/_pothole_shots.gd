## Windowed probe: the potholes (TownMap.pothole, town_road.gdshader). Counts them along the pot-holed streets, then
## parks the car a few metres short of SHOTS of them (default 3) and saves the chase view. Env: OUT, SHOTS, HOUR.
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 --position 2140,1390 -s tests/_pothole_shots.gd
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
	var out := _env("OUT", "/tmp/qa/potholes")
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
	var found := [] # [point, heading]
	var km := 0.0
	var holes := 0
	var home := Vector2(ow.drive.car.x, ow.drive.car.y)
	for ri in map.road_pts.size():
		if map.road_wear(ri) < 1.0:
			continue
		var pts := map.road_pts[ri]
		for i in pts.size() - 1:
			var d := pts[i + 1] - pts[i]
			var l := d.length()
			km += l / 1000.0
			var t := d / maxf(l, 0.01)
			var was := false
			var s := 0.0
			while s < l:
				var q := pts[i] + t * s + Vector2(-t.y, t.x) * 0.62
				var on := map.pothole(q.x, q.y) > 0.03
				if on and not was:
					holes += 1
					if q.distance_to(home) < 4000.0:
						found.append([pts[i] + t * (s - 13.0) - Vector2(-t.y, t.x) * 1.2, t.angle()])
				was = on
				s += 0.25
	print("POTHOLES %d under one wheel track on %.1f km of worn streets (%.1f per km)" % [holes, km, holes / maxf(km, 0.01)])
	var hour := float(_env("HOUR", "14"))
	for k in mini(int(_env("SHOTS", "3")), found.size()):
		var f: Array = found[k * maxi(1, found.size() / 3)]
		ow.drive.place(f[0], f[1])
		ow.drive.respawn()
		ow.snap_camera()
		for i in 60:
			ow.hour = hour
			await _wait(1)
		await RenderingServer.frame_post_draw
		var path := "%s/pothole_%d.png" % [out, k]
		root.get_texture().get_image().save_png(path)
		print("POTHOLES saved %s at %s" % [path, f[0]])
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()
