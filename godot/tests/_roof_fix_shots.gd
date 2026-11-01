## Windowed probe: Brzeszcze houses whose measured roof planes covered little of the footprint (they had
## walls with no roof over them). Saves one dusk shot of each from 30 m.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_roof_fix_shots.gd -- [out dir] [building indices...]
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/roof_fix"
	var ids: Array = []
	for i in range(1, args.size()):
		ids.append(int(args[i]))
	if ids.is_empty():
		ids = [70, 362, 475, 614]
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1280, 720)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.hud.visible = false
	for bi in ids:
		var ring: PackedVector2Array = ow.map.bld_rings[bi]
		var cen := Vector2.ZERO
		for p in ring:
			cen += p
		cen /= ring.size()
		var h := float(ow.map.buildings[bi][1])
		for k in 2:
			var dir := Vector2(1, 1).normalized() if k == 0 else Vector2(-1, 0.4).normalized()
			var eye := cen + dir * (28.0 + h)
			ow.drive.place(eye, 0.0)
			ow.drive.respawn()
			ow.hour = 17.0
			ow.active = true
			for i in 20:
				ow.hour = 17.0
				await process_frame
			ow.active = false
			ow.camera.position = Vector3(eye.x, ow.map.ground(eye.x, eye.y) + 6.0, eye.y)
			ow.camera.look_at(Vector3(cen.x, ow.map.ground(cen.x, cen.y) + h * 0.6, cen.y), Vector3.UP)
			ow.camera.fov = 60.0
			for i in 20:
				ow.hour = 17.0
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("b%d_%d.png" % [bi, k]))
	quit()
