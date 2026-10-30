## Windowed probe: close views of one building of each kind in Brzeszcze (facades from building.gdshader).
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_building_shots.gd -- [out dir]
## For each kind it finds a building near the town centre, puts the camera 25 m off its longest wall at eye
## height and saves a shot at midday and one at night.
extends SceneTree

const KINDS := ["house", "flats", "commercial", "industrial", "garage", "farm", "church", "public"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/building_shots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1600, 900)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	ow.hud.visible = false
	var spot: Array = ow.map.spots["industrial_sprint"]
	var home := Vector2(spot[0], spot[1])
	for kind in KINDS:
		var best := -1
		var best_d := INF
		for bi in ow.map.buildings.size():
			var b: Array = ow.map.buildings[bi]
			if String(b[0]) != kind or ow.map.bld_rings[bi].size() < 3:
				continue
			var d := ow.map.bld_rings[bi][0].distance_to(home)
			if d < best_d:
				best_d = d
				best = bi
		if best < 0:
			continue
		var ring: PackedVector2Array = ow.map.bld_rings[best]
		var cen := Vector2.ZERO
		for p in ring:
			cen += p
		cen /= ring.size()
		var wa := ring[0]
		var wb := ring[1]
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			if a.distance_to(b) > wa.distance_to(wb):
				wa = a
				wb = b
		var mid := (wa + wb) * 0.5
		var outv := (mid - cen).normalized()
		var h := float(ow.map.buildings[best][1])
		var eye := mid + outv * maxf(22.0, h * 1.6)
		ow.drive.place(eye + outv * 6.0, 0.0)
		ow.drive.respawn()
		for hour in [13.0, 22.5]:
			ow.hour = hour
			ow.active = true
			for i in 30:
				ow.hour = hour
				await process_frame
			ow.active = false
			var g := ow.map.ground(eye.x, eye.y)
			ow.camera.position = Vector3(eye.x, g + 1.7, eye.y)
			ow.camera.look_at(Vector3(mid.x, ow.map.ground(mid.x, mid.y) + minf(h * 0.45, 8.0), mid.y), Vector3.UP)
			ow.camera.fov = 60.0
			for i in 20:
				ow.hour = hour
				await process_frame
			await RenderingServer.frame_post_draw
			var name := "%s_%s.png" % [kind, "day" if hour < 20.0 else "night"]
			root.get_texture().get_image().save_png(out.path_join(name))
			print("saved ", name)
	quit()
