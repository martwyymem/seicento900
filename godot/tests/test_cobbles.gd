## Cobbled stretches (TrackDef.cobbles) have their own surface with less grip, the same for the player and the
## AI, and tracks without cobbles are untouched.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

## Straight-line full braking from 25 m/s on a flat surface: {dist (m to a stop), lat (peak lateral acceleration
## in a held steering lock at 28 m/s)}.
func _drive(race: Race, surf: int) -> Dictionary:
	var car: RaceCar = race.player
	var env := Physics.Env.new()
	env.surface = func(_x: float, _y: float) -> int: return surf
	env.mass = car.model.mass_with_fuel(car.fuel)
	env.abs_on = true
	env.tc_on = true
	env.esc_on = false
	var ctl := Physics.Controls.new()
	var dt := 1.0 / 120.0
	_reset(car, 25.0)
	var dist := 0.0
	for k in 120 * 12:
		ctl.throttle = 0.0
		ctl.brake = 1.0
		car.physics.step(car, ctl, env, dt)
		dist += car.vx * dt
		if car.vx < 0.5:
			break
	_reset(car, 28.0)
	var lat := 0.0
	for k in 120 * 3:
		ctl.throttle = 0.5
		ctl.brake = 0.0
		ctl.steer = 0.3
		car.physics.step(car, ctl, env, dt)
		if k > 60:
			lat = maxf(lat, absf(car.phys.ay_f))
	return {"dist": dist, "lat": lat}

func _reset(car: RaceCar, v: float) -> void:
	car.phys = null
	car.rev = false
	car.gear = 3
	car.heading = 0.0
	car.vx = v
	car.vy = 0.0
	car.yaw_rate = 0.0
	car.x = 0.0
	car.y = 0.0

func run() -> Array:
	check("cobble grip is one tunable below tarmac", Physics.COBBLE_GRIP < 1.0 and Physics.SURF_GRIP[Physics.SURF_COBBLE] == Physics.COBBLE_GRIP)
	var st := RaceSettings.new()
	st.track = "krakow"
	st.opponents = 2
	st.race_control = false
	var race := Race.new(st, null, 1)
	var cob: PackedVector2Array = race.track.cfg.cobbles
	check("krakow has a cobbled stretch", cob.size() > 0)
	if cob.size() > 0:
		var mid := (cob[0].x + cob[0].y) * 0.5
		for car in [race.player, race.cars[1]]:
			car.s = mid
			car.d = 0.0
			var inside := race.surface_at(car, car.x, car.y)
			check("cobbles are tagged for car %d" % car.id, inside == Physics.SURF_COBBLE, "(%d)" % inside)
			car.s = cob[0].x - 30.0
			check("tarmac before the cobbles for car %d" % car.id, race.surface_at(car, car.x, car.y) == Physics.SURF_TRACK)
			car.s = mid
			car.d = race.track.half + 6.0
			check("off the road is not cobble for car %d" % car.id, race.surface_at(car, car.x, car.y) != Physics.SURF_COBBLE)
	var tar := _drive(race, Physics.SURF_TRACK)
	var set := _drive(race, Physics.SURF_COBBLE)
	check("braking takes longer on setts", set.dist > tar.dist * 1.05, "(%.1f vs %.1f m)" % [set.dist, tar.dist])
	check("lateral grip is lower on setts", set.lat < tar.lat * 0.95, "(%.2f vs %.2f m/s2)" % [set.lat, tar.lat])
	race.dispose()
	# a track with no cobbles never reports the surface
	st.track = "gp"
	var gp := Race.new(st, null, 1)
	check("gp has no cobbles", gp.track.cfg.cobbles.is_empty())
	for s in [0.0, 500.0, 1500.0]:
		gp.player.s = s
		gp.player.d = 0.0
		check("gp stays plain track at %d" % s, gp.surface_at(gp.player, gp.player.x, gp.player.y) == Physics.SURF_TRACK)
	gp.dispose()
	print("  cobbles: tarmac brake %.1f m / %.2f lat, setts %.1f m / %.2f lat" % [tar.dist, tar.lat, set.dist, set.lat])
	completed = true
	return errors
