extends SceneTree
func _init():
	Brain.use_disk = false
	var st := RaceSettings.new()
	st.laps = 2
	var t0 := Time.get_ticks_msec()
	var race := Race.new(st, null, 12345)
	print("race built in ", Time.get_ticks_msec() - t0, " ms; cars ", race.cars.size())
	var inp := Race.PlayerInput.new()
	race.set_autopilot(true)
	t0 = Time.get_ticks_msec()
	var ticks := 0
	while race.phase != "finished" and ticks < 120 * 900:
		race.step(1.0 / 120.0, inp)
		ticks += 1
	print("sim %.0f s in %d ms, phase %s" % [ticks / 120.0, Time.get_ticks_msec() - t0, race.phase])
	for r in race.results():
		print("%2d %-24s laps %d %s best %s %s" % [r.pos, r.car.name, r.laps, Race.fmt_time(r.total), Race.fmt_time(r.car.best_lap), r.status])
	for e in race.events.slice(-12):
		print("  [%s] %s" % [e.kind, e.text])
	quit()
