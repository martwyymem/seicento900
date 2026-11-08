## Windowed probe: the car parked against a bridge's parapet, from the chase camera (it used to roll under the deck).
## godot --path godot --audio-driver Dummy --always-on-top -s tests/_bridge_edge_shots.gd -- [out dir]
extends SceneTree

const ROADS := [1501, 1932, 1239, 1744]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/bridge_edge"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var size := Vector2i(1280, 720)
	var usable := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.end - size - Vector2i(8, 8))
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	var map: TownMap = ow.map
	for ri: int in ROADS:
		var pts := map.road_pts[ri]
		var zs := map.road_z[ri]
		var best := -1
		for i in pts.size() - 1:
			if minf(zs[i], zs[i + 1]) > 3.0 and (best < 0 or absf(i - pts.size() / 2) < absf(best - pts.size() / 2)):
				best = i
		if best < 0:
			continue
		var d := (pts[best + 1] - pts[best]).normalized()
		var p := (pts[best] + pts[best + 1]) * 0.5 + Vector2(-d.y, d.x) * (map.road_w[ri] * 0.5 - FreeCar.HALF_W - 0.05) - d * 10.0
		ow.drive.place(p, atan2(d.y, d.x))
		ow.drive.z = ow.drive.support(p.x, p.y)
		ow.drive.vz = 0.0
		ow.drive.airborne = false
		ow.cam_pos = Vector3(p.x - d.x * 6.0, ow.drive.z + 3.0, p.y - d.y * 6.0)
		ow.active = true
		for i in 240:
			paused = false
			ow.hour = 9.0
			await process_frame
		var up: Vector3 = ow.drive.tilt.y
		print("road %d at %s: car z %.2f, deck %.2f, tilt %.1f deg" % [ri, p, ow.drive.z, map.ground(p.x, p.y) + map.deck_at(ri, best, 0.5), rad_to_deg(acos(clampf(up.y, -1.0, 1.0)))])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("bridge_%d.png" % ri))
	quit()
