## Headless traffic probe: runs the traffic round a few spots with the player parked and prints how natural it
## drives (heading snaps, braking, overlaps between cars, cars stuck, off-road) and runs the two traffic suites.
## godot --headless --path godot -s tests/_traffic_probe.gd
extends SceneTree

func _initialize() -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	var spots := ["industrial_sprint"]
	for k in map.spots:
		if spots.size() < 4 and not spots.has(k):
			spots.append(k)
	for key: String in ["industrial_sprint", "exit_pszczyna", "bor_stage"]:
		_run(map, key)
	for path: String in ["res://tests/test_open_world.gd", "res://tests/test_open_world_layers.gd"]:
		var t: Object = load(path).new()
		var errs: Array = t.run()
		print(path, ": ", "OK" if errs.is_empty() else str(errs.size()) + " errors")
		for e in errs.slice(0, 12):
			print("   ", e)
	quit()

func _run(map: TownMap, key: String) -> void:
	var root := Node3D.new()
	var builder := TownBuilder.new(map, root)
	var tr := Traffic.new(map, root, builder)
	var s: Array = map.spots[key]
	var fc := FreeCar.new(map)
	fc.place(Vector2(s[0], s[1]), float(s[2]))
	var dt := 1.0 / 120.0
	var max_rate := 0.0
	var max_jump := 0.0
	var max_dec := 0.0
	var overlaps := 0
	var off := 0
	var samples := 0
	var v_sum := 0.0
	var stopped_long := {}
	var still := {}
	var braking := 0
	var blinking := 0
	var prev := {}
	var t0 := Time.get_ticks_usec()
	var steps := 120 * 120
	for i in steps:
		tr.step(dt, fc)
		if i < 120 * 10:
			continue
		for c in tr.cars:
			var id: int = (c.node as Node3D).get_instance_id()
			if prev.has(id):
				var pv: Array = prev[id]
				var dh := absf(wrapf(float(c.heading) - float(pv[0]), -PI, PI)) / dt
				if float(c.knock) <= 0.0:
					max_rate = maxf(max_rate, dh)
				max_jump = maxf(max_jump, (c.pos as Vector2).distance_to(pv[1]) - float(c.v) * dt)
			prev[id] = [c.heading, c.pos]
			max_dec = minf(max_dec, float(c.get("acc", 0.0)))
			if float(c.v) < 0.2:
				still[id] = float(still.get(id, 0.0)) + dt
				if float(still[id]) > 25.0:
					var ld: Variant = c.get("lead")
					var why := "lead player" if ld is String else ("lead car v %.1f" % float(ld.v) if ld is Dictionary else "no lead")
					stopped_long[id] = "%s %s line %.1f s %.1f/%.1f wait %.1f next %d bends %s knock %.1f" % [c.pos, why, float(c.get("line", INF)), float(c.s), float(c.len), float(c.get("wait", 0.0)), (c.get("next", []) as Array).size(), str(c.get("bends", [])), float(c.knock)]
			else:
				still[id] = 0.0
		if i % 60 == 0:
			for a in tr.cars.size():
				var ca: Dictionary = tr.cars[a]
				samples += 1
				v_sum += float(ca.v)
				if bool(ca.get("braking", false)):
					braking += 1
				if int(ca.get("blink", 0)) != 0:
					blinking += 1
				var p: Vector2 = ca.pos
				if map.road_at(p.x, p.y, -INF, 2.0).is_empty():
					off += 1
				for b in range(a + 1, tr.cars.size()):
					var dd: Vector2 = (tr.cars[b].pos as Vector2) - p
					var hv := Vector2(cos(float(ca.heading)), sin(float(ca.heading)))
					if absf(dd.dot(hv)) < 3.6 and absf(dd.cross(hv)) < 1.5:
						overlaps += 1
						var cb: Dictionary = tr.cars[b]
						if overlaps < 6: print("   overlap at %s: A road %d s %.1f/%.1f v %.1f knock %.1f lead %s dodge %.1f | B road %d s %.1f/%.1f v %.1f knock %.1f dodge %.1f same edge %s" % [p, int(ca.edge[1]), float(ca.s), float(ca.len), float(ca.v), float(ca.knock), typeof(ca.get("lead")), float(ca.get("dodge_now", 0.0)), int(cb.edge[1]), float(cb.s), float(cb.len), float(cb.v), float(cb.knock), float(cb.get("dodge_now", 0.0)), is_same(ca.edge, cb.edge)])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	print("%s: %d cars, mean %.1f km/h, braking %d%%, signalling %d%%, max yaw %.2f rad/s, max jump %.2f m, max decel %.1f, overlaps %d, off-road %d/%d, stuck>25s %d, %.3f ms/step" % [
		key, tr.cars.size(), v_sum / maxf(samples, 1) * 3.6, 100 * braking / maxi(samples, 1), 100 * blinking / maxi(samples, 1),
		max_rate, max_jump, max_dec, overlaps, off, samples, stopped_long.size(), ms])
	print("   player at ", Vector2(fc.car.x, fc.car.y))
	for id in stopped_long:
		print("   stuck at ", stopped_long[id])
	tr.clear()
	root.free()
