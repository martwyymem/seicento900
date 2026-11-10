## The car catalogue (CarCatalog): every entry has a spec, a model that loads at the spec's real size, and a way to be unlocked;
## the Golf IV's performance sits in the real car's band; its model dresses a RaceCarVisual (wheels in the arches, decals on the
## body); whole fields finish races in it; the strategist and the rail AI calibrate it separately from the Seicento; settings
## that name it (and old ones that don't) round-trip. The campaign save is written and read back at once (the sandbox is shared).
extends RefCounted

var completed := false
var errors: Array[String] = []

const PROBE := preload("res://tests/_car_probe.gd")
const VISUAL := preload("res://scripts/ui/race_car_visual.gd")

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	_entries()
	_unlock()
	_performance()
	_visual()
	_calibration()
	await _races()
	_settings()
	completed = true
	return errors

func _entries() -> void:
	check(CarCatalog.KEYS.size() >= 3 and CarCatalog.KEYS[0] == "stock" and CarCatalog.KEYS[1] == "hypercar", "the saved picker order (stock 0, hypercar 1) changed")
	var seen := {}
	for k in CarCatalog.KEYS:
		check(not seen.has(k), "duplicate catalogue key %s" % k)
		seen[k] = true
		check(CarCatalog.is_key(k) and CarCatalog.key_at(CarCatalog.index_of(k)) == k, "%s: key and index do not round-trip" % k)
		check(CarCatalog.display_name(k) != "", "%s has no display name" % k)
		check(CarCatalog.unlock_hint(k) != "", "%s has no unlock hint" % k)
		var m := CarCatalog.model(k)
		check(m != null and m.spec.gears.size() >= 4 and m.spec.torque_curve.size() >= 4, "%s: no usable drivetrain" % k)
		check(m.spec.length > 3.0 and m.spec.wheelbase > 2.0 and m.spec.wheel_radius > 0.2, "%s: odd dimensions" % k)
		check(k == "stock" or m.spec.resource_name == k or k == "hypercar", "%s: the spec's resource_name is the key Track/Race key on (got '%s')" % [k, m.spec.resource_name])
		var v: Dictionary = CarCatalog.visual(k)
		check(ResourceLoader.exists(v.model), "%s: %s does not exist" % [k, v.model])
		for need in ["wheel_radius", "wheelbase", "half_track_front", "half_track_rear", "roof_number", "brake_light", "tailpipe", "fx_axle", "contact"]:
			check(v.has(need), "%s: the visual lacks '%s'" % [k, need])
	check(CarCatalog.model("stock").spec.resource_name == "", "the stock Seicento's spec must stay unnamed (it is the stock calibration)")
	# the golf's model is the real size: the GLB's Body against the spec
	var g := CarCatalog.spec("golf4")
	var scene := ResourceLoader.load(CarCatalog.visual("golf4").model, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(scene != null, "golf4.glb does not load")
	if scene:
		var root := scene.instantiate()
		var body := root.find_child("Body", true, false) as MeshInstance3D
		if body:
			var size := body.mesh.get_aabb().size
			check(absf(size.z - g.length) < 0.05, "the Golf's Body is %.3f m long, the spec says %.3f" % [size.z, g.length])
			var top := body.mesh.get_aabb().end.y
			check(top > 1.42 and top < 1.46, "the Golf's roof is %.3f m high (1.439 expected)" % top)
			check(size.x > g.width and size.x < g.width + 0.25, "the Golf's Body is %.3f m wide (mirrors out; spec %.3f)" % [size.x, g.width])
		var wheel := root.find_child("Wheel", true, false) as MeshInstance3D
		if wheel:
			var d := wheel.mesh.get_aabb().size.y
			check(absf(d * 0.5 - CarCatalog.visual("golf4").wheel_radius) < 0.004, "the Golf's wheel radius is %.4f m, the visual says %.4f" % [d * 0.5, CarCatalog.visual("golf4").wheel_radius])
		root.free()

func _unlock() -> void:
	var dev := FanLevels.dev_unlock
	FanLevels.dev_unlock = false
	check(CarCatalog.unlocked("stock"), "the stock Seicento is not always open")
	check(not CarCatalog.unlocked("hypercar", 0), "the hypercar is open at 0 fans")
	check(CarCatalog.unlocked("hypercar", FanLevels.THRESHOLDS[-1]), "the hypercar is shut at the top fan level")
	var before := Campaign.load_progress()
	var without := before.duplicate(true)
	without.erase("cars")
	Campaign.save_progress(without)
	check(not CarCatalog.unlocked("golf4"), "the Golf is open with no car in the campaign save")
	check(CarCatalog.open_keys(0) == ["stock"] or CarCatalog.open_keys(0).size() >= 1, "open_keys is empty")
	var with_golf := without.duplicate(true)
	with_golf["cars"] = ["golf4"]
	Campaign.save_progress(with_golf)
	check(CarCatalog.unlocked("golf4"), "the Golf is shut although the campaign save lists it")
	check("golf4" in CarCatalog.open_keys(0), "open_keys leaves out the awarded Golf")
	check(not CarCatalog.unlocked("hypercar", 0), "an awarded Golf opened the hypercar")
	Campaign.save_progress(without)
	FanLevels.dev_unlock = true
	check(CarCatalog.unlocked("golf4") and CarCatalog.unlocked("hypercar", 0), "the dev menu's unlock everything does not open the cars")
	FanLevels.dev_unlock = false
	check(not CarCatalog.unlocked("golf4"), "the Golf stayed open after the override went off")
	Campaign.save_progress(before)
	FanLevels.dev_unlock = dev

func _performance() -> void:
	var m: Dictionary = PROBE.measure(Golf4.model())
	var s: Dictionary = PROBE.measure(CarModel.new())
	print("    golf4: %.1f s 0-100, %.0f km/h, %.1f m from 100, %.2f g; stock: %.1f s, %.0f km/h, %.1f m, %.2f g" % [m.t100, m.top, m.brake, m.lat_g, s.t100, s.top, s.brake, s.lat_g])
	check(m.t100 > 13.2 and m.t100 < 14.6, "the Golf's 0-100 is %.2f s (real 13.9)" % m.t100)
	check(m.top > 165.0 and m.top < 177.0, "the Golf's top speed is %.0f km/h (real 171)" % m.top)
	check(m.brake > 36.0 and m.brake < 44.0, "the Golf stops from 100 km/h in %.1f m (real ~40)" % m.brake)
	check(m.lat_g > 0.78 and m.lat_g < 0.92, "the Golf holds %.2f g on the skidpad (real ~0.84)" % m.lat_g)
	check(not Golf4.spec().awd and m.mass > 1100.0 and m.mass < 1260.0, "the Golf is front-wheel drive at ~1.18 t (%.0f kg)" % m.mass)
	check(m.t100 < s.t100 and m.top > s.top, "the Golf is quicker than the Seicento")

func _visual() -> void:
	var parent := Node3D.new()
	Engine.get_main_loop().root.add_child(parent)
	var car: Node3D = VISUAL.new()
	car.car_key = "golf4"
	car.car_number = 5
	parent.add_child(car)
	check(car.wheels.size() == 4 and car._wheelbase == 2.511, "the Golf visual lacks its four wheels or its wheelbase")
	var fl: Vector3 = car._wheel_spots[0]
	var rr: Vector3 = car._wheel_spots[3]
	check(absf(fl.z + 1.2555) < 1e-3 and absf(rr.z - 1.2555) < 1e-3 and absf(fl.y - 0.3172) < 1e-4, "the Golf's wheels are not at its axles (%s %s)" % [fl, rr])
	# every decal sits on the Body, facing outwards
	var tri := (VISUAL._shared_resources("golf4").shell as Mesh).generate_triangle_mesh()
	for n in ["DoorDecalL", "DoorDecalR", "Sunstrip", "HoodDecal", "SillDecalL", "SillDecalR"]:
		var d := car.body_pivot.get_node_or_null(n) as MeshInstance3D
		check(d != null and d.mesh != null, "the Golf visual lacks decal %s" % n)
		if d == null:
			continue
		var normal := d.transform.basis.z.normalized()
		var hit := tri.intersect_ray(d.position + normal * 0.3, -normal)
		check(not hit.is_empty() and absf(((d.position - (hit.position as Vector3)).dot(normal)) - 0.006) < 0.004, "the Golf's %s does not sit on the body" % n)
	# the Golf's wheels are the Golf's, the Seicento's are unchanged, and a swap rebuilds
	var sei: Node3D = VISUAL.new()
	parent.add_child(sei)
	check(sei.car_key == "stock" and sei._wheel_spots == VISUAL.WHEEL_SPOTS and absf(sei._wheel_radius - VISUAL.WHEEL_RADIUS) < 1e-9, "the stock visual no longer uses its constants")
	check(sei._shell.mesh != car._shell.mesh, "the Golf and the Seicento share a body mesh")
	sei.set_car("golf4")
	check(sei.wheels.size() == 4 and sei._wheelbase == 2.511 and sei._shell.mesh == car._shell.mesh, "set_car did not rebuild the car as a Golf")
	sei.set_car("stock")
	check(sei._wheelbase == 2.2 and sei._shell.mesh != car._shell.mesh, "set_car did not go back to the Seicento")
	parent.free()

func _calibration() -> void:
	var track := Race.get_track("gp")
	var g := CarCatalog.model("golf4")
	var gs := Strategy.new(g, Tyres.new())
	var ss := Strategy.new(CarModel.new(), Tyres.new())
	var cg := gs.calibrate(track)
	var cs := ss.calibrate(track)
	check(not is_same(cg, cs) and absf(cg.T0 - cs.T0) > 0.01, "the Golf shares the Seicento's calibration on the track")
	check(cg.T0 > 30.0 and cg.fuel_per_lap > 0.3 and cg.top_speed > 30.0, "the Golf's calibration is implausible (T0 %.1f, fuel %.2f, top %.1f m/s)" % [cg.T0, cg.fuel_per_lap, cg.top_speed])
	check(is_same(gs.calibrate(track), cg), "the Golf's calibration is not cached")
	check(track.cal_alt.size() >= 1 and not is_same(track.cal, cg), "the Golf's calibration went into the stock slot")
	var pg := track.profile_for(g)
	var ps := track.profile_for(CarModel.new())
	check(not is_same(pg, ps) and pg.size() == ps.size(), "the Golf has no rail profile of its own")
	var slower := 0
	var faster := 0
	for i in pg.size():
		if pg[i] < ps[i] - 0.01:
			slower += 1
		elif pg[i] > ps[i] + 0.01:
			faster += 1
	check(slower > faster, "the Golf's grip (0.86 g against the Seicento's 0.96) should take the corners slower (%d slower, %d faster)" % [slower, faster])
	check(is_same(track.profile_for(g), pg), "the Golf's profile is not cached")

func _races() -> void:
	for tk in ["gp", "fiat"]:
		var rs := RaceSettings.new()
		rs.track = tk
		rs.laps = 2
		rs.opponents = 5
		rs.car_class = "golf4"
		rs.race_control = false
		var cm := CarCatalog.model("golf4")
		var r := Race.new(rs, {"stints": [{"c": "M", "laps": 2}]}, 11, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})
		check(r.spec.resource_name == "golf4" and r.cars.size() == 6, "%s: the race is not in the Golf with a field of six" % tk)
		r.set_autopilot(true)
		var idle := Race.PlayerInput.new()
		var ticks := 0
		while r.phase != "finished" and ticks < 60 * 60 * 20:
			r.step(1.0 / 60.0, idle)
			ticks += 1
		var done := 0
		for c in r.cars:
			if c.finished and not c.dnf:
				done += 1
		check(r.phase == "finished" and done == r.cars.size(), "%s: only %d of %d Golfs finished (phase %s after %d ticks)" % [tk, done, r.cars.size(), r.phase, ticks])
		check(r.player.finish_time != null and float(r.player.finish_time) > 30.0, "%s: the player's Golf has no sensible finish time" % tk)
		r.dispose()
		await Engine.get_main_loop().process_frame

