## Windowed probe: does a wall flicker? Looks at buildings near the Wola mineshafts and prints how a centre patch changes.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_flicker_probe.gd -- [out dir]
extends SceneTree

const SPOTS := [["flats_a", Vector2(382, 2082)], ["flats_b", Vector2(375, 2202)]]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/flicker"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1280, 800)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.hud.hide()
	var shadows_modes := [{}]
	for sm in shadows_modes:
		for hr in [7.0, 9.0, 10.5, 12.0, 13.5, 15.0, 17.0]:
			for sp in SPOTS:
				var target: Vector2 = sp[1]
				var ang := 0.0
				var p := target + Vector2(cos(ang), sin(ang)) * 24.0
				ow.drive.place(p, ang + PI)
				ow.drive.respawn()
				ow.hour = hr
				ow.active = true
				for i in 30:
					ow.hour = hr
					await process_frame
				ow.active = false
				var c := Vector3(target.x, ow.drive.z + 5.0, target.y)
				ow.camera.position = Vector3(p.x, ow.drive.z + 3.0, p.y)
				ow.camera.look_at(c, Vector3.UP)
				for k in sm: ow.sun.set(k, sm[k])
				var prev: Image = null
				var changes := 0
				for f in 30:
					ow.hour = hr + f * (1.0 / 80.0 / 60.0)
					ow._apply_time()
					await RenderingServer.frame_post_draw
					var img := root.get_texture().get_image()
					if prev != null:
						for y in range(250, 550, 10):
							for x in range(300, 1000, 10):
								if not prev.get_pixel(x, y).is_equal_approx(img.get_pixel(x, y)):
									changes += 1
					if f == 29 and sp[0] == "flats_a":
						img.save_png(out.path_join("cfg%d.png" % shadows_modes.find(sm)))
					prev = img
				print(sm, " hour ", hr, " ", sp[0], " changed samples over 29 frames: ", changes)
	quit()
