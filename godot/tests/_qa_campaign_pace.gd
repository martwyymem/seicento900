## QA probe (headless): races campaign stages with the co-driver (autopilot) driving the player and prints the
## grid, the field's skills and the player's position lap by lap.
## STAGES=6,7,8 SEEDS=3 godot --headless --path godot -s tests/_qa_campaign_pace.gd
extends SceneTree

func _initialize() -> void:
	Brain.use_disk = false
	var stages := (OS.get_environment("STAGES") if OS.get_environment("STAGES") != "" else "6,7,8").split(",")
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 3
	var diff_over := OS.get_environment("DIFF")
	for si in stages:
		var st: Dictionary = Campaign.get_stage(int(si))
		for seed in seeds:
			var s := RaceSettings.new()
			s.track = st.track
			s.laps = st.laps
			s.weather = st.weather
			s.opponents = st.opponents
			s.difficulty = diff_over if diff_over != "" else st.difficulty
			s.start_hour = st.start_hour
			s.wear_mult = st.wear_mult
			s.fuel_mult = st.fuel_mult
			s.grid = st.grid
			s.player_name = "PLAYER"
			var race := Race.new(s, null, 1000 + seed)
			race.set_autopilot(true)
			var line := []
			for c in race.cars:
				line.append("%s%s(%.3f)" % ["*" if c.is_player else "", c.name.get_slice(" ", 1) if not c.is_player else "YOU", c.skill])
			print("STAGE %s %s %s grid %s seed %d target P%d" % [si, st.track, s.difficulty, s.grid, seed, st.target_pos])
			print("  grid: ", " ".join(line))
			var inp := Race.PlayerInput.new()
			var ticks := 0
			var last_lap := -1
			var trace := []
			while race.phase != "finished" and ticks < 120 * 1500:
				race.step(1.0 / 120.0, inp)
				ticks += 1
				var p: RaceCar = race.player
				if p.lap != last_lap:
					last_lap = p.lap
					var pos: int = race.order.find(p) + 1
					trace.append("L%d:P%d" % [p.lap, pos])
			var res: Array = race.results()
			var ppos := 0
			for r in res:
				if r.car.is_player:
					ppos = r.pos
			var top := []
			for r in res.slice(0, 4):
				top.append("%s %s best %s" % [r.pos, "YOU" if r.car.is_player else r.car.name.get_slice(" ", 1), Race.fmt_time(r.car.best_lap)])
			var pbest := Race.fmt_time(race.player.best_lap)
			print("  laps: ", " ".join(trace), "  -> finish P%d (%s), player best %s, sim %.0fs" % [ppos, "OK" if ppos <= st.target_pos else "FAIL", pbest, ticks / 120.0])
			print("  top: ", " | ".join(top))
	quit()
