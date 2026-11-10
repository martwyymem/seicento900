## Windowed probe: open-world draw calls and objects by top-level group, visible vs shadow pass (deterministic CPU-cost proxy).
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_ow_draw_census.gd
extends SceneTree

const SPOTS := ["station", "bor_stage", "exit_tychy"]

func _info(vp: Viewport) -> Array:
	for i in 4:
		await process_frame
	return [vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)]

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame
	root.size = Vector2i(1600, 900)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint", {"quality": 1})
	for name in SPOTS:
		var spot: Array = ow.map.spots.get(name, [])
		ow.drive.place(Vector2(spot[0], spot[1]), float(spot[2]))
		ow.drive.respawn()
		ow.active = true
		for i in 30:
			await process_frame
		var base: Array = await _info(ow.viewport)
		var tot := func(): return [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))]
		await _info(ow.viewport)
		var t_on: Array = tot.call()
		ow.reflections.visible = false
		await _info(ow.viewport)
		var t_off: Array = tot.call()
		ow.reflections.visible = true
		print("RESULT %s all viewports draws/objs: car reflections on %s off %s" % [name, t_on, t_off])
		print("RESULT %s total: vis draws %d shadow draws %d | vis objs %d shadow objs %d" % [name, base[0], base[1], base[2], base[3]])
		var groups := []
		for c in ow.world.get_children():
			if c is Node3D:
				groups.append(c)
				for g in c.get_children():
					if g is Node3D and g.get_child_count() > 0:
						groups.append(g)
		var rows := []
		for g in groups:
			if not is_instance_valid(g) or not g.visible:
				continue
			g.visible = false
			var r: Array = await _info(ow.viewport)
			g.visible = true
			var d := [base[0] - r[0], base[1] - r[1]]
			if d[0] + d[1] >= 15:
				rows.append([d[0] + d[1], "%s: vis %d shadow %d" % [g.get_path().get_concatenated_names().get_slice("/", -1) if false else str(ow.world.get_path_to(g)), d[0], d[1]]])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in rows.slice(0, 25):
			print("   ", r[1])
	quit()
