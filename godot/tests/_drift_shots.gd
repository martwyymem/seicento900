## Windowed probe (NOT part of the suite; run only with the user's OK): drives the open-world car into a handbrake drift
## with synthetic key presses and saves screenshots of the smoke, skid marks, camera swing, drift meter and the fans
## card's count-up.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_drift_shots.gd -- [out dir]
extends SceneTree

var out := "/tmp/drift_shots"
var ow: OpenWorld

func _wait(n: int) -> void:
	for k in n:
		paused = false
		await process_frame

func _secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		paused = false
		await process_frame

func _key(code: Key, on: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = on
	Input.parse_input_event(e)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	var c := ow.drive.car
	print("%s: %.0f km/h slip %.0f deg  meter pts %d x%.1f  chain %d" % [name, ow.drive.speed_kmh(), rad_to_deg(absf(DriftStyle.slip_angle(c.vx, c.vy, c.heading))),
		ow._drift_view.pending(), ow._drift_view.mult, int(ow.chain_points * ow.chain_mult)])
	print("   cam swing %.2f roll %.3f  cam_dir-heading %.2f  vel-heading %.2f  cam_mode %d" % [ow.drift_cam.swing, ow.drift_cam.roll,
		wrapf(ow.cam_vel_dir.angle() - c.heading, -PI, PI), DriftStyle.slip_angle(c.vx, c.vy, c.heading), ow.cam_mode])
	var f := Vector2(cos(c.heading), sin(c.heading))
	var wd := f.lerp(Vector2(c.vx, c.vy).normalized(), 0.45).normalized().rotated(ow.drift_cam.swing * 0.6)
	print("   want-heading %.2f speed %.1f" % [wrapf(wd.angle() - c.heading, -PI, PI), c.speed])
	var fx: Dictionary = ow.car_visual._fx
	for k in fx:
		var p: GPUParticles3D = fx[k]
		if p.emitting:
			print("   fx %s ratio %.2f" % [k, p.amount_ratio])

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await _wait(1)
	root.size = Vector2i(1600, 900)
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.hour = 12.0
	if ow.story:
		ow.story.process_mode = Node.PROCESS_MODE_DISABLED
		if ow.story.card:
			ow.story.card.hide()
	await _wait(30)
	_key(KEY_W, true)
	await _wait(90)
	await _shot("0_speed")
	# kick the car into a slide (the probe sets the state; the physics carries it on with the keys held)
	var c := ow.drive.car
	var v := maxf(19.0, Vector2(c.vx, c.vy).length())
	var dir := c.heading - 0.6
	c.vx = cos(dir) * v
	c.vy = sin(dir) * v
	c.yaw_rate = 1.0
	_key(KEY_A, true)
	for k in 8:
		await _wait(16)
		var cc := ow.drive.car
		if absf(DriftStyle.slip_angle(cc.vx, cc.vy, cc.heading)) < 0.5 and k < 6: # keep it sideways for the stills
			var vv := maxf(17.0, Vector2(cc.vx, cc.vy).length())
			cc.vx = cos(cc.heading - 0.6) * vv
			cc.vy = sin(cc.heading - 0.6) * vv
		await _shot("1_drift_%d" % k)
	_key(KEY_A, false)
	_key(KEY_W, false)
	await _wait(200)
	await _shot("2_banked")
	ow._add_fans(1234, "SKILL CHAIN")
	await _wait(20)
	await _shot("3_fans")
	await _secs(1.0)
	await _shot("3b_fans")
	await _secs(6.0)
	await _shot("4_after")
	print("DONE ", out)
	quit()
