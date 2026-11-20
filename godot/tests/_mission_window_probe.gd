## Windowed probe: campaign missions on the open-world map, seen and measured. For the S1 sprint and the Kolonia
## Stawowa off-road: the grid, the field after a few seconds with the player at a steady PACE (m/s), rival speeds and
## gaps, a side contact (how far the rival is knocked, how hard the player is pushed). For Rajd Borów: the fog's
## numbers, the stage start in fog, the liaison after SS1 and the SS2 start. Prints numbers, saves shots.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_mission_window_probe.gd -- [out dir]
## Env: ONLY (comma list of mission ids), PACE (default 18).
## The window sits in the bottom-right corner; a 50 s watchdog starts once the world has loaded.
extends SceneTree

var ow: OpenWorld
var out := ""
var pace := 18.0
var frame_ms := PackedFloat32Array()

func _initialize() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("!! load watchdog: probe timed out")
		quit(1))
	await _main()
	quit()

func _main() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/tmp/mission_window"
	DirAccess.make_dir_recursive_absolute(out)
	if OS.get_environment("PACE") != "":
		pace = float(OS.get_environment("PACE"))
	await process_frame
	root.size = Vector2i(960, 540)
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(Vector2i(960, 540))
	DisplayServer.window_set_position(screen.position + screen.size - Vector2i(980, 580))
	FanLevels.dev_unlock = true
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open("festival")
	if ow.live == null:
		print("!! no live board")
		return
	create_timer(50.0, true, false, true).timeout.connect(func() -> void:
		print("!! 50 s watchdog after load: stopping")
		quit(2))
	var only := OS.get_environment("ONLY").split(",", false)
	for id in ["sprint_s1", "offroad_kolonia", "rally_bor"]:
		if not only.is_empty() and not only.has(id):
			continue
		var idx := Missions.index_of(id)
		if idx < 0:
			print("!! %s: no such mission" % id)
			continue
		if not ow._begin_mission(idx):
			print("!! %s: _begin_mission refused" % id)
			continue
		print("\n== %s (hour %.1f, weather %s, fog %.2f, mu %.2f)" % [id, ow.hour, ow.weather, ow.fog, ow.drive.mu])
		if id == "rally_bor":
			await _rally(id)
		else:
			await _race(id)
		ow._end_run()
		ow._after_run()
		await _frames(5)
	var s := Array(frame_ms)
	s.sort()
	if not s.is_empty():
		print("\nframe ms over %d frames: median %.1f, p95 %.1f, worst %.1f" % [s.size(), s[s.size() / 2], s[int(s.size() * 0.95)], s[-1]])

func _race(id: String) -> void:
	var run: Dictionary = ow.live.run
	var tr: PackedVector2Array = run.track
	await _hold(tr[0], (tr[mini(3, tr.size() - 1)] - tr[0]).angle(), 30)
	await _shot(id + "_1_grid")
	ow._update_live(3.2) # through the countdown
	var rv := ow.live.rivals()
	if rv == null:
		print("!! no field")
		return
	print("   field %d rivals" % rv.rivals.size())
	# the player at a steady pace down the route for 8 s, the field racing
	var s := 0.0
	var vmax := 0.0
	var vsum := 0.0
	var n := 0
	var t := 0.0
	while t < 8.0:
		var dt := 1.0 / 60.0
		var t0 := Time.get_ticks_usec()
		s += pace * dt
		var i := mini(int(s / LiveEvents.TRACK_STEP), tr.size() - 2)
		var dir := (tr[i + 1] - tr[i]).normalized()
		ow.drive.place(tr[i], dir.angle())
		ow.drive.car.vx = dir.x * pace
		ow.drive.car.vy = dir.y * pace
		ow._update_live(dt)
		for r in rv.rivals:
			vmax = maxf(vmax, float(r.v))
			vsum += float(r.v)
			n += 1
		paused = false
		ow.paused = false
		await process_frame
		frame_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		t += dt
		if is_equal_approx(snappedf(t, 0.01), 3.0):
			await _shot(id + "_2_field_3s")
	await _shot(id + "_3_field_8s")
	var lead := -INF
	var last := INF
	for r in rv.rivals:
		lead = maxf(lead, float(r.s))
		last = minf(last, float(r.s))
	print("   after 8 s with the player at %.0f km/h (%.0f m): rivals mean %.0f km/h, max %.0f km/h; leader %.0f m, last %.0f m; P%d; %s"
		% [pace * 3.6, s, vsum / maxf(n, 1) * 3.6, vmax * 3.6, lead, last, rv.position(), rv.gap_text()])
	# a side contact: the player put half overlapping the nearest rival
	var best := -1
	var bd := INF
	var me := Vector2(ow.drive.car.x, ow.drive.car.y)
	for k in rv.rivals.size():
		var pose: Array = rv.pose(float(rv.rivals[k].s), float(rv.rivals[k].lat))
		var d := me.distance_to(pose[0])
		if d < bd:
			bd = d
			best = k
	if best >= 0:
		var r: Dictionary = rv.rivals[best]
		var pose: Array = rv.pose(float(r.s), float(r.lat))
		var p: Vector2 = pose[0]
		var dir: Vector2 = pose[1]
		var side := Vector2(-dir.y, dir.x)
		var lat0 := float(r.lat)
		ow.drive.place(p + side * 1.4, dir.angle())
		ow.drive.car.vx = dir.x * float(r.v) - side.x * 4.0 # closing sideways at 4 m/s
		ow.drive.car.vy = dir.y * float(r.v) - side.y * 4.0
		var before := Vector2(ow.drive.car.x, ow.drive.car.y)
		ow._update_rivals(1.0 / 60.0)
		var pushed := Vector2(ow.drive.car.x, ow.drive.car.y).distance_to(before)
		var dv := Vector2(ow.drive.car.vx, ow.drive.car.vy) - dir * float(r.v)
		for f in 30:
			ow._update_live(1.0 / 60.0)
			paused = false
			ow.paused = false
			await process_frame
		print("   contact at 1.4 m, 4 m/s sideways: player pushed %.2f m, left with %.1f m/s across; rival lat %.2f -> %.2f m (0.5 s later)"
			% [pushed, dv.dot(side), lat0, float(r.lat)])
		await _shot(id + "_4_contact")

