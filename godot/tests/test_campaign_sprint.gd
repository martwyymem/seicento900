## The campaign's A->B sprints (Campaign "format": "sprint", RaceSettings.sprint): the stage data (spans on their
## tracks, 3-8 km, the menus' wording), the settings a stage turns into, every sprint's grid behind its start line A,
## and headless field races (one on a baked open-world sprint, one whose span runs over the track's own line): every
## car finishes at the line B, the classification is the finishing order, and no laps are counted.
extends RefCounted

var completed := false

const DT := 1.0 / 120.0

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	_data(errors)
	_grids(errors)
	_race(errors, "stage_wola", 5)
	_race(errors, "stage_5", 4) # Bielsko: A on Gościnna, over the track's line on Armii Krajowej, B on Karpacka
	completed = true
	return errors

func _data(errors: Array[String]) -> void:
	var sprints := Campaign.STAGES.filter(func(st): return Campaign.is_sprint(st))
	if sprints.size() < 5:
		errors.append("data: only %d sprint stages (want the three converted loops and the Wola and Góra sprints)" % sprints.size())
	for id in ["stage_1", "stage_2", "stage_5", "stage_wola", "stage_gora"]:
		var i := Campaign.index_of(id)
		if i < 0 or not Campaign.is_sprint(Campaign.STAGES[i]):
			errors.append("data: %s should be a sprint" % id)
	for id in ["stage_wola", "stage_gora"]:
		var i := Campaign.index_of(id)
		if i < 0 or int(Campaign.STAGES[i].act) > 2:
			errors.append("data: %s should be in act 1 or 2" % id)
	for st: Dictionary in sprints:
		var tr := Race.get_track(String(st.track))
		var sp := Campaign.sprint_span(st)
		var length := Campaign.sprint_length(st)
		if sp.x < 0.0 or sp.x >= tr.L or sp.y < 0.0 or sp.y >= tr.L or is_equal_approx(sp.x, sp.y):
			errors.append("data: %s's span %s is not on its %.0f m track" % [st.id, sp, tr.L])
		if length < 3000.0 or length > 8000.0:
			errors.append("data: %s is %.0f m from A to B (want 3-8 km)" % [st.id, length])
		if not Campaign.length_label(st).ends_with("km sprint"):
			errors.append("data: %s reads as %s" % [st.id, Campaign.length_label(st)])
		if st.get("baked", false) and not tr.cfg.point_to_point:
			errors.append("data: %s's baked track %s is not a point-to-point stage" % [st.id, st.track])
	var lap: Dictionary = Campaign.STAGES[Campaign.index_of("stage_3")]
	if Campaign.is_sprint(lap) or Campaign.length_label(lap) != "2 laps":
		errors.append("data: the Bór lap race reads as %s" % Campaign.length_label(lap))
	# the settings a sprint stage turns into
	var st := RaceSettings.new()
	st.mandatory_stop = true
	st.refuel = true
	var wola: Dictionary = Campaign.STAGES[Campaign.index_of("stage_wola")]
	Campaign.apply_format(st, wola)
	var sp := Campaign.sprint_span(wola)
	if not st.sprint or st.stage_from != sp.x or st.stage_to != sp.y or st.laps != 1 or st.mission != "sprint" \
			or st.mandatory_stop or st.refuel or st.two_compounds:
		errors.append("data: apply_format left %s" % [[st.sprint, st.stage_from, st.stage_to, st.laps, st.mission, st.mandatory_stop]])
	var lr := RaceSettings.new()
	lr.laps = 2
	Campaign.apply_format(lr, lap)
	if lr.sprint or lr.laps != 2 or lr.mission != "":
		errors.append("data: apply_format changed a lap race")

## Every sprint stage's field grids two by two behind its line A, in order, none past it.
func _grids(errors: Array[String]) -> void:
	for st: Dictionary in Campaign.STAGES.filter(func(x): return Campaign.is_sprint(x)):
		var race := Race.new(_settings(st, int(st.opponents)), null, 3)
		var n := race.cars.size()
		for c: RaceCar in race.cars:
			var run := race.sprint_run(c)
			if run > -8.9 or run < -(9.0 + 6.5 * (n - 1)) - 0.1:
				errors.append("grid: %s's car %d stands %.1f m from A" % [st.id, c.grid, run])
				break
		if race.cars.any(func(c: RaceCar) -> bool: return c.lap != 0):
			errors.append("grid: %s starts a car on another lap" % st.id)
		race.dispose()

func _settings(stage: Dictionary, opp: int) -> RaceSettings:
	var st := RaceSettings.new()
	st.track = String(stage.track)
	st.opponents = opp
	st.difficulty = "easy"
	st.ai_learning = "off"
	st.weather = "dry"
	st.grid = "p3"
	Campaign.apply_format(st, stage)
	return st

## A whole field on autopilot from A to B: everyone home at the line, classified in the order they crossed it.
func _race(errors: Array[String], id: String, opp: int) -> void:
	var stage: Dictionary = Campaign.STAGES[Campaign.index_of(id)]
	var race := Race.new(_settings(stage, opp), null, 7)
	race.set_autopilot(true)
	var length := race.sprint_length()
	var at_line := {}
	var inp := Race.PlayerInput.new()
	var n := 0
	while race.phase != "finished" and n < int(900.0 / DT):
		race.step(DT, inp)
		for c: RaceCar in race.cars:
			if c.finished and not at_line.has(c):
				at_line[c] = race.sprint_run(c)
		n += 1
	var tag := "sprint %s" % id
	var home := race.cars.filter(func(c: RaceCar) -> bool: return c.finished and not c.running and not c.dnf)
	if race.phase != "finished" or home.size() != race.cars.size():
		errors.append("%s: %d of %d cars home (phase %s)" % [tag, home.size(), race.cars.size(), race.phase])
	for c: RaceCar in at_line:
		if absf(float(at_line[c]) - length) > 6.0:
			errors.append("%s: %s finished %.1f m from A, not at B (%.0f m)" % [tag, c.name, float(at_line[c]), length])
			break
	for c: RaceCar in race.cars:
		if not c.lap_times.is_empty() or c.best_lap != null:
			errors.append("%s: %s counted a lap (%s)" % [tag, c.name, c.lap_times])
			break
	var rows := race.results()
	for i in rows.size() - 1:
		if rows[i].total == null or rows[i + 1].total == null or float(rows[i].total) > float(rows[i + 1].total):
			errors.append("%s: classification not by finishing time" % tag)
			break
		if rows[i].car.finish_order > rows[i + 1].car.finish_order:
			errors.append("%s: classification not in the order the cars crossed B" % tag)
			break
		if String(rows[i + 1].gap).contains("lap"):
			errors.append("%s: a gap in laps (%s)" % [tag, rows[i + 1].gap])
			break
	if race.winner == null or rows[0].car != race.winner:
		errors.append("%s: the winner is not first" % tag)
	if rows[0].total != null:
		var kmh := length / float(rows[0].total) * 3.6
		if kmh < 40.0 or kmh > 140.0:
			errors.append("%s: the winner averaged %.0f km/h over %.0f m" % [tag, kmh, length])
	race.dispose()
