## TV-camera sightline shots (dev tool, needs a window): renders the view from trackside TV cameras towards a
## red marker where a car on the racing line would be, and prints whether _tv_sees thinks it is in view.
## TRACK=nordschleife PAIRS=11:128,11:40 (camera index:metres ahead of it) OUT=/tmp/tv_sight
## godot --path godot -s tests/_tv_sight_shot.gd
extends SceneTree

func _initialize() -> void:
	var env := OS.get_environment
	var key: String = env.call("TRACK") if env.call("TRACK") != "" else "nordschleife"
	var out: String = env.call("OUT") if env.call("OUT") != "" else "/tmp/tv_sight"
	root.size = Vector2i(1280, 720)
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var rs := RaceSettings.new()
	rs.track = key
	world.set_race(Race.new(rs))
	for f in 3:
		await process_frame
	world.set_process(false) # the camera is placed by hand
	var tr: Track = world.track
	if env.call("LIST") != "":
		for n in world.track_root.get_children():
			print("node ", n.name, " ", n.get_child_count())
		for i in world.tv_cameras.size():
			print("cam %d s=%.0f kind=%d eye=%s view=%s" % [i, world.tv_camera_s[i], world.tv_camera_kind[i], world.tv_cameras[i], world._tv_sight(i)])
		var sr: Node = world.track_root.find_child("Surroundings", false, false)
		if sr:
			for n in sr.get_children():
				print("  surroundings/", n.name, " ", n.get_child_count())
	if env.call("HIDE") != "":
		for nm in env.call("HIDE").split(","):
			var n: Node = world.track_root.find_child(nm, true, false)
			if n:
				n.visible = false
				print("hid ", n.get_path())
	var marker := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.9
	ball.height = 1.8
	marker.mesh = ball
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color.RED
	marker.material_override = red
	world.add_child(marker)
	DirAccess.make_dir_recursive_absolute(out)
	if env.call("EVERY") != "":
		# the director's own shots: drive the focus round the lap and save the view every EVERY metres
		world.camera_mode = 3
		var every := float(env.call("EVERY"))
		var next := float(env.call("FROM")) if env.call("FROM") != "" else 0.0
		var s := next - 300.0
		var stop := float(env.call("TO")) if env.call("TO") != "" else tr.L
		while s < stop:
			var d := tr.sample(tr.RLD, s)
			var p := tr.pos(s, d)
			var target := Vector3(p[0] - world.world_center.x, world._road_y(s) + tr.bank_rise(s, d), p[1] - world.world_center.y)
			world._focus_s = tr.wrap_s(s)
			world._focus_pos = target
			world._focus_heading = tr.heading(s)
			world._update_camera(1.0 / 30.0)
			if s >= next:
				marker.global_position = target + Vector3.UP
				for f in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				var path := "%s/%s_s%05d.png" % [out, key, int(s)]
				root.get_texture().get_image().save_png(path)
				print("%s  heli=%s cam=%d" % [path, world._tv_heli, world._tv_index])
				next += every
			s += 1.0
		quit()
		return
	for pair in env.call("PAIRS").split(","):
		var bits: PackedStringArray = pair.split(":")
		var i := int(bits[0])
		var s: float = world.tv_camera_s[i] - float(bits[1])
		var d := tr.sample(tr.RLD, s)
		var p := tr.pos(s, d)
		var target := Vector3(p[0] - world.world_center.x, world._road_y(s) + tr.bank_rise(s, d) + 1.0, p[1] - world.world_center.y)
		marker.global_position = target
		var eye: Vector3 = world.tv_cameras[i]
		world.camera.global_position = eye
		world.camera.look_at(target, Vector3.UP)
		world.camera.fov = clampf(rad_to_deg(2.0 * atan(14.0 / maxf(1.0, eye.distance_to(target)))), 8.0, 60.0)
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/%s_cam%d_ahead%s.png" % [out, key, i, bits[1]]
		root.get_texture().get_image().save_png(path)
		print("%s  sees=%s view=%s" % [path, world._tv_sees(eye, s), world._tv_sight(i)])
	quit()