func _rally(id: String) -> void:
	var env: Environment = ow.find_children("*", "WorldEnvironment", true, false)[0].environment
	ow._apply_time()
	print("   fog: density %.4f (race 0.02), sky affect %.2f, light %s, sun energy %.2f, volumetric %s"
		% [env.fog_density, env.fog_sky_affect, env.fog_light_color, ow.sun.light_energy, env.volumetric_fog_enabled])
	var run: Dictionary = ow.live.run
	var tr: PackedVector2Array = run.track
	await _hold(tr[0], (tr[mini(3, tr.size() - 1)] - tr[0]).angle(), 40)
	await _shot(id + "_1_ss1_start_fog")
	ow._update_live(3.2)
	# 4 s of SS1 at the steady pace, the chase camera in the fog
	var s := 0.0
	for f in 240:
		s += pace / 60.0
		var i := mini(int(s / LiveEvents.TRACK_STEP), tr.size() - 2)
		var dir := (tr[i + 1] - tr[i]).normalized()
		ow.drive.place(tr[i], dir.angle())
		ow.drive.car.vx = dir.x * pace
		ow.drive.car.vy = dir.y * pace
		var t0 := Time.get_ticks_usec()
		ow._update_live(1.0 / 60.0)
		paused = false
		ow.paused = false
		await process_frame
		frame_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	await _shot(id + "_2_ss1_running")
	# through SS1's gates: the stage done, the liaison
	var cps: PackedVector2Array = run.cps
	var stage_len := float(tr.size()) * LiveEvents.TRACK_STEP
	for i in cps.size():
		if String(run.get("state", "")) == "liaison":
			break
		ow.live.run.notice = ""
		var j := mini(int(float(run.cp_s[i]) / LiveEvents.TRACK_STEP), tr.size() - 2)
		ow.drive.place(cps[i], (tr[j + 1] - tr[j]).angle())
		ow._update_live(stage_len / pace / maxf(cps.size(), 1.0))
	print("   after SS1: state %s, stage times %s, place P%d" % [String(run.get("state", "")), run.get("stage_times", []), ow.live.rally_place()])
	await _hold(Vector2(ow.drive.car.x, ow.drive.car.y), ow.drive.car.heading, 30)
	await _shot(id + "_3_liaison")
	# the liaison driven: put at SS2's line
	if String(run.get("state", "")) == "liaison":
		var sp := ow.live.stage_pose(1)
		ow.drive.place(sp[0], float(sp[1]))
		ow._update_live(0.1)
		print("   at SS2's line: state %s, stage %d" % [String(run.get("state", "")), int(run.get("stage", -1))])
		await _hold(sp[0], float(sp[1]), 30)
		await _shot(id + "_4_ss2_start")

func _frames(n: int) -> void:
	for i in n:
		paused = false
		ow.paused = false
		await process_frame

func _hold(p: Vector2, h: float, n: int) -> void:
	ow.drive.place(p, h)
	ow.snap_camera()
	for i in n:
		ow.drive.place(p, h)
		paused = false
		ow.paused = false
		await process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("   saved ", name)
