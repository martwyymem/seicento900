## The open world's fan-level modifiers (CarMods): each unlocks at its level, and the physics ones change the car.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	FanLevels.dev_unlock = false
	var levels := []
	for m in CarMods.LIST:
		levels.append(m[1])
		check("%s unlocks at its level" % m[0], not CarMods.unlocked(m[0], FanLevels.THRESHOLDS[m[1] - 2])
			and CarMods.unlocked(m[0], FanLevels.THRESHOLDS[m[1] - 1]))
	check("one modifier per level from 2 to 9", levels == [2, 3, 4, 5, 6, 7, 8, 9])
	var on := {"moon": true, "nitro": true, "nonsense": true}
	check("only unlocked modifiers are active", CarMods.active(on, FanLevels.THRESHOLDS[4]).keys() == ["moon"])
	FanLevels.dev_unlock = true
	check("the dev unlock opens them all", CarMods.active(on, 0).size() == 2)
	FanLevels.dev_unlock = false

	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	var stock := _brake_distance(map, {})
	var ice := _brake_distance(map, {"ice": true})
	check("the ice rink stops the car far later", ice > stock * 2.0, "(%.1f m dry, %.1f m ice)" % [stock, ice])
	var normal_air := _air_time(map, {})
	var moon_air := _air_time(map, {"moon": true})
	check("moon gravity floats a jump several times longer", moon_air > normal_air * 4.0, "(%.2f s, %.2f s)" % [normal_air, moon_air])
	var fc := FreeCar.new(map)
	CarMods.apply_to(fc, {"drift": true})
	check("drift king loosens the rear and maxes the drift assist", fc.rear_grip < 1.0 and fc.drift_king)
	CarMods.apply_to(fc, {"monster": true})
	check("a monster truck shrugs off a traffic car", fc.monster)
	CarMods.apply_to(fc, {})
	check("switching them off restores the stock car", fc.rear_grip == 1.0 and fc.grip_mul == 1.0 and fc.grav_mul == 1.0 and not fc.drift_king and not fc.monster)
	var dry := _top_speed_after(map, 1.0)
	var boosted := _top_speed_after(map, CarMods.NITRO_POWER)
	check("nitrous pulls harder", boosted > dry * 1.08, "(%.1f vs %.1f km/h after 4 s)" % [dry, boosted])

	# in a race: the player's car only, and nothing changes without modifiers (Race.set_mods)
	var rs := RaceSettings.new()
	rs.track = "gp"
	rs.laps = 1
	rs.opponents = 1
	rs.race_control = false
	var race := Race.new(rs, {"stints": [{"c": "M", "laps": 1}]}, 3)
	check("a race starts without modifiers", race.mods.is_empty())
	race.set_mods({"ice": true, "moon": true, "drift": true, "nitro": true, "monster": true})
	var env := Physics.Env.new()
	env.mu = 1.0
	env.gx = 1.0
	env.power = 1.0
	var inp := Race.PlayerInput.new()
	inp.nitro = true
	race._ctl.throttle = 1.0
	race._apply_mods(race.player, env, inp, 0.1)
	check("race modifiers change the player's car", env.mu == CarMods.ICE_GRIP and env.gx == CarMods.MOON_GRAVITY
		and env.rear_grip == CarMods.DRIFT_REAR_GRIP and env.power == CarMods.NITRO_POWER and race.nitro < 1.0 and race.nitro_burning)
	check("a monster truck grips on the grass in a race", race.surface_at(race.player, race.player.x + 200.0, race.player.y + 200.0) == Physics.SURF_TRACK)
	race.dispose()

	var vis = load("res://scripts/ui/race_car_visual.tscn").instantiate()
	Engine.get_main_loop().root.add_child(vis)
	vis.set_wheel_scale(CarMods.MONSTER_WHEELS)
	var lifted: float = vis.body_pivot.position.y
	var wheel_y: float = vis.steer_pivots[0].position.y
	check("monster wheels lift the body and still touch the ground", lifted > 0.2
		and absf(wheel_y - vis.WHEEL_RADIUS * CarMods.MONSTER_WHEELS) < 1e-4)
	vis.set_wheel_scale(1.0)
	check("stock wheels put the body back", vis.body_pivot.position.y == 0.0 and vis.steer_pivots[0].scale == Vector3.ONE)
	vis.queue_free()
	completed = true
	return errors

func _start(map: TownMap, on: Dictionary) -> FreeCar:
	var fc := FreeCar.new(map)
	var sp: Array = map.spots["industrial_sprint"]
	fc.place(Vector2(sp[0], sp[1]), float(sp[2]))
	CarMods.apply_to(fc, on)
	return fc

## Metres from 60 km/h to a stop with the brake held (ABS on).
func _brake_distance(map: TownMap, on: Dictionary) -> float:
	var fc := _start(map, on)
	fc.car.vx = cos(fc.car.heading) * 60.0 / 3.6
	fc.car.vy = sin(fc.car.heading) * 60.0 / 3.6
	fc.car.speed = 60.0 / 3.6
	var p0 := Vector2(fc.car.x, fc.car.y)
	for i in 120 * 20:
		fc.step(1.0 / 120.0, 0.0, 1.0, 0.0)
		if Vector2(fc.car.vx, fc.car.vy).length() < 0.5:
			break
	return Vector2(fc.car.x, fc.car.y).distance_to(p0)

## km/h after 4 s of full throttle from a standstill with the engine at this output.
func _top_speed_after(map: TownMap, power: float) -> float:
	var fc := _start(map, {})
	fc.power_mul = power
	for i in 120 * 4:
		fc.step(1.0 / 120.0, 1.0, 0.0, 0.0)
	return fc.speed_kmh()

## Seconds in the air after a 3 m/s hop.
func _air_time(map: TownMap, on: Dictionary) -> float:
	var fc := _start(map, on)
	fc.airborne = true
	fc.vz = 3.0
	for i in 120 * 20:
		fc.step(1.0 / 120.0, 0.0, 0.0, 0.0)
		if not fc.airborne:
			break
	return fc.last_air
