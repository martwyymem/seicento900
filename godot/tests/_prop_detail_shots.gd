## Windowed probe: the Blender prop kits lit by a midday sun, to check prop_detail.gdshader.
##   godot --path godot --audio-driver Dummy --always-on-top --position 0,0 -s tests/_prop_detail_shots.gd -- [out dir]
extends SceneTree

const WA := preload("res://scripts/ui/world_assets.gd")
const MODELS := ["furniture", "roadside", "town", "landmarks", "brzeszcze_landmarks"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/prop_detail"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.72, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.38, 0.22)
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 55
	root.add_child(cam)
	cam.current = true
	for m in MODELS:
		var scene: Node = WA._load_model("res://models/%s.glb" % m)
		root.add_child(scene)
		var box := AABB()
		var first := true
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		print(m, " bounds ", box)
		# ground it, then look at a few slices of it
		scene.position.y -= box.position.y
		var c := box.get_center()
		var ext := maxf(box.size.x, box.size.z)
		var views := [[Vector3(0.5, 0.25, 1.0), 0.9], [Vector3(-0.8, 0.2, 0.7), 0.5]]
		var vi := 0
		for v in views:
			cam.position = Vector3(c.x, box.size.y * 0.5, c.z) + (v[0] as Vector3).normalized() * ext * (v[1] as float) * 1.4 + Vector3(0, 1, 0)
			cam.look_at(Vector3(c.x, box.size.y * 0.35, c.z), Vector3.UP)
			for i in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s_%d.png" % [m, vi]))
			vi += 1
		scene.queue_free()
		await process_frame
	quit()
