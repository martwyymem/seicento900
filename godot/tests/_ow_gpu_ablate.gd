## Windowed probe: open-world frame time with one rendering feature off at a time (GPU cost hunt), vsync off.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_ow_gpu_ablate.gd [-- quality=1 scale=0.67]
extends SceneTree

const SPOTS := ["exit_tychy", "station"]

func _measure(n := 150) -> float:
	for i in 30:
		await process_frame
	var ft := PackedFloat64Array()
	for f in n:
		var t := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		ft.append((Time.get_ticks_usec() - t) / 1000.0)
	ft.sort()
	return ft[ft.size() / 2]

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	root.size = Vector2i(int(args.get("w", "1600")), int(args.get("h", "900")))
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint", {"quality": int(args.get("quality", "1"))})
	ow.viewport.scaling_3d_scale = float(args.get("scale", "1.0"))
	print("viewport ", ow.viewport.size, " scale ", ow.viewport.scaling_3d_scale, " quality ", ow.quality)
	var veg: Node3D = ow.world.find_child("Vegetation", true, false)
	var grass := []
	for c in ow.world.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := c as MultiMeshInstance3D
		var m := mmi.material_override as ShaderMaterial
		if m and m.shader and m.shader.resource_path.contains("grass"):
			grass.append(mmi)
	print("grass MMIs ", grass.size())
	var tests := {
		"scale 0.5": [func(): ow.viewport.scaling_3d_scale *= 0.5, func(): ow.viewport.scaling_3d_scale *= 2.0],
		"no ssao": [func(): ow.env.ssao_enabled = false, func(): ow.env.ssao_enabled = true],
		"no glow": [func(): ow.env.glow_enabled = false, func(): ow.env.glow_enabled = true],
		"no fog": [func(): ow.env.fog_enabled = false, func(): ow.env.fog_enabled = true],
		"no vol fog": [func(): ow.env.volumetric_fog_enabled = false, func(): pass],
		"no shadows": [func(): ow.sun.shadow_enabled = false, func(): ow.sun.shadow_enabled = true],
		"no car refl": [func(): ow.reflections.visible = false, func(): ow.reflections.visible = true],
		"sky static": [func(): ow.env.sky.process_mode = Sky.PROCESS_MODE_QUALITY; ow.set_process(false), func(): ow.set_process(true)],
		"no vegetation": [func(): veg.visible = false, func(): veg.visible = true],
		"no grass": [func(): for g in grass: g.visible = false, func(): for g in grass: g.visible = true],
		"no lamps": [func(): for l in ow.lamp_lights: l.visible = false, func(): for l in ow.lamp_lights: l.visible = true],
		"no aa": [func(): ow.viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED; ow.viewport.msaa_3d = Viewport.MSAA_DISABLED, func(): pass],
	}
	for name in SPOTS:
		var spot: Array = ow.map.spots.get(name, [])
		ow.drive.place(Vector2(spot[0], spot[1]), float(spot[2]))
		ow.drive.respawn()
		ow.active = true
		await _measure()
		var base: float = await _measure()
		var line := "RESULT %s base %.2f ms (draws %d prims %dk) |" % [name, base, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000]
		for k in tests:
			tests[k][0].call()
			var t: float = await _measure()
			tests[k][1].call()
			line += " %s %.2f;" % [k, t]
		print(line)
		print("ENV ssao %s ssr %s ssil %s glow %s vol %s sdfgi %s msaa %d ssaa %d taa %s shadow_mode %d dist %.0f" % [ow.env.ssao_enabled, ow.env.ssr_enabled, ow.env.ssil_enabled, ow.env.glow_enabled, ow.env.volumetric_fog_enabled, ow.env.sdfgi_enabled, ow.viewport.msaa_3d, ow.viewport.screen_space_aa, ow.viewport.use_taa, ow.sun.directional_shadow_mode, ow.sun.directional_shadow_max_distance])
	quit()
