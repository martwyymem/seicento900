extends SceneTree
func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var rs := RaceSettings.new()
	rs.track = "indy"
	rs.opponents = 3
	var race := Race.new(rs)
	world.set_race(race)
	for f in 5:
		race.step(1.0 / 60.0, Race.PlayerInput.new())
		await process_frame
	var tr: Track = world.track
	var p = race.player
	var cases := [[900.0, -3.0, 0.5], [930.0, -3.0, 0.5], [960.0, -3.0, 0.5], [990.0, -3.0, 0.5]]
	var k := 0
	for c in cases:
		var pos := tr.pos(c[0], c[1])
		p.s = c[0]; p.d = c[1]; p.x = pos[0]; p.y = pos[1]
		p.heading = tr.heading(c[0]) + c[2]
		p.px = p.x; p.py = p.y; p.ph = p.heading; p.ps = p.s
		p.speed = 0.0; p.vx = 0.0; p.vy = 0.0
		world.camera_snap = true
		for f in 6:
			await process_frame
			world._process(1.0 / 60.0)
		await process_frame
		root.get_texture().get_image().save_png("/tmp/cam_%d.png" % k)
		print("case ", k, " cam y=", world.camera.global_position.y, " car y=", world._focus_pos.y)
		k += 1
	quit()
