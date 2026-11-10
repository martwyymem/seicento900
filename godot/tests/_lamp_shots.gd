## QA probe (dev tool, run WINDOWED): the car's lamps and headlight beams in the open world, with numbers.
##  1. the night facade: the car 20 m from a block of flats on Osiedle Paderewskiego (the user's screenshot), its beams
##     on the wall, at HOURS (default 23) through the chase camera; prints the facade's mean brightness and the share of
##     near-white pixels in the upper half of the frame (the wall above the car).
##  2. the lamps of each car in CARS (default stock,golf4) by day and night, from behind and in front, off / braking /
##     reversing; prints the brightness at each lamp (head = headlamp reflector, tail = tail lamp lens).
## Env: OUT (default /tmp/qa/lamps), HOURS (facade hours, comma), CARS, DIST (m from the wall, default 20). Saves are
## backed up and restored (shared sandbox).
## godot --path godot --audio-driver Dummy --always-on-top --resolution 1280x720 --position 2140,1390 -s tests/_lamp_shots.gd
extends SceneTree

const Guard := preload("res://tests/_qa_save_guard.gd")
var game
var cam: Camera3D

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _wait(frames: int) -> void:
	for k in frames:
		if game:
			game._app_focused = true
			if game.paused:
				game._set_paused(false)
		await process_frame

func _initialize() -> void:
	Brain.use_disk = false
	Guard.backup()
	var out := _env("OUT", "/tmp/qa/lamps")
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await _wait(30)
	game._on_aspect_selected(1)
	game._on_preset_selected(2)
	await _wait(5)
	await game._enter_open_world("")
	await _wait(60)
	var ow: OpenWorld = game.open_world
	if ow == null or ow.map == null:
		print("LAMPS no open world")
		Guard.restore()
		quit(1)
		return
	await _facade(ow, out)
	await _lamps(ow, out)
	game.queue_free()
	await process_frame
	Guard.restore()
	quit()

## The tallest block of flats within 120 m of Osiedle Paderewskiego, the car DIST m off its longest wall facing it.
func _facade(ow: OpenWorld, out: String) -> void:
	var road_pts: Array = []
	for ri in ow.map.road_pts.size():
		if ow.map.road_name[ri] == "Osiedle Ignacego Paderewskiego":
			road_pts.append_array(Array(ow.map.road_pts[ri]))
	var best := []
	for b in ow.map.buildings:
		if float(b[1]) < 12.0:
			continue
		var poly: Array = b[4]
		var c := Vector2.ZERO
		for k in range(0, poly.size() - 1, 2):
			c += Vector2(poly[k], poly[k + 1])
		c /= poly.size() / 2.0
		var near := INF
		for q in road_pts:
			near = minf(near, c.distance_to(q))
		if near < 120.0 and (best.is_empty() or float(b[1]) > float(best[0][1])):
			best = [b, c]
	if best.is_empty():
		print("LAMPS no block of flats found near Osiedle Paderewskiego")
		return
	var poly: Array = best[0][4]
	var c: Vector2 = best[1]
	var wa := Vector2.ZERO
	var wb := Vector2.ZERO
	var n := poly.size() / 2
	for k in n:
		var a := Vector2(poly[2 * k], poly[2 * k + 1])
		var b2 := Vector2(poly[(2 * k + 2) % (2 * n)], poly[(2 * k + 3) % (2 * n)])
		if a.distance_to(b2) > wa.distance_to(wb):
			wa = a
			wb = b2
	var mid := (wa + wb) * 0.5
	var normal := (wb - wa).orthogonal().normalized()
	if normal.dot(mid - c) < 0.0:
		normal = -normal
	var dist := float(_env("DIST", "20"))
	var p := mid + normal * dist
	print("LAMPS facade: %.0f m tall %s at %s, wall %.0f m long, car %.0f m off it at %s" % [float(best[0][1]), best[0][0], c, wa.distance_to(wb), dist, p])
	for hour_s in _env("HOURS", "23").split(","):
		ow.hour = float(hour_s)
		ow.drive.place(p, (-normal).angle())
		ow.snap_camera()
		for i in 90:
			ow.hour = float(hour_s)
			ow.drive.place(p, (-normal).angle())
			await _wait(1)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/facade_h%s.png" % [out, hour_s]
		img.save_png(path)
		var st := _region(img, Rect2i(0, 0, img.get_width(), img.get_height() / 2))
		print("LAMPS facade hour %s: upper half mean %.3f, near-white %.1f%%, beam energy %.1f -> %s" % [hour_s, st.mean, st.white * 100.0,
			ow.headlights[0].light_energy if ow.headlights.size() else 0.0, path])

