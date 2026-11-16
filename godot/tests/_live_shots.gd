## Windowed probe: the live events and missions on screen (countdown, gates, race HUD, notices, results card, a
## speed zone's start, the pause menu).
##   godot --path godot --audio-driver Dummy --always-on-top --resolution 800x450 --position 920,660 \
##       -s tests/_live_shots.gd -- [out dir] [only,shots]
extends SceneTree

var ow: OpenWorld
var out := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/tmp/live_shots"
	var only: PackedStringArray = args[1].split(",") if args.size() > 1 else PackedStringArray()
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(800, 450)
	ow = OpenWorld.new()
	root.add_child(ow)
	await ow.open("festival")
	ow.hour = 13.0
	var s: Array = ow.map.spots.get("festival")
	var home := Vector2(s[0], s[1])
	var key := CarCatalog.key_at(ow.progress.car_class)
	# a live sprint: the countdown, then a gate with the next and after-next posts
	var sprint := ow.live.generate(home, PackedVector2Array(), "sprint")
	ow.live.board.append(sprint)
	ow._live_sync()
	ow._begin_live_ev(sprint)
	await _frames(40)
	await _shot("1_sprint_countdown", only)
	ow._update_live(3.2)
	var g: Dictionary = ow.live.run.gates[0]
	var d: Vector2 = g.dir
	await _hold((g.pos as Vector2) - d * 32.0, d.angle(), 30)
	await _shot("2_sprint_gate", only)
	# a missed checkpoint
	# run on past the next gate without going through it (put straight there: the gate line is never crossed)
	var tr: PackedVector2Array = ow.live.run.track
	var past := int((float(ow.live.run.cp_s[int(ow.live.run.cp)]) + 70.0) / LiveEvents.TRACK_STEP)
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
	var cps: PackedVector2Array = ow.live.run.cps
	for i in cps.size():
		ow.drive.place(cps[i], 0.0)
		ow._update_live(float(ow.live.run.tiers[2]) * 0.95 / cps.size())
	await _hold(Vector2(ow.drive.car.x, ow.drive.car.y), ow.drive.car.heading, 30)
	await _shot("5_results_card", only)
	ow._result = {}
	ow.hud.hide_event()
	# a mission race: the HUD with position, progress and the field
	if ow._begin_mission(Missions.index_of("sprint_s1")):
		ow.hour = 13.0
		ow._update_live(3.2)
		var rv := ow.live.rivals()
		for i in 240:
			ow._update_live(1.0 / 60.0)
			paused = false
			ow.paused = false
			await process_frame
		await _hold(Vector2(ow.drive.car.x, ow.drive.car.y), ow.drive.car.heading, 10)
		await _shot("6_race_hud", only)
		ow._end_run()
	# a speed zone's start gate, seen on the run-up
	var sz := ow.live.generate(home, PackedVector2Array(), "speed_zone")
	if not sz.is_empty():
		ow.live.board.append(sz)
		ow._live_sync()
		var h := float(sz.heading)
		await _hold((sz.pos as Vector2) - Vector2.from_angle(h) * 30.0, h, 30)
		await _shot("7_speed_zone_start", only)
		ow._begin_rolling(sz, sz.pos)
		await _hold((sz.pos as Vector2) + Vector2.from_angle(h) * 40.0, h, 30)
		await _shot("8_speed_zone_running", only)
	quit()

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
