## TV-camera sightline check (dev tool): drives a car round each TRACKS circuit on the racing line and, for the
## trackside TV director, reports how much of the lap the camera on air has the car hidden behind trees or a
## rise, with the director that ignores them (old) and the one that checks its view (new).
## TRACKS=nordschleife,spa godot --headless --path godot -s tests/_tv_sight_probe.gd
extends SceneTree

func _initialize() -> void:
	for key in OS.get_environment("TRACKS").split(","):
		var world = load("res://ui/race_world.tscn").instantiate()
		root.add_child(world)
		await process_frame
		var rs := RaceSettings.new()
		rs.track = key
		world.set_race(Race.new(rs))
		var tr: Track = world.track
		print("%s: %d cameras, %d trees" % [key, world.tv_cameras.size(), world._occluders.size() / 4])
		var t0 := Time.get_ticks_usec()
		for i in world.tv_cameras.size():
			world._tv_sight(i)
		print("  every camera's view worked out in %d ms" % ((Time.get_ticks_usec() - t0) / 1000))
		for director in ["old", "new"]:
			var idx := -1
			var end := 0.0
			var shot := 0
			var hidden := 0
			var steps := 0
			var cuts := 0
			var by_ground := 0
			var blind_cam := 0
			var heli := 0
			var s := 0.0
			while s < tr.L:
				world._focus_s = s
				var d := tr.sample(tr.RLD, s)
				var p := tr.pos(s, d)
				var pos := Vector3(p[0] - world.world_center.x, world._road_y(s), p[1] - world.world_center.y)
				if director == "new":
					if world._tv_direct(pos, idx < 0):
						cuts += 1
					idx = world._tv_index
				else:
					var cut: bool = idx < 0 or world.tv_cameras[idx].distance_to(pos) > 450.0
					if not cut:
						cut = tr.rel(world.tv_camera_s[idx] - s) < end
					if cut:
						cuts += 1
						idx = _old_pick(world, tr, s, shot)
						shot += 1
						end = world.TV_END_AHEAD[world.tv_camera_kind[idx]]
				if director == "new" and world._tv_heli:
					heli += 1
				elif not world._tv_sees(world.tv_cameras[idx], s):
					hidden += 1
					var keep = world.surroundings
					world.surroundings = null
					if world._tv_sees(world.tv_cameras[idx], s):
						by_ground += 1
					world.surroundings = keep
					var v: Vector2 = world._tv_sight(idx)
					if v.y < v.x:
						blind_cam += 1
					if director == "new" and OS.get_environment("SHOTS") != "" and hidden % 25 == 1:
						print("    hidden: s=%.0f cam %d kind %d ahead %.0f view %s" % [s, idx, world.tv_camera_kind[idx], tr.rel(world.tv_camera_s[idx] - s), v])
				steps += 1
				s += 2.0
			print("  %s director: car hidden %.1f%% of the lap (%.1f%% by the ground alone, %.1f%% on cameras that see nothing), helicopter %.1f%%, %d shots (%.0f m each)" % [
				director, 100.0 * hidden / steps, 100.0 * by_ground / steps, 100.0 * blind_cam / steps, 100.0 * heli / steps, cuts, tr.L / cuts])
		world.queue_free()
		await process_frame
	quit()

## The director before sightlines: the nearest camera of the kind due next far enough ahead, else of any kind.
func _old_pick(world, tr: Track, s: float, shot: int) -> int:
	var want: int = world.TV_SEQUENCE[shot % world.TV_SEQUENCE.size()]
	var best := -1
	var best_ahead := INF
	for pass_kind in 2:
		for i in world.tv_camera_s.size():
			var kind: int = world.tv_camera_kind[i]
			if pass_kind == 0 and kind != want:
				continue
			var ahead_m := fposmod(world.tv_camera_s[i] - s, tr.L)
			if ahead_m >= world.TV_MIN_AHEAD[kind] and ahead_m < best_ahead:
				best_ahead = ahead_m
				best = i
		if best >= 0:
			return best
	return maxi(0, best)
