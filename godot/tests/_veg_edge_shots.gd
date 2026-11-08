## Windowed probe: open-world meadows from the chase camera at a few spots, to judge the edge of the planted ring
## (grass, bushes, flowers) against the bare ground beyond. -- [out dir] [quality 0-3]
extends SceneTree

const SHOTS := [
	# [name, x, y, heading, hour]
	["bridge_meadow", -1445.0, 1440.0, 3.37, 9.0],
	["meadow_noon", 1500.0, -1200.0, 2.4, 13.0],
	["meadow_side", 1500.0, -1200.0, 0.6, 16.0],
	["verge_town", 0.0, 0.0, 1.2, 16.0],
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/veg_edge"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var size := Vector2i(1280, 720)
	var usable := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.end - size - Vector2i(8, 8))
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	var veg: Node3D = ow.world.find_child("Vegetation", true, false)
	if args.size() > 1 and veg:
		veg.set_quality(int(args[1]))
	print("quality ", veg.quality if veg else -1)
	for shot in SHOTS:
		ow.drive.place(Vector2(shot[1], shot[2]), shot[3])
		ow.drive.respawn()
		ow.cam_pos = Vector3(ow.drive.car.x, ow.drive.z + 3.0, ow.drive.car.y)
		ow.active = true
		for i in 600:
			paused = false
			ow.hour = shot[4]
			await process_frame
			if i > 60 and veg.queue.is_empty():
				break
		for i in 30:
			paused = false
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(String(shot[0]) + ".png"))
		print("saved ", shot[0])
	quit()
