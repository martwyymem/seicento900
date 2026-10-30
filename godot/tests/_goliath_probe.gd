## Headless probe: builds the Goliath and runs a one-lap hypercar race on it with the player on autopilot.
extends SceneTree

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var def := Track.load_def("goliath")
	var tr := Track.new(def)
	print("goliath: n %d, L %.0f m, built in %d ms" % [tr.n, tr.L, Time.get_ticks_msec() - t0])
	for cls in ["hypercar", "stock"]:
		var rs := RaceSettings.new()
		rs.track = "goliath"
		rs.laps = 1
		rs.opponents = 5
		rs.car_class = cls
		rs.race_control = false
		var cm: CarModel = Hypercar.model() if cls == "hypercar" else CarModel.new()
		t0 = Time.get_ticks_msec()
		var r := Race.new(rs, {"stints": [{"c": "M", "laps": 1}]}, 7, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})
		print("  %s race set up in %d ms" % [cls, Time.get_ticks_msec() - t0])
		var idle := Race.PlayerInput.new()
		r.set_autopilot(true)
		var ticks := 0
		var top := 0.0
		t0 = Time.get_ticks_msec()
		while r.phase != "finished" and ticks < 60 * 1800:
			r.step(1.0 / 60.0, idle)
			top = maxf(top, r.player.v)
			ticks += 1
		var times := []
		for c in r.cars:
			times.append("%s" % ("%.0f" % float(c.finish_time) if c.finish_time != null else "DNF"))
		print("  %s: phase %s, %.0f s simulated in %d ms, top %.0f km/h, finish times %s" % [cls, r.phase, ticks / 60.0, Time.get_ticks_msec() - t0, top * 3.6, times])
		r.dispose()
	quit()
