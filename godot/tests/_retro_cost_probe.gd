## Windowed probe: GPU cost of the retro post-process per style at a full-screen size, over a busy image.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_retro_cost_probe.gd
extends SceneTree

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var size := Vector2i(3448, 2164)
	root.size = size
	var img := Image.create(1715, 1076, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	for y in img.get_height():
		for x in img.get_width():
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v * 0.9, v * 0.5))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/retro_postprocess.gdshader")
	var tex := ImageTexture.create_from_image(img)
	for k in 6: # six full-size passes a frame, offscreen, so the cost shows above the display's frame cap
		var vp := SubViewport.new()
		vp.size = size
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var tr := TextureRect.new()
		tr.texture = tex
		tr.size = size
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.material = mat
		vp.add_child(tr)
		root.add_child(vp)
	print("window ", DisplayServer.window_get_size())
	for mode in [0, 6, 0, 6, 2, 5]:
		mat.set_shader_parameter("retro_mode", mode)
		for i in 30:
			await process_frame
		var ft := PackedFloat64Array()
		for f in 200:
			var t := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			ft.append((Time.get_ticks_usec() - t) / 1000.0)
		ft.sort()
		print("RESULT mode %d  %.2f ms" % [mode, ft[100]])
	quit()
