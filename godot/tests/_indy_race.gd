## Full Indianapolis fuel race (12 laps, fuel ×15) on autopilot: strategies, stops, fuel left, results.
extends SceneTree
func _init():
	Brain.use_disk = false
	var st := RaceSettings.new()
	st.track = "indy"
	st.laps = 12
	st.wear_mult = 1.0
	st.fuel_mult = 15.0
	st.bot_physics = OS.get_environment("BOTPHYS") if OS.get_environment("BOTPHYS") != "" else "off"
	var seed_ := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	var race := Race.new(st, null, seed_)
	var inp := Race.PlayerInput.new()
	race.set_autopilot(true)
	var ticks := 0
	var mix_t := {}
	var min_fuel := {}
	while race.phase != "finished" and ticks < 120 * 3600:
		race.step(1.0 / 120.0, inp)
		ticks += 1
		if race.phase == "racing":
			for c in race.cars:
				if c.mode == "race" and not c.finished:
					var k: String = c.name
					if not mix_t.has(k):
						mix_t[k] = {"save": 0.0, "normal": 0.0}
					mix_t[k][c.mix] += 1.0 / 120.0
					min_fuel[k] = minf(min_fuel.get(k, 99.0), c.fuel)
	print("sim %.0f s, phase %s" % [ticks / 120.0, race.phase])
	for r in race.results():
		var c: RaceCar = r.car
		var m: Dictionary = mix_t.get(c.name, {})
		print("%2d %-22s %-34s stops %d %s %s save %3.0f%% minfuel %.1f fpl %.2f" % [r.pos, c.name, c.strategy_label, c.stops, Race.fmt_time(r.total), r.status,
			100.0 * m.get("save", 0.0) / maxf(1.0, m.save + m.normal), min_fuel.get(c.name, 0.0), c.fuel_lap])
	for e in race.events:
		if e.kind in ["warn", "bad"] or "fuel" in e.text:
			print("  [%s] t=%.0f %s" % [e.kind, e.t, e.text])
	quit()