## Each car's lamps from behind and in front, by day and by night, off / braking / reversing.
func _lamps(ow: OpenWorld, out: String) -> void:
	var s: Array = ow.map.spots.industrial_sprint
	cam = Camera3D.new()
	cam.fov = 40.0
	ow.world.add_child(cam)
	for key in _env("CARS", "stock,golf4").split(","):
		ow.progress.car_class = CarCatalog.index_of(key)
		ow._fit_car()
		for hour: float in [14.0, 23.0]:
			ow.hour = hour
			OpenWorld.spawn_car(ow.drive, ow.map, Vector2(s[0], s[1]), float(s[2]))
			for i in 60:
				ow.hour = hour
				await _wait(1)
			ow.active = false # frozen: the probe sets the lamps and the camera
			var v: Node3D = ow.car_visual
			for state in ["off", "brake", "reverse"]:
				ow.drive.car.brake_on = state == "brake"
				ow.drive.car.rev = state == "reverse"
				v.sync(ow.drive.car, 0.0, 0.0, ow.night, false)
				for side in ["rear", "front"]:
					var back := v.global_basis.z.normalized() * (1.0 if side == "rear" else -1.0) # -Z is the car's front
					cam.global_position = v.global_position + back * 5.5 + Vector3.UP * 1.3
					cam.look_at(v.global_position + Vector3.UP * 0.6, Vector3.UP)
					cam.make_current()
					for i in 4:
						await process_frame
					await RenderingServer.frame_post_draw
					var img := root.get_texture().get_image()
					var path := "%s/%s_h%d_%s_%s.png" % [out, key, int(hour), state, side]
					img.save_png(path)
					var lamp := "tail" if side == "rear" else "head"
					var at := _lamp_point(v, "TailGlass" if side == "rear" else "Headlight")
					var sc := Vector2(img.get_size()) / Vector2(game.get_viewport().get_visible_rect().size)
					var px := Vector2i(cam.unproject_position(at) * sc)
					var st := _region(img, Rect2i(px - Vector2i(4, 4), Vector2i(9, 9)))
					print("LAMPS %s hour %d %s from the %s: %s lamp brightness %.3f (red %.3f) -> %s" % [key, int(hour), state, side, lamp, st.mean, st.red, path])
			ow.drive.car.brake_on = false
			ow.drive.car.rev = false
			ow.active = true
	cam.queue_free()

## The middle of the right-hand lamp of a Details surface, in the world.
func _lamp_point(v: Node3D, material: String) -> Vector3:
	var d: MeshInstance3D = v._details_node
	var surf := -1
	for i in d.mesh.get_surface_count():
		var m := d.mesh.surface_get_material(i)
		var o := d.get_surface_override_material(i)
		if (m and m.resource_name == material) or (o and o.resource_name == material):
			surf = i
	if surf < 0:
		return d.global_position
	var sum := Vector3.ZERO
	var k := 0
	for p: Vector3 in d.mesh.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
		if p.x > 0.0:
			sum += p
			k += 1
	return d.to_global(sum / maxf(k, 1))

func _region(img: Image, r: Rect2i) -> Dictionary:
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var sum := 0.0
	var red := 0.0
	var white := 0
	var n := 0
	for y in range(r.position.y, r.end.y, 2 if r.size.y > 50 else 1):
		for x in range(r.position.x, r.end.x, 2 if r.size.x > 50 else 1):
			var c := img.get_pixel(x, y)
			sum += c.get_luminance()
			red += c.r
			if c.r > 0.94 and c.g > 0.94 and c.b > 0.94:
				white += 1
			n += 1
	return {"mean": sum / maxf(n, 1), "red": red / maxf(n, 1), "white": float(white) / maxf(n, 1)}
