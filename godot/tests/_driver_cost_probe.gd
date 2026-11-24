## What the driver costs: the one-off Cabin cut, a twelve-car field's animation per frame, and its triangles and surfaces.
## godot --headless --path godot -s tests/_driver_cost_probe.gd
extends SceneTree

const VISUAL := preload("res://scripts/ui/race_car_visual.gd")

func _initialize() -> void:
	await process_frame
	var t0 := Time.get_ticks_usec()
	var first: Node3D = VISUAL.new()
	first.car_key = "golf4"
	root.add_child(first)
	print("first golf (model load, cabin cut, driver parts): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var raw: Mesh = null
	var scene := ResourceLoader.load("res://models/golf4.glb", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var rt := scene.instantiate()
	for mi in rt.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).split(".")[0] == "Cabin":
			raw = (mi as MeshInstance3D).mesh
	t0 = Time.get_ticks_usec()
	var cut: Mesh = VISUAL._without_wheel(raw, CarCatalog.visual("golf4"))
	print("Cabin cut alone (once per car type): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	rt.free()
	var cars: Array = []
	for i in 12:
		var c: Node3D = VISUAL.new()
		c.car_key = CarCatalog.KEYS[i % CarCatalog.KEYS.size()]
		c.position = Vector3(i * 3.0, 0.0, 0.0)
		root.add_child(c)
		cars.append(c)
	var rcs: Array = []
	for i in 12:
		var rc := RaceCar.new()
		rc.control = "free"
		rc.speed = 30.0
		rc.steer = 0.1 * sin(i)
		rcs.append(rc)
	for c in cars:
		c.is_player = false
	var n := 2000
	t0 = Time.get_ticks_usec()
	for f in n:
		for i in 12:
			rcs[i].steer = 0.2 * sin(f * 0.05 + i)
			rcs[i].speed += 0.01 * cos(f * 0.07)
			cars[i]._animate_driver(rcs[i], 1.0 / 60.0, rcs[i].steer)
	var per_frame := (Time.get_ticks_usec() - t0) / float(n)
	print("driver animation, 12 cars: %.0f us per frame (%.3f ms)" % [per_frame, per_frame / 1000.0])
	print("check: car 3 wheel turn %.2f, head yaw %.2f" % [cars[3]._drv_turn, cars[3]._drv_head.rotation.y])
	var tris := 0
	var surfaces := 0
	for mi in [first._drv_body, first._drv_head, first._drv_arms[0], first._drv_arms[1], first._drv_wheel]:
		var m: Mesh = (mi as MeshInstance3D).mesh
		surfaces += m.get_surface_count()
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("per car: %d triangles, %d surfaces; 12 cars: %d triangles, %d draw calls (cut Cabin: %d surfaces)" % [tris, surfaces, tris * 12, surfaces * 12, cut.get_surface_count()])
	print("materials per car: suit + helmet; shared: visor, wheel, 5 meshes")
	quit()
