## Probe (headless): where the open world's chase camera puts the car in the frame when the car's velocity and heading
## disagree (scraping along a wall nose-in) and when the camera's spot falls inside a building.
##   godot --headless --path godot -s tests/_camera_wall_probe.gd
extends SceneTree

func _initialize() -> void:
	await process_frame
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.active = false
	var spot: Array = ow.map.spots["industrial_sprint"]
	var base := Vector2(spot[0], spot[1])
	var h := float(spot[2])
	# a building to back the camera into: the nearest one to the spot
	var bi := ow.map.buildings_near(base, 200.0)
	print("buildings near spot: ", bi.size())
	for case in [["straight", 0.0, 20.0], ["scrape 30deg", 30.0, 20.0], ["scrape 60deg", 60.0, 12.0], ["pinned 80deg", 80.0, 4.0]]:
		var car = ow.drive.car
		car.x = base.x
		car.y = base.y
		car.heading = h + deg_to_rad(case[1])
		car.vx = cos(h) * case[2]
		car.vy = sin(h) * case[2]
		car.speed = case[2] * cos(deg_to_rad(case[1]))
		var p := Vector3(base.x, ow.map.ground(base.x, base.y), base.y)
		ow.car_visual.position = p
		ow.cam_vel_dir = Vector2(cos(h), sin(h))
		ow.cam_pos = p - Vector3(cos(h), 0, sin(h)) * 6.0 + Vector3.UP * 2.0
		for i in 180:
			ow._update_camera(1.0 / 60.0)
		var sz := Vector2(root.size)
		var sp := ow.camera.unproject_position(p + Vector3.UP * 0.7)
		var fwd := -ow.camera.global_transform.basis.z
		var cam_yaw := atan2(fwd.z, fwd.x)
		print("%-14s heading-vs-velocity %3.0f deg: camera yaw off heading %5.1f deg, car at %.0f%% of frame width (50 = centre), distance %.1f m" % [case[0], case[1], rad_to_deg(wrapf(cam_yaw - car.heading, -PI, PI)), 100.0 * sp.x / sz.x, Vector2(ow.cam_pos.x - p.x, ow.cam_pos.z - p.z).length()])
	# backed up to a building: find spots where the camera's resting place (6 m behind) is inside a building
	var found := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tries := 0
	while found < 5 and tries < 20000:
		tries += 1
		var q := base + Vector2(rng.randf_range(-400, 400), rng.randf_range(-400, 400))
		var hh := rng.randf_range(-PI, PI)
		var f2 := Vector2(cos(hh), sin(hh))
		if ow.map.inside_building(q) or not ow.map.inside_building(q - f2 * 5.0) or ow.map.inside_building(q - f2 * 2.0):
			continue
		found += 1
		var car = ow.drive.car
		car.x = q.x
		car.y = q.y
		car.heading = hh
		car.vx = 0.0
		car.vy = 0.0
		car.speed = 0.0
		var p := Vector3(q.x, ow.map.ground(q.x, q.y), q.y)
		ow.car_visual.position = p
		ow.cam_vel_dir = f2
		ow.cam_pos = p - Vector3(f2.x, 0, f2.y) * 6.0 + Vector3.UP * 2.0
		var xs := []
		var ds := []
		for i in 120:
			ow._update_camera(1.0 / 60.0)
			if i >= 60:
				var sp := ow.camera.unproject_position(p + Vector3.UP * 0.7)
				xs.append(100.0 * sp.x / root.size.x)
				ds.append(Vector2(ow.cam_pos.x - p.x, ow.cam_pos.z - p.z).length())
		print("backed to a wall #%d: car x in frame %.0f-%.0f%%, camera distance %.1f-%.1f m (frames 60-120)" % [found, xs.min(), xs.max(), ds.min(), ds.max()])
	quit()
