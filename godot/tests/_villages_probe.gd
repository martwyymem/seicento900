## Windowed probe: the open world's villages seen from the road. For each place, the nearest road, whether it is
## inside the play area, the buildings within 150 m, and a chase-camera shot facing along the road.
##   godot --path godot --audio-driver Dummy --resolution 800x450 --position 700,500 -s tests/_villages_probe.gd -- [out dir]
extends SceneTree

const PLACES := ["Wola", "Rajsko", "Jawiszowice", "Góra"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/villages"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/brzeszcze.json"))
	for pl in raw.places:
		if not PLACES.has(pl.name):
			continue
		var p := Vector2(pl.x, pl.y)
		var nr := ow.map.nearest_road(p, 600.0, 2)
		print("%s: at (%.0f, %.0f) in_play %s, nearest road %s, buildings<150m %d" % [pl.name, p.x, p.y, ow.map.in_play(p), "%.0f m" % nr.dist if not nr.is_empty() else "none within 600 m", ow.map.buildings_near(p, 150.0).size()])
		if nr.is_empty():
			continue
		ow.drive.place(nr.pos, atan2(nr.dir.y, nr.dir.x))
		ow.drive.respawn()
		ow.hour = 14.0
		ow.cam_pos = Vector3(ow.drive.car.x, ow.drive.z + 3.0, ow.drive.car.y)
		ow.active = true
		for i in 50:
			ow.hour = 14.0
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(String(pl.name).to_ascii_buffer().hex_encode() + ".png"))
		print("  saved ", pl.name, "; car z ", ow.drive.z, " in play ", ow.map.in_play(Vector2(ow.drive.car.x, ow.drive.car.y)))
	quit()
