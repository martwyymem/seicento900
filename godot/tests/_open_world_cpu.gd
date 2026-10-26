## Headless CPU profile of the open world: build time per step, then the main-thread cost of a simulated drive.
##   godot --headless --path godot -s tests/_open_world_cpu.gd
extends SceneTree

func _initialize() -> void:
	await process_frame
	var ow := OpenWorld.new()
	root.add_child(ow)
	var t0 := Time.get_ticks_usec()
	await ow.open("industrial_sprint")
	print("open: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	ow.active = true
	ow.throttle = 1.0
	ow.hour = 21.5
	var parts := {}
	var dt := 1.0 / 60.0
	var n := 600
	var t_all := 0.0
	for i in n:
		ow.throttle = 1.0
		var hit := ow.map.road_at(ow.drive.car.x, ow.drive.car.y)
		ow.steer = clampf(-float(hit.dist) * 0.15, -0.4, 0.4) if not hit.is_empty() else 0.0
		var a := Time.get_ticks_usec()
		_time(parts, "drive", func(): ow.drive.step(1.0 / 120.0, 1.0, 0.0, ow.steer, false, false); ow.drive.step(1.0 / 120.0, 1.0, 0.0, ow.steer, false, false))
		_time(parts, "traffic", func(): ow.traffic.step(1.0 / 120.0, ow.drive); ow.traffic.step(1.0 / 120.0, ow.drive))
		_time(parts, "apply_time", ow._apply_time)
		_time(parts, "sync_car", func(): ow._sync_car(dt))
		_time(parts, "camera", func(): ow._update_camera(dt))
		_time(parts, "skills", func(): ow._update_skills(dt))
		_time(parts, "events", ow._check_events)
		_time(parts, "traps", ow._check_traps)
		_time(parts, "discovery/2", ow._check_discovery)
		_time(parts, "area", ow._check_area)
		_time(parts, "lamps", ow._place_lamp_lights)
		_time(parts, "route_mesh", ow._update_route_mesh)
		_time(parts, "hud", func(): ow.hud.update_drive(ow.drive.speed_kmh(), 1, ow.drive.car.rpm, ow.drive.model.spec.limiter, Vector2(ow.drive.car.x, ow.drive.car.y), ow.drive.car.heading, dt); ow.hud.set_stats(ow.progress.fans, ow.progress.roads.size(), ow.map.road_pts.size(), ow.hour))
		t_all += (Time.get_ticks_usec() - a)
	print("per frame (us, mean over %d frames, each part called every frame):" % n)
	var keys := parts.keys()
	keys.sort_custom(func(x, y): return parts[x] > parts[y])
	for k in keys:
		print("  %-12s %8.1f" % [k, parts[k] / n])
	print("  total        %8.1f" % (t_all / n))
	print("speed %.0f km/h, traffic %d" % [ow.drive.speed_kmh(), ow.traffic.cars.size()])
	quit()

func _time(parts: Dictionary, key: String, f: Callable) -> void:
	var a := Time.get_ticks_usec()
	f.call()
	parts[key] = parts.get(key, 0.0) + (Time.get_ticks_usec() - a)
