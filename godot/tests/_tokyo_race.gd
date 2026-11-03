## Probe (headless): one lap of Tokyo C1 against 11 hard bots, as campaign stage 9, the player on autopilot. Prints
## each car's time, retirements, crash counts, and the player's speed through each named section (the spiral above all).
##   godot --headless --path godot -s tests/_tokyo_race.gd    (env: LAPS 1, OPP 11, DIFF hard, BOTPHYS on, SEED 7)
extends SceneTree

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _init():
	Brain.use_disk = false
	var st := RaceSettings.new()
	st.track = "tokyo"
	st.laps = int(_env("LAPS", "1"))
	st.opponents = int(_env("OPP", "11"))
	st.difficulty = _env("DIFF", "hard")
	st.grid = "pole"
	st.start_hour = 0.0
	st.wear_mult = 2.0
	st.bot_physics = _env("BOTPHYS", "on")
	var race := Race.new(st, null, int(_env("SEED", "7")))
	var inp := Race.PlayerInput.new()
	race.set_autopilot(true)
	var tr: Track = race.track
	var ticks := 0
	var player: RaceCar = race.cars[0]
	for c in race.cars:
		if c.is_player:
			player = c
	var sec_speed := {} # section name -> [sum km/h, samples, min km/h]
	var stuck := {}
	while race.phase != "finished" and ticks < 120 * 1800:
		race.step(1.0 / 120.0, inp)
		ticks += 1
		if race.phase == "racing" and ticks % 12 == 0:
			var nm := tr.sector_name(player.s)
			var v: float = sqrt(player.vx * player.vx + player.vy * player.vy) * 3.6
			if not sec_speed.has(nm):
				sec_speed[nm] = [0.0, 0, 999.0]
			sec_speed[nm][0] += v
			sec_speed[nm][1] += 1
			sec_speed[nm][2] = minf(sec_speed[nm][2], v)
			for c in race.cars:
				if not c.finished and not c.dnf and sqrt(c.vx * c.vx + c.vy * c.vy) < 2.0:
					stuck[c.name] = stuck.get(c.name, 0) + 1
	print("sim %.0f s, phase %s, lap %.0f m" % [ticks / 120.0, race.phase, tr.L])
	for r in race.results():
		var c: RaceCar = r.car
		print("  %-22s %s laps %d %s  stopped %.0f s" % [c.name, "DNF" if c.dnf else "   ", r.laps,
			("%.1f s" % r.total) if r.total != null else "-", stuck.get(c.name, 0) / 10.0])
	print("player by section (mean / min km/h):")
	for e in tr.sectors:
		var nm: String = e[1]
		if sec_speed.has(nm):
			print("  %-22s %5.0f %5.0f" % [nm, sec_speed[nm][0] / sec_speed[nm][1], sec_speed[nm][2]])
	quit()
