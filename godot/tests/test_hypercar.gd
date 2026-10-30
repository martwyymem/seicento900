## The Hypercar Seicento reaches Le Mans hypercar speeds on the shared physics (all-wheel drive, ~500 kW, ~340 km/h) and
## the stock Seicento stays front-wheel drive.
extends RefCounted

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
	completed = true
	return errors

func _peak_kw(m: CarModel) -> float:
	var best := 0.0
	for r in range(1000, 8200, 100):
		best = maxf(best, m.torque_at(r) * r * TAU / 60.0 * m.spec.efficiency)
	return best / 1000.0
