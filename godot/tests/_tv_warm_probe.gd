## Times the TV director's sightline set-up per circuit (dev tool): indexing the occluders, and each camera's view.
## TRACKS=nordschleife,monaco godot --headless --path godot -s tests/_tv_warm_probe.gd
extends SceneTree

func _initialize() -> void:
	for key in OS.get_environment("TRACKS").split(","):
		var world = load("res://ui/race_world.tscn").instantiate()
		root.add_child(world)
		await process_frame
		var rs := RaceSettings.new()
		rs.track = key
		world.set_race(Race.new(rs))
		var frames := 0
		var worst := 0.0
		var total := 0.0
		while world._tv_warm_next < world.tv_cameras.size():
			var t1 := Time.get_ticks_usec()
			world._tv_warm_up()
			var ms := (Time.get_ticks_usec() - t1) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			frames += 1
		var t2 := Time.get_ticks_usec()
		world.camera_mode = 3
		world._tv_index = -1
		world._update_camera(1.0 / 60.0)
		print("%s: warm-up %d frames, %.0f ms total, worst frame %.1f ms; first TV frame after it %.2f ms" % [
			key, frames, total, worst, (Time.get_ticks_usec() - t2) / 1000.0])
		world.queue_free()
		await process_frame
	quit()
