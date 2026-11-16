## The Hypercar Seicento reaches Le Mans hypercar speeds on the shared physics (all-wheel drive, ~500 kW, ~340 km/h) and
## the stock Seicento stays front-wheel drive. It is also friendly on a keyboard (user, 2026-11-13: "drivable and doesn't
## crash you into a wall when you brake"): full braking from any speed stays straight and settles a disturbance, in the
## race physics and in the open world's FreeCar alike (the manoeuvres of tests/_hypercar_feel_probe.gd).
extends RefCounted

const Probe := preload("res://tests/_hypercar_feel_probe.gd")
const DT := 1.0 / 120.0

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var m := Hypercar.model()
	check("the hypercar drives all four wheels", m.spec.awd)
	check("the stock Seicento is front-wheel drive", not CarModel.new().spec.awd)
	var stock := CarModel.new()
	check("the hypercar is as light and as small as the Seicento", m.base_mass() == stock.base_mass() and m.spec.length == stock.spec.length and m.spec.width == stock.spec.width
		and m.spec.wheelbase == stock.spec.wheelbase and m.spec.wheel_radius == stock.spec.wheel_radius)
	check("it has a Ferrari 499P's power: 450-550 kW at the wheels", _peak_kw(m) > 450.0 and _peak_kw(m) < 550.0, str(_peak_kw(m)))
	var st := RaceSettings.new()
	st.track = "gp"
	st.opponents = 1
	st.race_control = false
	var race := Race.new(st, null, 1, {"car_model": m})
	var car: RaceCar = race.player
	car.phys = null
	car.rev = false
	car.gear = 0
	car.heading = 0.0
	car.vx = 0.0
	car.vy = 0.0
	car.yaw_rate = 0.0
	car.fuel = 20.0
	var env := Physics.Env.new()
	env.surface = func(_x: float, _y: float) -> int: return Physics.SURF_ASPHALT
	env.mass = m.mass_with_fuel(car.fuel)
	var ctl := Physics.Controls.new()
	ctl.throttle = 1.0
	var dt := 1.0 / 120.0
	var t100 := -1.0
	var t300 := -1.0
	for k in 120 * 40:
		race.auto_shift(car, car.vx * cos(car.heading) + car.vy * sin(car.heading), 1.0, 0.0)
		car.physics.step(car, ctl, env, dt)
		car.shift_t = maxf(0.0, car.shift_t - dt)
		car.hold_t = maxf(0.0, car.hold_t - dt)
		var kmh := sqrt(car.vx * car.vx + car.vy * car.vy) * 3.6
		if t100 < 0.0 and kmh >= 100.0:
			t100 = k * dt
		if t300 < 0.0 and kmh >= 300.0:
			t300 = k * dt
	var top := sqrt(car.vx * car.vx + car.vy * car.vy) * 3.6
	check("0-100 km/h in under 3 s", t100 > 0.0 and t100 < 3.0, "(%.1f s)" % t100)
	check("300 km/h within 20 s", t300 > 0.0 and t300 < 20.0, "(%.1f s)" % t300)
	check("top speed 330-360 km/h", top > 330.0 and top < 360.0, "(%.0f km/h)" % top)
	check("the car stays straight", absf(car.heading) < 0.05 and absf(car.vy) < 1.0, "(heading %.2f)" % car.heading)
	race.dispose()
	# a whole race on it: the field finishes, and a lap is quicker than the stock car's
	var lap := {}
	var vmax := {}
	for cls in ["stock", "hypercar"]:
		var rs := RaceSettings.new()
		rs.track = "gp"
		rs.laps = 1
		rs.opponents = 3
		rs.car_class = cls
		rs.race_control = false
		var cm: CarModel = Hypercar.model() if cls == "hypercar" else CarModel.new()
		var r := Race.new(rs, {"stints": [{"c": "M", "laps": 1}]}, 7, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})
		var idle := Race.PlayerInput.new()
		r.set_autopilot(true)
		var ticks := 0
		var top_v := 0.0
		while r.phase != "finished" and ticks < 120 * 600:
			r.step(1.0 / 60.0, idle)
			top_v = maxf(top_v, r.player.v)
			ticks += 1
		vmax[cls] = top_v * 3.6
		check("a %s race finishes" % cls, r.phase == "finished", "(phase %s after %d ticks)" % [r.phase, ticks])
		lap[cls] = float(r.player.finish_time) if r.player.finish_time != null else INF
		r.dispose()
	check("a hypercar race is no slower, and the car really is quicker on the straights", lap.hypercar <= lap.stock and vmax.hypercar > vmax.stock * 1.3,
		"(%.0f s vs %.0f s, top %.0f vs %.0f km/h)" % [lap.hypercar, lap.stock, vmax.hypercar, vmax.stock])
	_stability(m)
	completed = true
	return errors

