## Windowed probe: a campaign stage started from its open-world beacon through the real game scene; prints the frame
## stats and every SubViewport that still renders, with the visible geometry in each 3D world.
## STAGE (campaign index, default 1 = Brzeszcze). godot --path godot --audio-driver Dummy --always-on-top -s tests/_race_game_perf.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")
var game

func _wait(frames: int) -> void:
	for k in frames:
		game._app_focused = true
		if game.paused:
			game._set_paused(false)
		await process_frame

func _geo(n: Node, acc: Dictionary) -> void:
	if n is Node3D and not (n as Node3D).is_visible_in_tree():
		return
	if n is GeometryInstance3D:
		var w := (n as Node3D).get_world_3d()
		var k := str(w.get_instance_id()) if w else "none"
		acc[k] = int(acc.get(k, 0)) + 1
	for c in n.get_children():
		if c is SubViewport:
			continue
		_geo(c, acc)

func _report(tag: String) -> void:
	await _wait(60)
	var ft := PackedFloat64Array()
	for f in 60:
		game._app_focused = true
		var t := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		ft.append((Time.get_ticks_usec() - t) / 1000.0)
	ft.sort()
	print("== %s: frame %.1f ms  draw %d  objects %d  prims %d  nodes %d" % [tag, ft[ft.size() / 2],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	for vp: SubViewport in root.find_children("*", "SubViewport", true, false):
		var acc := {}
		for c in vp.get_children():
			_geo(c, acc)
		print("  %s  mode %d  own %s  size %s  world %s  geo %s" % [vp.get_path(), vp.render_target_update_mode,
			vp.own_world_3d, vp.size, vp.find_world_3d().get_instance_id() if vp.find_world_3d() else 0, acc])

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	await game._enter_open_world("")
	await _report("open world")
	var stage := int(OS.get_environment("STAGE")) if OS.get_environment("STAGE") != "" else 1
	game._on_world_stage(stage)
	await _wait(240)
	await _report("race")
	var by := {}
	for g: GeometryInstance3D in game.find_children("*", "GeometryInstance3D", true, false):
		if not g.is_visible_in_tree() or g.get_world_3d() != game.render_viewport.find_world_3d():
			continue
		var parts := String(game.render_viewport.get_path_to(g)).split("/")
		var k := "/".join(parts.slice(0, mini(int(OS.get_environment("DEPTH")) if OS.get_environment("DEPTH") != "" else 3, parts.size() - 1)))
		by[k] = int(by.get(k, 0)) + 1
	var ks := by.keys()
	ks.sort_custom(func(a, b): return by[a] > by[b])
	for k in ks.slice(0, 25):
		print("  ", by[k], "  ", k)
	for hide_name in OS.get_environment("HIDE").split(",", false): # e.g. HIDE=RoadBlockages,Canopy: what each costs
		for n in game.find_children(hide_name, "Node3D", true, false):
			n.visible = false
		await _report("race without " + hide_name)
	Guard.restore()
	quit()
