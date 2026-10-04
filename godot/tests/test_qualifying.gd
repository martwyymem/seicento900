## Qualifying: the session setup, the time sheet and the grid it hands to the race.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	var st := RaceSettings.new()
	st.track = "gp"
	st.opponents = 15
	Qualifying.configure(st)
	var q := Race.new(st, null, 31)

	if q.cars.size() != 1 or not q.cars[0].is_player:
		errors.append("qualifying should put only the player on the circuit, got %d cars" % q.cars.size())
	if q.quali_bots.size() != 15 or q.quali_times.size() != 15:
		errors.append("the field should have 15 times on the sheet, got %d/%d" % [q.quali_bots.size(), q.quali_times.size()])
	if q.R != 1 + Qualifying.timed_laps(q.cal.T0):
		errors.append("an out lap plus the timed laps expected, got R=%d" % q.R)
	if q.rc != null or q.brain != null:
		errors.append("qualifying runs without race control or AI learning")
	if q.player.tyre.c != "S":
		errors.append("dry qualifying runs on softs, got %s" % q.player.tyre.c)
	if Qualifying.timed_laps(744.0) != 1 or Qualifying.timed_laps(100.0) != 2:
		errors.append("a long circuit gets one timed lap, a short one two")

	# the interpolated times match a full simulated lap per driver
	for b in q.quali_bots:
		var exact := Qualifying.bot_time(q, Qualifying.lap_time(q, b.quali), b.quali, Qualifying.lap_time(q, 1.0), Qualifying.coach_scale(q))
		if absf(q.quali_times[b.id] - exact) > exact * 2e-4:
			errors.append("%s: interpolated lap %.3f vs simulated %.3f" % [b.name, q.quali_times[b.id], exact])
			break

	# the sheet: fastest first, gaps to pole, a player without a time at the back
	var bots_best: float = q.quali_times.values().min()
	var rows := Qualifying.sheet(q, bots_best - 0.5)
	if rows[0].id != 0 or rows[0].pos != 1 or absf(rows[1].gap - 0.5) > 1e-6:
		errors.append("a player 0.5 s up on the field should be on pole with a 0.5 s gap")
	rows = Qualifying.sheet(q, bots_best + 100.0)
	if rows[-1].id != 0:
		errors.append("a slow lap should put the player last")
	rows = Qualifying.sheet(q, null)
	if rows[-1].id != 0 or rows[-1].time != null or rows[-1].gap != null:
		errors.append("no time set: the player is listed last with no time")
	for i in range(1, rows.size() - 1):
		if rows[i].time < rows[i - 1].time:
			errors.append("sheet not sorted by lap time at row %d" % i)
			break

	# a grid from a sheet where the player is P4
	var times: Array = q.quali_times.values()
	times.sort()
	rows = Qualifying.sheet(q, (times[2] + times[3]) * 0.5)
	if rows[3].id != 0:
		errors.append("expected the player P4, got P%d" % [rows.find_custom(func(r): return r.id == 0) + 1])
	var grid := Qualifying.grid_from(q, rows)
	# through JSON, as the saved championship does
	grid = JSON.parse_string(JSON.stringify(grid))
	var rs := RaceSettings.new()
	rs.track = "gp"
	rs.opponents = 15
	rs.quali_grid = grid
	var race := Race.new(rs, null, 77)
	if race.cars.size() != 16:
		errors.append("the race should have 16 cars, got %d" % race.cars.size())
	for k in rows.size():
		if race.cars[k].id != int(rows[k].id) or race.cars[k].grid != k + 1:
			errors.append("grid slot %d should hold car %d, got %d" % [k + 1, int(rows[k].id), race.cars[k].id])
			break
	if race.player.grid != 4:
		errors.append("player should start P4, got P%d" % race.player.grid)
	for b in q.quali_bots:
		var raced: RaceCar = race.cars.filter(func(c): return c.id == b.id)[0]
		if absf(raced.skill - b.skill) > 1e-6 or absf(raced.quali - b.quali) > 1e-6:
			errors.append("%s should race at the pace they qualified with" % b.name)
			break
	# a driver missing from the order starts behind everyone
	rs.quali_grid = {"order": [3, 2], "skills": {}, "quali": {}}
	race = Race.new(rs, null, 77)
	if race.cars[0].id != 3 or race.cars[1].id != 2 or race.cars.size() != 16:
		errors.append("a partial grid should keep the listed order first")

	# running wide on the out lap (or in the pit lane) must not void the first timed lap
	var pl := q.player
	pl.d = q.track.half + 3.0
	q.after_move(pl, 0.0)
	if pl.invalid_lap:
		errors.append("the out lap should not be flagged for running wide")
	pl.lap = 1
	q.after_move(pl, 0.0)
	if not pl.invalid_lap:
		errors.append("a timed lap with the car off the tarmac should be flagged invalid")
	q.phase = "racing"
	q.on_line(pl) # crossing the line starts the next lap clean
	q.phase = "countdown"
	if pl.invalid_lap:
		errors.append("the line should clear the invalid flag")
	pl.d = 0.0
	pl.lap = 0
	pl.invalid_lap = false
	pl.last_lap = null
	pl.lap_times.clear()
	pl.best_lap = null

	# a short run: the lights are skipped, the car moves, nobody pits, the out lap does not set a time
	var inp := Race.PlayerInput.new()
	q.set_autopilot(true)
	for i in 120 * 12:
		q.step(1.0 / 120.0, inp)
	if q.phase != "racing" or q.player.speed < 5.0:
		errors.append("the session should be underway after 12 s (phase %s, speed %.1f)" % [q.phase, q.player.speed])
	if q.player.best_lap != null:
		errors.append("the out lap should not count as a lap time")
	completed = true
	return errors
