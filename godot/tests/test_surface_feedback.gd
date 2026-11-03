## The open world's surface feedback (SurfaceFeedback, TASKS.md Phase 2 backlog 1): what each wheel stands on, the
## gravel crunch and grass loops at WorldAudio's race levels, and the car visual's dust, kick-up and tyre smoke
## (race_car_visual.gd surface_fx, shared with the races). Smoke only comes off a paved road.
extends RefCounted

const Surfaces := preload("res://tests/test_surfaces.gd")
const CAR_SCENE := preload("res://scripts/ui/race_car_visual.tscn")
const CarVisual := preload("res://scripts/ui/race_car_visual.gd")

var completed := false
var errors := []

func check(what: String, ok: bool) -> void:
	if not ok:
		errors.append(what)

func _all(s: int) -> PackedInt32Array:
	return PackedInt32Array([s, s, s, s])

func run() -> Array:
	# ---- what the wheels are on
	var c := SurfaceFeedback.contact(_all(Physics.SURF_DIRT))
	check("four wheels on a dirt road crunch at LOOSE_ROAD_CRUNCH[0], got %s" % c,
		is_equal_approx(c[1], WorldAudio.LOOSE_ROAD_CRUNCH[0]) and c[0] == 0.0)
	c = SurfaceFeedback.contact(_all(Physics.SURF_GRAVEL_ROAD))
	check("a gravel road crunches at LOOSE_ROAD_CRUNCH[1], got %s" % c, is_equal_approx(c[1], WorldAudio.LOOSE_ROAD_CRUNCH[1]))
	c = SurfaceFeedback.contact(PackedInt32Array([Physics.SURF_GRASS, Physics.SURF_GRASS, Physics.SURF_TRACK, Physics.SURF_TRACK]))
	check("two wheels on the grass swish at half, got %s" % c, is_equal_approx(c[0], 0.5) and c[1] == 0.0)
	c = SurfaceFeedback.contact(_all(Physics.SURF_ASPHALT))
	check("tarmac is quiet, got %s" % c, c[0] == 0.0 and c[1] == 0.0)
	check("the loosest wheel shows: gravel trap over grass",
		SurfaceFeedback.kick_surface(PackedInt32Array([Physics.SURF_GRASS, Physics.SURF_GRAVEL, 0, 0])) == Physics.SURF_GRAVEL)
	check("the loosest wheel shows: dirt over tarmac",
		SurfaceFeedback.kick_surface(PackedInt32Array([0, 0, Physics.SURF_DIRT, 0])) == Physics.SURF_DIRT)
	check("all tarmac shows tarmac", SurfaceFeedback.kick_surface(_all(Physics.SURF_TRACK)) == Physics.SURF_TRACK)

	# ---- effect strengths (dry, as the open world always is)
	var fx: Dictionary = CarVisual.surface_fx(Physics.SURF_DIRT, 20.0, 1.0, 0.0, 0.0, false)
	check("a sliding car on a dirt road throws dust, not smoke: %s" % fx, fx.get("dust", 0.0) > 0.5 and not fx.has("smoke"))
	fx = CarVisual.surface_fx(Physics.SURF_GRAVEL_ROAD, 20.0, 0.0, 0.0, 0.0, false)
	check("a gravel road throws dust: %s" % fx, fx.get("dust", 0.0) > 0.5)
	fx = CarVisual.surface_fx(Physics.SURF_GRASS, 20.0, 1.0, 0.0, 0.0, false)
	check("grass kicks up grass, no smoke: %s" % fx, fx.get("grass", 0.0) > 0.5 and not fx.has("smoke"))
	fx = CarVisual.surface_fx(Physics.SURF_TRACK, 20.0, 1.0, 0.0, 0.0, false)
	check("a slide on tarmac smokes: %s" % fx, fx.get("smoke", 0.0) > 0.5 and not fx.has("dust"))
	fx = CarVisual.surface_fx(Physics.SURF_TRACK, 20.0, 0.0, 0.0, 0.0, false)
	check("rolling on dry tarmac shows nothing: %s" % fx, fx.values().all(func(k): return k <= 0.02))
	check("a standing car shows nothing", CarVisual.surface_fx(Physics.SURF_DIRT, 1.0, 1.0, 0.0, 0.0, false).is_empty())

	# ---- the FreeCar on a flat dirt town: the wheels report dirt, the crunch rises, the visual throws dust
	var tree := Engine.get_main_loop() as SceneTree
	var town: TownMap = Surfaces.FlatTown.new()
	town.force_surf = Physics.SURF_DIRT
	var fc := FreeCar.new(town)
	fc.place(Vector2.ZERO, 0.0)
	fc.car.vx = 20.0
	fc.car.speed = 20.0
	var surfs := fc.wheel_surfaces()
	check("FreeCar.wheel_surfaces gives four dirt wheels, got %s" % surfs, surfs == _all(Physics.SURF_DIRT))
	var sf := SurfaceFeedback.new()
	tree.root.add_child(sf)
	var vis := CAR_SCENE.instantiate()
	tree.root.add_child(vis)
	vis.is_player = true
	for i in 30:
		sf.update(fc, vis, 1.0 / 60.0)
	check("the gravel crunch plays on a dirt road at 72 km/h (gain %.2f)" % sf._gravel.gain, sf._gravel.gain > 0.2)
	check("no grass swish on a dirt road (gain %.2f)" % sf._grass.gain, sf._grass.gain < 0.01)
	var dust := vis.get_node_or_null("Fx_kickup_dirt") as GPUParticles3D
	check("the car visual throws dust on a dirt road", dust != null and dust.emitting)
	# airborne: the loops die away and the dust stops
	fc.airborne = true
	for i in 120:
		sf.update(fc, vis, 1.0 / 60.0)
	check("airborne, the crunch dies away (gain %.3f)" % sf._gravel.gain, sf._gravel.gain < 0.01)
	check("airborne, no dust", dust == null or not dust.emitting)
	# on tarmac nothing crunches
	fc.airborne = false
	town.force_surf = Physics.SURF_TRACK
	for i in 120:
		sf.update(fc, vis, 1.0 / 60.0)
	check("tarmac: no crunch (gain %.3f)" % sf._gravel.gain, sf._gravel.gain < 0.01)
	check("the loops play on the CarFx bus (Options → Effects)", sf._gravel.player.bus == "CarFx" and sf._wind.player.bus == "CarFx")
	sf.stop_all()
	sf.queue_free()
	vis.queue_free()
	completed = true
	return errors
