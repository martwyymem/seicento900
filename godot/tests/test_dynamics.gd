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
	car.fuel -= race.fpl * 1.2
	race._observe_rates(car)
	check("tread use measured", absf(car.obs_wear - 0.10) < 1e-9, str(car.obs_wear))
	check("fuel use measured", absf(car.fuel_lap - race.fpl * 1.2) < 1e-9, str(car.fuel_lap))
	car.lap = 5
	car.tyre.wear -= 0.05
	car.fuel -= race.fpl * 0.8
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
	completed = true
	return errors
