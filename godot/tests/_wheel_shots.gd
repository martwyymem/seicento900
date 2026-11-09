## Windowed probe: close, low shots of a tyre meeting the road, before (the old ride height) and after the fix.
##   WHAT=ow       open world: a street, and a pavement edge     WHAT=circuit  TRACK=monza (default): the asphalt
##   python3 winlock.py godot --path godot -s tests/_wheel_shots.gd -- <out dir>
## "before" reproduces the old heights on the visual: the open-world car at the ground-height support (no street lift),
## the circuit car at RaceWorld's _road_y (ROAD_REF) instead of onto the asphalt ribbon.
extends SceneTree

const CarVisual := preload("res://scripts/ui/race_car_visual.gd")
const SIZE := Vector2i(1280, 720)
var out := ""

func _initialize() -> void:
	Brain.use_disk = false
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "/tmp/wheels"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.size = Vector2i(640, 360)
	if OS.get_environment("WHAT") == "circuit":
		await _circuit()
	else:
		await _open_world()
	print("DONE")
	quit()

## Camera low beside/in front of one wheel of `visual` (index into WHEEL_SPOTS), looking at its contact patch.
func _aim(cam: Camera3D, visual: Node3D, wheel: int, fwd: float, out_k: float, height: float, look_h: float) -> void:
	var spot: Vector3 = CarVisual.WHEEL_SPOTS[wheel]
	var w := visual.global_transform * Vector3(spot.x, 0.0, spot.z)
	var right := visual.global_transform.basis.x.normalized()
	var forward := -visual.global_transform.basis.z.normalized()
	var outward := right * signf(spot.x)
	cam.global_position = w + forward * fwd + outward * out_k + Vector3.UP * height
	cam.look_at(w + Vector3.UP * look_h, Vector3.UP)
	cam.fov = 38.0

func _open_world() -> void:
	var ow := OpenWorld.new()
	ow.render_size = func(_px: Vector2i) -> Vector2i: return SIZE
	root.add_child(ow)
	await ow.open("industrial_sprint", {"quality": 3})
	ow.apply_graphics(3)
	ow.hud.hide()
	if ow.route_mesh:
		ow.route_mesh.visible = false
	for b in ow.builder.beacon_nodes.values():
		(b as Node3D).visible = false
	if ow.traffic:
		ow.traffic.clear()
	var map: TownMap = ow.map
	print("open world built")
	# spot 1: a residential street, car in its lane; spot 2: beside a pavement, the car's side at the kerb
	var spots := []
	spots.append(["street", _street_spot(map, false)])
	spots.append(["pavement", _street_spot(map, true)])
	for sp in spots:
		var name: String = sp[0]
		var info: Dictionary = sp[1]
		if info.is_empty():
			print("no spot for ", name)
			continue
		ow.drive.place(info.p, info.h)
		ow.drive.car.heading = info.h
		ow.hour = 15.5
		ow.active = true
		for f in 60:
			ow.hour = 15.5
			ow.throttle = 0.0
			ow.brake = 1.0
			await process_frame
		ow.active = false
		for f in 6:
			await process_frame
		var p := Vector2(ow.drive.car.x, ow.drive.car.y)
		print(name, " car at ", p, " z ", ow.drive.z, " support unlifted ", ow.drive.support(p.x, p.y, false), " pavement top ", map.pave_top_at(p.x, p.y))
		var lifted_y: float = ow.car_visual.position.y
		# the wheel at the pavement side (or the right one on a plain street), a low look from in front; the camera
		# is set from the fixed (after) pose and stays put for both variants
		_aim(ow.camera, ow.car_visual, int(info.wheel), 1.7, 0.7, 0.16, 0.08)
		for variant in ["before", "after"]:
			ow.car_visual.position.y = ow.drive.support(p.x, p.y, false) if variant == "before" else lifted_y
			for f in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out.path_join("ow_%s_%s.png" % [name, variant])
			ow.viewport.get_texture().get_image().save_png(path)
			print("saved ", path)

## A parking spot on a residential street: {p, h, wheel}. beside_pavement: the car's right side at a pavement's kerb.
func _street_spot(map: TownMap, beside_pavement: bool) -> Dictionary:
	for ri in map.road_pts.size():
		if map.road_kind[ri] != "residential" or not map.road_z[ri].is_empty() or map.road_len[ri] < 30.0:
			continue
		var pts := map.road_pts[ri]
		for i in range(2, pts.size() - 2):
			var d := (pts[i + 1] - pts[i]).normalized()
			if (pts[i + 1] - pts[i]).length() < 3.0:
				continue
			var n := Vector2(-d.y, d.x)
			var half := map.road_w[ri] * 0.5
			var mid := pts[i] + (pts[i + 1] - pts[i]) * 0.5
			for sd: float in [1.0, -1.0]:
				var kerb_side := mid + n * sd * (half + 0.5)
				var has_pave := map.pave_top_at(kerb_side.x, kerb_side.y) > 0.0
				if has_pave != beside_pavement:
					continue
				if map.road_at(mid.x, mid.y).is_empty() or not map.buildings_near(mid, 3.0).is_empty():
					continue
				# park with the side at the kerb: centre HALF_W + 0.25 from the road edge
				var spot := mid + n * sd * (half - 1.0) if beside_pavement else mid + n * 1.0
				var heading := d.angle()
				# which wheel is on the pavement side: right of travel is +n for heading d (x east, y south)
				var wheel := 1 if sd > 0.0 else 0 # FR on the +n side (right of travel), FL otherwise
				return {"p": spot, "h": heading, "wheel": wheel}
	return {}

func _circuit() -> void:
	var key := OS.get_environment("TRACK") if OS.get_environment("TRACK") != "" else "monza"
	root.size = SIZE
	var world = load("res://ui/race_world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	var rs := RaceSettings.new()
	rs.track = key
	rs.opponents = 3
	rs.laps = 3
	var race := Race.new(rs, null, 1)
	world.set_race(race)
	for f in 20:
		await process_frame
	print("circuit ", key, " world built")
	var visual: Node3D = world.visuals[race.player.id]
	world.set_process(false)
	var base_y := visual.position.y
	print("player visual y ", base_y)
	_aim(world.camera, visual, 1, 1.7, 0.7, 0.16, 0.08)
	for variant in ["before", "after"]:
		visual.position.y = base_y + (World_REF - World_ASPHALT) if variant == "before" else base_y
		for f in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out.path_join("circuit_%s_%s.png" % [key, variant])
		root.get_texture().get_image().save_png(path)
		print("saved ", path)

const World_REF := 0.09
const World_ASPHALT := 0.04
