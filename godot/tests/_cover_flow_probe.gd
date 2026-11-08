## Windowed probe: opens the open world as the game does and times it, saving a shot of the loading cover early on
## and the cover's frame count (how often the spinner got to draw) while the town built.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_cover_flow_probe.gd -- [out png]
extends SceneTree

var frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/cover_flow.png"
	await process_frame
	root.size = Vector2i(1280, 720)
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(screen.position + screen.size - Vector2i(1300, 760))
	process_frame.connect(func(): frames += 1)
	var ow := OpenWorld.new()
	root.add_child(ow)
	var t0 := Time.get_ticks_msec()
	ow.open("")
	var shot_at := t0 + int(OS.get_environment("SHOT_MS")) if OS.get_environment("SHOT_MS") != "" else t0 + 600
	var shot_taken := false
	var longest := 0
	var last := Time.get_ticks_msec()
	while ow.building or not ow.built:
		await process_frame
		var now := Time.get_ticks_msec()
		if now - last > 150:
			print("gap %d ms at %d ms, status '%s', built %s" % [now - last, now - t0, ow.hud.loading._status.text, ow.built])
		longest = maxi(longest, now - last)
		last = now
		if not shot_taken and now >= shot_at:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out)
			shot_taken = true
	print("COVER open %d ms, %d frames, longest frame gap %d ms" % [Time.get_ticks_msec() - t0, frames, longest])
	quit()
