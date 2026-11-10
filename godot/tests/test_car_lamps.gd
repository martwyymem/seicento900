## The cars' lamp surfaces match the lights they have on (RaceCarVisual.set_lamps, from sync), for every catalogue car:
## by day the tail lamps and headlamps are off unless braking or reversing; after dark the headlamps glow with the beams
## and the tail lamps burn dimly, brighter when braking. Each car's headlamp reflector lights round its own lamp.
extends RefCounted

const VISUAL := preload("res://scripts/ui/race_car_visual.gd")

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var parent := Node3D.new()
	Engine.get_main_loop().root.add_child(parent)
	for key in CarCatalog.KEYS:
		var car: Node3D = VISUAL.new()
		car.car_key = key
		parent.add_child(car)
		_lamps(car, key)
		_centre(key)
	# a fresh visual nobody syncs (the menu car, the open world's street rivals before their first frame) shows them off
	var idle: Node3D = VISUAL.new()
	parent.add_child(idle)
	var s := _state(idle)
	check("an unsynced car's lamps are off", s.tail == 0.0 and s.bulb == 0.0 and s.glow == 0.0 and s.lit == 0.0, str(s))
	check("the headlamps follow the beams' curve", VISUAL.headlamp_level(0.0) == 0.0 and VISUAL.headlamp_level(1.0) == 1.0
		and VISUAL.headlamp_level(0.1) == 0.0 and VISUAL.headlamp_level(0.5) > 0.4)
	parent.free()
	completed = true
	return errors

func _state(car: Node3D) -> Dictionary:
	var d: MeshInstance3D = car._details_node
	return {"tail": car.tail_material.emission_energy_multiplier, "bulb": car.bulb_material.emission_energy_multiplier,
		"bulb_col": car.bulb_material.emission, "glow": float(d.get_instance_shader_parameter("glow")),
		"lit": float(d.get_instance_shader_parameter("lit"))}

func _lamps(car: Node3D, key: String) -> void:
	var rc := RaceCar.new()
	rc.control = "free"
	# through sync, as the races and the open world drive it
	rc.brake_on = false
	car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
	var s := _state(car)
	check("%s by day: tail lamps and headlamps off" % key, s.tail == 0.0 and s.bulb == 0.0 and s.glow == 0.0 and s.lit == 0.0, str(s))
	rc.brake_on = true
	car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
	s = _state(car)
	check("%s braking by day: bright brake lights, headlamps off" % key, s.tail >= 0.5 and s.bulb >= 3.0 and s.glow == 1.0 and s.lit == 0.0, str(s))
	rc.brake_on = false
	rc.rev = true
	car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
	s = _state(car)
	check("%s reversing by day: a white reversing bulb" % key, s.bulb > 1.0 and (s.bulb_col as Color).b > 0.5 and s.lit == 0.0, str(s))
	rc.rev = false
	car.sync(rc, 1.0 / 60.0, 0.0, 1.0, false)
	var night := _state(car)
	check("%s at night: headlamps glowing" % key, night.lit >= 3.0, str(night))
	check("%s at night: dim red position lights" % key, night.tail > 0.0 and night.tail < 0.3 and night.bulb > 0.2 and night.bulb < 1.5
		and night.glow > 0.1 and night.glow < 0.5 and (night.bulb_col as Color).b < 0.2, str(night))
	rc.brake_on = true
	car.sync(rc, 1.0 / 60.0, 0.0, 1.0, false)
	s = _state(car)
	check("%s braking at night: brighter than the position lights" % key, s.tail > night.tail * 3.0 and s.bulb > night.bulb * 3.0 and s.glow == 1.0 and s.lit >= 3.0, str(s))
	rc.brake_on = false
	car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
	s = _state(car)
	check("%s back to day: all off again" % key, s.tail == 0.0 and s.bulb == 0.0 and s.lit == 0.0, str(s))

## The headlamp shader's bulb sits in the car's own right-hand lamp.
func _centre(key: String) -> void:
	var sh: Dictionary = VISUAL._shared_resources(key)
	var details: Mesh = sh.details
	var surf := VISUAL._surface(details, "Headlight")
	check("%s has a Headlight surface" % key, surf >= 0)
	if surf < 0:
		return
	var mat := details.surface_get_material(surf) as ShaderMaterial
	check("%s headlamp wears car_headlamp.gdshader" % key, mat != null and mat.shader.resource_path.ends_with("car_headlamp.gdshader"))
	if mat == null:
		return
	var set_c = mat.get_shader_parameter("centre")
	var c: Vector2 = set_c if set_c is Vector2 else Vector2(0.40, 0.64) # unset: the shader's default, the Seicento's bulb
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v: Vector3 in details.surface_get_arrays(surf)[Mesh.ARRAY_VERTEX]:
		if v.x > 0.0:
			lo = lo.min(Vector2(v.x, v.y))
			hi = hi.max(Vector2(v.x, v.y))
	check("%s headlamp bulb inside its lamp" % key, c.x > lo.x and c.x < hi.x and c.y > lo.y and c.y < hi.y, "(%s in %s..%s)" % [c, lo, hi])