## Full brake in one frame from kmh to a stop. yaw0, vy0: a disturbance at the start; tap: the steering key held this long
## (at the keyboard's rate); grass: the left wheels on the grass. Returns the run's Probe.Log.
func _brake(rig, kmh: float, yaw0 := 0.0, vy0 := 0.0, tap := 0.0, grass := false):
	rig.set_grass(0.0 if grass else INF)
	rig.reset(kmh / 3.6)
	rig.car.yaw_rate = yaw0
	rig.car.vy = vy0
	var lg = Probe.Log.new()
	var st := 0.0
	while rig.speed() > 0.5 and not rig.car.rev and lg.t < 30.0:
		st = move_toward(st, 1.0 if lg.t < tap else 0.0, (2.6 if lg.t < tap else 8.0) * DT)
		rig.step(0.0, 1.0, st)
		lg.take(rig)
	return lg

func _beta(rig) -> float:
	var c: RaceCar = rig.car
	return absf(atan2(-c.vx * sin(c.heading) + c.vy * cos(c.heading), maxf(absf(c.vx * cos(c.heading) + c.vy * sin(c.heading)), 0.5)))

func _stability(m: CarModel) -> void:
	var stock := CarModel.new().spec
	check("the stock Seicento keeps the shared defaults", stock.aero_front == 0.55 and stock.aero_rear == 0.45 and stock.steer_fast == 1.0
		and stock.reverse_power == 1.0 and stock.esc_grip == 1.0 and stock.esc_aero == 0.0)
	var sp := m.spec
	check("the downforce shares add up to 1", is_equal_approx(sp.aero_front + sp.aero_rear, 1.0))
	var tarmac: int = Probe.S.surf_ids().asphalt
	for path in [["race", "full"], ["race", "abs"], ["free", "abs"]]:
		var tag := "%s/%s" % [path[0], path[1]]
		var rig = Probe.Rig.new(path[0], m, path[1], tarmac)
		for kmh in [100.0, 200.0, 300.0]:
			var lg = _brake(rig, kmh)
			check("%s: full braking from %.0f km/h stays dead straight" % [tag, kmh], lg.max_y < 0.05 and lg.max_head < deg_to_rad(0.5) and lg.lock_r == 0.0,
				"(%.2f m, %.2f deg, rear locked %.2f s)" % [lg.max_y, rad_to_deg(lg.max_head), lg.lock_r])
			var lim: float = {100.0: 31.0, 200.0: 108.0, 300.0: 210.0}[kmh]
			check("%s: and it still stops hard from %.0f km/h" % [tag, kmh], lg.dist < lim, "(%.1f m, limit %.0f)" % [lg.dist, lim])
			# a yaw and a sideways shove as the brake goes on: the car settles (it used to swap ends from 200 km/h up)
			lg = _brake(rig, kmh, 0.1, 0.5)
			check("%s: disturbed braking from %.0f km/h converges" % [tag, kmh], lg.max_head < deg_to_rad(4.0) and lg.max_beta < deg_to_rad(3.0) and lg.max_y < 3.0,
				"(heading %.1f deg, slide %.1f deg, %.2f m off line)" % [rad_to_deg(lg.max_head), rad_to_deg(lg.max_beta), lg.max_y])
			# a tap on the steering key under full braking turns the car a little and no more
			lg = _brake(rig, kmh, 0.0, 0.0, 0.3)
			check("%s: a steering tap under braking from %.0f km/h does not spin it" % [tag, kmh], lg.max_beta < deg_to_rad(7.0) and lg.max_head < deg_to_rad(14.0),
				"(slide %.1f deg, heading %.1f deg)" % [rad_to_deg(lg.max_beta), rad_to_deg(lg.max_head)])
			# two wheels on the grass
			lg = _brake(rig, kmh, 0.0, 0.0, 0.0, true)
			check("%s: braking from %.0f km/h with two wheels on the grass does not spin it" % [tag, kmh], lg.max_beta < deg_to_rad(8.0) and lg.max_head < deg_to_rad(20.0),
				"(slide %.1f deg, heading %.1f deg)" % [rad_to_deg(lg.max_beta), rad_to_deg(lg.max_head)])
		rig.set_grass(INF)
		# the brake held on past the stop selects reverse: gently
		rig.reset(30.0 / 3.6)
		var back := 0.0
		var t_stop := -1.0
		var t := 0.0
		while t < 8.0 and (t_stop < 0.0 or t < t_stop + 2.5):
			rig.step(0.0, 1.0, 0.0)
			t += DT
			if t_stop < 0.0 and (rig.car.rev or rig.speed() < 0.4):
				t_stop = t
			back = maxf(back, -(rig.car.vx * cos(rig.car.heading) + rig.car.vy * sin(rig.car.heading)))
		check("%s: the brake held past a stop backs up no faster than a Seicento" % tag, back * 3.6 < 30.0 and back * 3.6 > 5.0, "(%.0f km/h after 2.5 s)" % (back * 3.6))
		# a fast bend on the steering key, then the throttle shut: the tail stays in line
		rig.reset(200.0 / 3.6)
		var lift = Probe.Log.new()
		var hold = Probe.Log.new()
		for k in int(6.0 / DT):
			var tt := k * DT
			var err: float = 200.0 / 3.6 - rig.speed()
			rig.step(clampf(0.3 + err * 0.6, 0.0, 1.0) if tt < 3.0 else 0.0, 0.0, minf(1.0, tt * 2.6))
			if tt < 3.0:
				hold.take(rig)
			else:
				lift.take(rig)
		check("%s: the steering key held in a 200 km/h bend does not slide the tail out" % tag, hold.max_beta < deg_to_rad(8.0), "(%.1f deg)" % rad_to_deg(hold.max_beta))
		check("%s: lifting off in that bend does not spin it" % tag, lift.max_beta < deg_to_rad(8.0), "(%.1f deg)" % rad_to_deg(lift.max_beta))
		# a quick left-right on the keys at 250 km/h: the car recovers by itself
		rig.reset(250.0 / 3.6)
		var lane = Probe.Log.new()
		var st := 0.0
		for k in int(4.0 / DT):
			var tt := k * DT
			var want := 1.0 if tt < 0.35 else (-1.0 if tt < 0.7 else 0.0)
			st = move_toward(st, want, (8.0 if (want == 0.0 or signf(want) != signf(st)) else 2.6) * DT)
			var err: float = 250.0 / 3.6 - rig.speed()
			rig.step(clampf(0.3 + err * 0.6, 0.0, 1.0), 0.0, st)
			lane.take(rig)
		check("%s: a lane change on the keys at 250 km/h recovers" % tag, lane.max_beta < deg_to_rad(8.0) and absf(rig.car.yaw_rate) < 0.02 and _beta(rig) < deg_to_rad(0.5)
			and absf(rig.car.heading) < deg_to_rad(8.0), "(slide %.1f deg; 3 s on: yaw %.3f rad/s, slide %.2f deg, heading %.1f deg)" % [
			rad_to_deg(lane.max_beta), rig.car.yaw_rate, rad_to_deg(_beta(rig)), rad_to_deg(rig.car.heading)])
		# full throttle from rest with the steering key held: it turns, it does not spin
		rig.reset(0.0)
		var go = Probe.Log.new()
		st = 0.0
		for k in int(4.0 / DT):
			st = move_toward(st, 1.0 if k * DT < 1.5 else 0.0, (4.4 if k * DT < 1.5 else 8.0) * DT)
			rig.step(1.0, 0.0, st)
			go.take(rig)
		check("%s: flat out from rest on full lock, then straight: no spin" % tag, go.max_beta < deg_to_rad(20.0) and _beta(rig) < deg_to_rad(1.0) and absf(rig.car.yaw_rate) < 0.15,
			"(slide %.1f deg, end %.1f deg, yaw %.2f rad/s)" % [rad_to_deg(go.max_beta), rad_to_deg(_beta(rig)), rig.car.yaw_rate])

func _peak_kw(m: CarModel) -> float:
	var best := 0.0
	for r in range(1000, 8200, 100):
		best = maxf(best, m.torque_at(r) * r * TAU / 60.0 * m.spec.efficiency)
	return best / 1000.0
