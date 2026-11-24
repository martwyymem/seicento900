## Windowed probe: screenshots of the festival dressing at campaign mission starts (crowds, arch, organisers' trailer).
##   godot --path godot --audio-driver Dummy -s tests/_mission_start_shots.gd -- [out dir]
## Env: MISSIONS (comma list of mission indexes, default 0,3), HOUR (default 17.5).
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/mission_start_shots"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1280, 720)
	var ow := OpenWorld.new()
	root.add_child(ow)
	await ow.open("industrial_sprint")
	var which := (OS.get_environment("MISSIONS") if OS.get_environment("MISSIONS") != "" else "0,3").split(",", false)
	var hour := float(OS.get_environment("HOUR")) if OS.get_environment("HOUR") != "" else 17.5
	var fest: FestivalDressing = ow.builder.festival
	for mk in which:
		var ev := MapMissions.event(Missions.BASE + int(mk))
		var p: Vector2 = ev.pos
		var h := float(ev.heading)
		ow.drive.place(p - Vector2(cos(h), sin(h)) * 2.0, h)
		ow.drive.respawn()
		ow.hour = hour
		ow.snap_camera()
		ow.active = true
		for i in 60:
			ow.hour = hour
			await process_frame
		ow.active = false
		# nearest trailer (a MultiMesh of the dressing) to the start
		var best := Vector3.ZERO
		var best_d := INF
		for n in fest.get_children():
			if String(n.name).begins_with("OrganiserTrailers"):
				var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
				for i in mm.instance_count:
					var o := mm.get_instance_transform(i).origin
					var d := Vector2(o.x, o.z).distance_to(p)
					if d < best_d:
						best_d = d
						best = o
		print("mission ", mk, " start ", p, " trailer ", best, " at ", best_d, " m")
		var road := Vector3(p.x, ow.drive.z, p.y)
		var views := {
			"grid": [road + Vector3(-cos(h), 0, -sin(h)) * 30.0 + Vector3(0, 6, 0), road + Vector3(cos(h), 0, sin(h)) * 20.0 + Vector3.UP * 2.0],
		}
		if best_d < INF:
			var to := Vector3(best.x - road.x, 0, best.z - road.z)
			var away := to.normalized()
			views["trailer"] = [Vector3(best.x, best.y, best.z) - away * 11.0 + Vector3(0, 2.4, 0) + Vector3(-away.z, 0, away.x) * 3.0, best + Vector3.UP * 1.6]
			views["execs"] = [best - away * 4.2 + Vector3(0, 1.7, 0) + Vector3(-away.z, 0, away.x) * 2.5, best - away * 2.9 + Vector3.UP * 1.3 ]
		for vn in views:
			ow.camera.position = views[vn][0]
			ow.camera.look_at(views[vn][1], Vector3.UP)
			ow.camera.fov = 62.0
			for i in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("m%s_%s.png" % [mk, vn]))
			print("saved m", mk, "_", vn)
	quit()
