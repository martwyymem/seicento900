## Godot-only race dynamics (no JS reference): the slipstream model and the per-lap tyre and fuel measurements
## that the live pit calls rely on.
extends RefCounted

var completed := false
var errors := []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	# wake: thins with distance and sideways offset, needs a leader at speed, ends beyond 60 m
	var w5 := Race.wake_strength(5.0, 0.0, 40.0)
	var w15 := Race.wake_strength(15.0, 0.0, 40.0)
	var w30 := Race.wake_strength(30.0, 0.0, 40.0)
	check("wake gets weaker with distance", w5 > w15 and w15 > w30 and w30 > 0.0, "%s %s %s" % [w5, w15, w30])
	check("wake is strong right behind", w5 > 0.8, str(w5))
	check("wake is weaker off to the side", Race.wake_strength(8.0, 1.5, 40.0) < 0.5 * Race.wake_strength(8.0, 0.0, 40.0))
	check("no wake from a slow car", Race.wake_strength(5.0, 0.0, 6.0) == 0.0)
	check("no wake beyond 60 m or from behind", Race.wake_strength(61.0, 0.0, 40.0) == 0.0 and Race.wake_strength(-5.0, 0.0, 40.0) == 0.0)

	var st := RaceSettings.new()
	st.track = "monaco"
	st.laps = 3
	st.opponents = 1
	st.race_control = false
	var race := Race.new(st, null, 1)
	var car: RaceCar = race.player
	# the tow builds up gradually, holds, then fades quickly
	var dt := 1.0 / 120.0
	var d := 1.0
	for i in 30: # 0.25 s
		d = race.tow_drag(car, 1.0, dt)
	check("tow is only part built after 0.25 s", d < 1.0 and d > 1.0 - Race.TOW_MAX + 0.05, str(d))
	for i in 90:
		d = race.tow_drag(car, 1.0, dt)
	check("full tow cuts drag by TOW_MAX", absf(d - (1.0 - Race.TOW_MAX)) < 1e-9, str(d))
	for i in 60: # 0.5 s out of the wake
		d = race.tow_drag(car, 0.0, dt)
	check("tow is lost within half a second", d == 1.0, str(d))

	# a lap's real tread and fuel use is measured, and the estimate rises faster than it falls
	car.stops = 0
	car.lap = 3
	car.obs_wear = 0.0
	car.fuel_lap = 0.0
	car.rate_mark = null
	race._observe_rates(car)
	car.lap = 4
	car.tyre.wear -= 0.10
	race.burn_fuel(car, race.fpl * 1.2)
	race._observe_rates(car)
	check("tread use measured", absf(car.obs_wear - 0.10) < 1e-9, str(car.obs_wear))
	check("fuel use measured", absf(car.fuel_lap - race.fpl * 1.2) < 1e-9, str(car.fuel_lap))
	car.lap = 5
	car.tyre.wear -= 0.05
	race.burn_fuel(car, race.fpl * 0.8)
	race._observe_rates(car)
	check("a lighter lap only nudges the tread estimate down", car.obs_wear < 0.10 and car.obs_wear > 0.08, str(car.obs_wear))
	check("a lighter lap only nudges the fuel estimate down", car.fuel_lap < race.fpl * 1.2 and car.fuel_lap > race.fpl * 1.0, str(car.fuel_lap))
	car.stops = 1 # after a stop the old marks say nothing about the new tyres
	car.lap = 6
	var before := car.obs_wear
	car.tyre.wear -= 0.5
	race._observe_rates(car)
	check("a lap that included a stop is not measured", car.obs_wear == before, str(car.obs_wear))
	check("refuelling uses the measured fuel per lap", race.car_fpl(car) == car.fuel_lap)
	# a lap on the save mix burns less, but is measured as what the normal mix would have used, so
	# switching mixes doesn't read as the car's consumption changing
	var measured := car.fuel_lap
	car.lap = 7
	car.rate_mark = null
	race._observe_rates(car)
	car.lap = 8
	race.set_mix(car, "save")
	race.burn_fuel(car, measured * Strategy.mix_fuel(race.cal, "save"))
	race._observe_rates(car)
	race.set_mix(car, "normal")
	check("a save-mix lap is measured at its normal-mix equivalent", absf(car.fuel_lap - measured) < 1e-9, "%f vs %f" % [car.fuel_lap, measured])
	st.dynamic_running = false
	check("with live running off the calibrated fuel figure is used", race.car_fpl(car) == race.fpl)

	# the safety-car delta: a moment over it at each braking zone of a long safety-car period does not add up
	# to a penalty, staying over it does
	var sct := RaceSettings.new()
	sct.track = "monaco"
	sct.laps = 3
	sct.opponents = 1
	var scr := Race.new(sct, null, 1)
	var rc := scr.rc
	var p := scr.player
	scr.phase = "racing"
	rc.flag = "sc"
	p.control = "free"
	var lim := rc.speed_cap(p)
	check("the safety car caps your speed", lim > 0.0, str(lim))
	var fwd := Vector2(cos(scr.track.heading(p.s)), sin(scr.track.heading(p.s)))
	for k in 120 * 120: # two minutes: half a second over the delta every six seconds
		var v := lim + 3.0 if k % 720 < 60 else lim * 0.8
		p.vx = fwd.x * v
		p.vy = fwd.y * v
		rc._player_rules(dt)
	check("brief moments over the delta are not penalised", p.penalties.is_empty(), str(p.penalties))
	p.vx = fwd.x * (lim + 3.0)
	p.vy = fwd.y * (lim + 3.0)
	for k in 120 * 5:
		rc._player_rules(dt)
	check("staying over the delta is penalised", p.penalties.size() == 1, str(p.penalties))

	# a race where every car retires before anyone takes the flag still ends (it used to run forever)
	var sto := RaceSettings.new()
	sto.track = "monaco"
	sto.laps = 2
	sto.opponents = 2
	var out := Race.new(sto, null, 3)
	var idle := Race.PlayerInput.new()
	while out.phase != "racing":
		out.step(1.0 / 120.0, idle)
	for c in out.cars:
		c.dnf = true
		c.dnf_reason = "Out of fuel"
	out.step(1.0 / 120.0, idle)
	check("a race with every car out is over", out.phase == "finished", out.phase)
	check("...and classifies every car", out.results().size() == 3)

	# retiring on the grid, before the lights go out, projects a finish with real times (it gave NaN)
	var grid := Race.new(sto, null, 4)
	for k in 60:
		grid.step(1.0 / 120.0, idle)
	grid.player.dnf = true
	grid.approximate_finish()
	check("a race called off on the grid has a finite clock", is_finite(grid.race_time) and grid.race_time >= 0.0, str(grid.race_time))
	var finite_totals := true
	for r in grid.results():
		if r.total != null and not is_finite(float(r.total)):
			finite_totals = false
	check("...and finite finishing times", finite_totals and grid.phase == "finished")

	# a bot wedged facing the wrong way under the safety car is put back (two of them nose to nose against
	# the wall at Sainte Dévote used to hold the whole field there for good)
	var stw := RaceSettings.new()
	stw.track = "monaco"
	stw.laps = 3
	stw.opponents = 2
	var wed := Race.new(stw, null, 5)
	while wed.race_time < 8.0:
		wed.step(1.0 / 120.0, idle)
	var b: RaceCar = wed.cars[0] if not wed.cars[0].is_player else wed.cars[1]
	var at := wed.track.pos(216.0, 4.3)
	b.s = 216.0
	b.d = 4.3
	b.x = at[0]
	b.y = at[1]
	b.heading = wed.track.heading(216.0) + 2.56
	b.vx = 0.0
	b.vy = 0.0
	b.yaw_rate = 0.0
	b.v = 0.0
	b.phys = null
	wed.rc.deploy_sc("test")
	var turned_back := false
	for k in 120 * 14:
		wed.step(1.0 / 120.0, idle)
		if absf(SimUtil.wrap_angle(b.heading - wed.track.heading(b.s))) < 1.0:
			turned_back = true
			break
	check("a bot wedged facing the wrong way under the safety car is put back", turned_back,
		"(heading off %.2f, s %.0f)" % [absf(SimUtil.wrap_angle(b.heading - wed.track.heading(b.s))), b.s])

	# reversing: the brake pedal drives backwards, the throttle slows the car (it used to speed it up too)
	race.phase = "racing"
	var rcar: RaceCar = race.player
	var v_thr := 0.0
	var v_brk := 0.0
	for pedal in 2:
		rcar.rev = true
		rcar.gear = 0
		rcar.heading = 0.0
		rcar.vx = -5.0
		rcar.vy = 0.0
		for k in 60:
			race.step_free(rcar, 1.0 / 120.0, 1.0 if pedal == 0 else 0.0, 0.0 if pedal == 0 else 1.0, 0.0, null)
		if pedal == 0:
			v_thr = rcar.vx
		else:
			v_brk = rcar.vx
	check("throttle in reverse slows the car", v_thr > -5.0, str(v_thr))
	check("brake in reverse speeds the car backwards", v_brk < -5.0, str(v_brk))

	race.dispose()
	scr.dispose()
	out.dispose()
	grid.dispose()
	wed.dispose()
	completed = true
	return errors
