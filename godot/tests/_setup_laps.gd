## Set-up lap probe (dev tool): the bots' driver alone on the circuit, the same skill every run, on the
## stock car and on each roster driver's set-up: best of three laps and time off the road.
## TRACK=gp ASSISTS=full godot --headless --path godot -s tests/_setup_laps.gd
extends SceneTree

func _lap(key: String, assists: String, setup: Dictionary) -> Array:
	var st := RaceSettings.new()
	st.track = key
	st.laps = 4
	st.opponents = 1
	st.collisions = false
	st.race_control = false
	st.ai_learning = "off"
	st.assists = assists
	st.dynamic_running = false
	st.weather = OS.get_environment("WEATHER") if OS.get_environment("WEATHER") else "dry"
	var race := Race.new(st, null, 3)
	var bot: RaceCar = race.cars.filter(func(c): return not c.is_player)[0]
	bot.skill = 0.97
	bot.mistake_rate = 0.0
	bot.wet_skill = 1.0
	bot.agg = 1.0
	race.fit_setup(bot, setup)
	race.set_autopilot(true)
	var inp := Race.PlayerInput.new()
	var off := 0.0
	var dt := 1.0 / 120.0
	while race.phase != "finished" and race.clock < 4 * race.cal.T0 * 2.0:
		race.step(dt, inp)
		if absf(bot.d) > race.track.half + 0.5:
			off += dt
	var best = null
	for t in bot.lap_times.slice(1):
		best = t if best == null else minf(best, t)
	race.dispose()
	return [best, off]

func _initialize() -> void:
	Brain.use_disk = false
	var key := OS.get_environment("TRACK") if OS.get_environment("TRACK") else "gp"
	var assists := OS.get_environment("ASSISTS") if OS.get_environment("ASSISTS") else "full"
	var ref := _lap(key, assists, {})
	print("%-20s %s  off %.1f s" % ["stock", Race.fmt_time(ref[0]), ref[1]])
	for who in Drivers.ROSTER:
		var r := _lap(key, assists, who.setup)
		print("%-20s %s  %+.2f s  off %.1f s" % [who.name, Race.fmt_time(r[0]), r[0] - ref[0] if r[0] != null and ref[0] != null else NAN, r[1]])
	quit()
