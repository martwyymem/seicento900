extends SceneTree
## Headless qualifying run: godot --headless --path godot -s tests/smoke_quali.gd -- [track] [pole|bots]
## The co-driver drives the timed laps; prints the sheet and the grid a race would take from it.
func _init():
	Brain.use_disk = false
	var args := OS.get_cmdline_user_args()
	var st := RaceSettings.new()
	st.track = args[0] if args.size() > 0 else "gp"
	st.opponents = 15
	Qualifying.configure(st)
	var race := Race.new(st, null, 4242)
	print("coach scale %.4f" % Qualifying.coach_scale(race))
	print("track %s T0 %.1f s, %d timed laps, quali fuel %.1f L, tyre %s" % [st.track, race.cal.T0, race.R - 1, race.quali_fuel, race.quali_compound()])
	var inp := Race.PlayerInput.new()
	race.set_autopilot(true)
	var t0 := Time.get_ticks_msec()
	var ticks := 0
	while race.phase != "finished" and ticks < 120 * 1800:
		race.step(1.0 / 120.0, inp)
		ticks += 1
	print("sim %.0f s in %d ms, phase %s, laps %s, best %s" % [ticks / 120.0, Time.get_ticks_msec() - t0, race.phase, race.player.lap_times.map(func(x): return "%.2f" % x), race.player.best_lap])
	var rows := Qualifying.sheet(race)
	for r in rows:
		print("%2d #%-2d %-24s %s  %s  %s%s" % [r.pos, r.number, r.name, Race.fmt_time(r.time), ("+%.3f" % r.gap) if r.gap != null else "", ("%.1f km/h" % r.speed) if r.speed != null else "", "  <-- you" if r.is_player else ""])
	var grid := Qualifying.grid_from(race, rows)
	var st2 := RaceSettings.new()
	st2.track = st.track
	st2.opponents = 15
	st2.quali_grid = grid
	var race2 := Race.new(st2, null, 99)
	print("race grid: ", race2.cars.map(func(c): return "%d:%s" % [c.grid, c.name.split(" ")[-1] if not c.is_player else "YOU"]))
	quit()
