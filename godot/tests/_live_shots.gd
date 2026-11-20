## Windowed probe: the live events and missions on screen (countdown, gates, race HUD, notices, results card, a
## speed zone's start, the pause menu).
##   godot --path godot --audio-driver Dummy --always-on-top --resolution 800x450 --position 920,660 \
##       -s tests/_live_shots.gd -- [out dir] [only,shots]
extends SceneTree

var ow: OpenWorld
var out := ""

func _initialize() -> void:
	# a watchdog: whatever a step does (or fails to do) the probe ends
	create_timer(300.0, true, false, true).timeout.connect(func() -> void:
		print("!! watchdog: probe timed out")
		quit(1))
	await _main()
	quit()

func _fail(what: String) -> void:
	printerr("!! live shots: " + what)

func _main() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/tmp/live_shots"
	var only: PackedStringArray = args[1].split(",") if args.size() > 1 else PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(800, 450)
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open("festival")
	if ow.live == null or not ow.map.spots.has("festival"):
		_fail("open world or its live board is not there")
		return
	ow.hour = 13.0
	var s: Array = ow.map.spots.get("festival")
	var home := Vector2(s[0], s[1])
	var key := CarCatalog.key_at(ow.progress.car_class)
	# a live sprint: the countdown, then a gate with the next and after-next posts
	var sprint := ow.live.generate(home, PackedVector2Array(), "sprint")
	if sprint.is_empty():
		_fail("no sprint generated")
		return
	ow.live.board.append(sprint)
	ow._live_sync()
	ow._begin_live_ev(sprint)
	await _frames(40)
	await _shot("1_sprint_countdown", only)
	ow._update_live(3.2)
	if not ow.live.is_running() or not ow.live.run.has("gates"):
		_fail("the sprint is not running after the countdown")
		return
	var g: Dictionary = ow.live.run.gates[0]
	var d: Vector2 = g.dir
	await _hold((g.pos as Vector2) - d * 32.0, d.angle(), 30)
	await _shot("2_sprint_gate", only)
	# a missed checkpoint
	# run on past the next gate without going through it (put straight there: the gate line is never crossed)
	var tr: PackedVector2Array = ow.live.run.track
	var past := mini(int((float(ow.live.run.cp_s[int(ow.live.run.cp)]) + 70.0) / LiveEvents.TRACK_STEP), tr.size() - 4)
	ow.live.run.s = past * LiveEvents.TRACK_STEP
	ow.live.run.prev = tr[past]
	ow.drive.place(tr[past], (tr[past + 3] - tr[past]).angle())
	ow._update_live(0.02)
	await _hold(tr[past], (tr[past + 3] - tr[past]).angle(), 20)
	await _shot("3_missed_checkpoint", only)
	ow.live.run.notice = ""
	# the pause menu while it runs
	ow._set_paused(true)
	await _frames(10, true)
	await _shot("4_pause_menu", only)
	ow._set_paused(false)
	# through every gate: the results card
	# (the run's clock gets a steady 15 m/s over the route, split between the gates)
	var cps: PackedVector2Array = ow.live.run.cps
	var per_gate := float(sprint.length) / 15.0 / maxf(float(cps.size()), 1.0)
	for i in cps.size():
		if not ow.live.is_running():
			break
		ow.live.run.notice = ""
		ow.drive.place(cps[i], 0.0)
		ow._update_live(per_gate)
	await _hold(Vector2(ow.drive.car.x, ow.drive.car.y), ow.drive.car.heading, 30)
	await _shot("5_results_card", only)
	ow._result = {}
	ow.hud.hide_event()
	# a mission race: the HUD with position, progress and the field
	if Missions.index_of("sprint_s1") >= 0 and ow._begin_mission(Missions.index_of("sprint_s1")):
		ow.hour = 13.0
		ow._update_live(3.2)
		for i in 240:
			ow._update_live(1.0 / 60.0)
			paused = false
			ow.paused = false
			await process_frame
		await _hold(Vector2(ow.drive.car.x, ow.drive.car.y), ow.drive.car.heading, 10)
		await _shot("6_race_hud", only)
		ow._end_run()
	# a live drag (a generated mission): its card, then the four abreast on the grid in the countdown
	var dg := ow.live.generate(home, PackedVector2Array(), "drag")
	if not dg.is_empty():
		ow.live.board.append(dg)
		ow._live_sync()
		var h := float(dg.heading)
		await _hold(dg.pos, h, 30)
		ow._check_events()
		await _shot("7_live_drag_card", only)
		ow._begin_live_ev(dg)
		ow._update_live(0.5)
		var slot: Array = ow.live.grid_pose(dg)
		await _hold(slot[0], float(slot[1]), 30)
		await _shot("8_live_drag_grid", only)
		ow._end_run()

func _frames(n: int, keep_pause := false) -> void:
	for i in n:
		paused = false
		if not keep_pause:
			ow.paused = false # a window that loses focus pauses the open world
		await process_frame

## The car held still at p facing h for n frames (the camera settles behind it).
func _hold(p: Vector2, h: float, n: int) -> void:
	ow.drive.place(p, h)
	ow.snap_camera()
	for i in n:
		ow.drive.place(p, h)
		paused = false
		ow.paused = false
		await process_frame

func _shot(name: String, only: PackedStringArray) -> void:
	if not only.is_empty() and not name in only:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