func _settings() -> void:
	var st := RaceSettings.new()
	check(st.car_class == "stock", "the default car class is not stock")
	st.car_class = "golf4"
	var path := "user://dev_sandbox/_catalog_settings_test.tres"
	DirAccess.make_dir_recursive_absolute("user://dev_sandbox")
	check(ResourceSaver.save(st, path) == OK, "could not save settings naming the Golf")
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RaceSettings
	check(back != null and back.car_class == "golf4", "the Golf's car class did not round-trip")
	DirAccess.remove_absolute(path)
	# an old settings resource has no car_class: it loads as the stock car
	var old := FileAccess.open(path, FileAccess.WRITE)
	old.store_string('[gd_resource type="Resource" script_class="RaceSettings" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/data/race_settings.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\ntrack = "gp"\nlaps = 3\n')
	old.close()
	var legacy := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RaceSettings
	check(legacy != null and legacy.car_class == "stock" and legacy.laps == 3, "settings without a car class do not load as the stock car")
	DirAccess.remove_absolute(path)
	# the open world stores the class as an index: old saves (0, 1) keep their meaning, an unknown one clamps
	check(CarCatalog.key_at(0) == "stock" and CarCatalog.key_at(1) == "hypercar" and CarCatalog.key_at(99) == CarCatalog.KEYS[-1], "world car indexes changed meaning")
