## Balance probe (headless) for the campaign's class ladder and stage pace (B1/B2): races campaign stages with
## the autopilot driving the player at skill H (a stand-in for a human's pace) and prints the start slot, the
## finish, and the gap to the winner (negative: the player won by that much).
##   MODE=new (default): the stage as configured now (Campaign.configure_stage: its grid, mixed-class field,
##     pace and the campaign heat HEAT), the player in the stage's reference car (REF: the best car of the expected
##     class the missions have opened by then; CAR=<key> overrides).
##   MODE=old: the 0.5.9 layout (P3/P2/pole grids, the stage's base difficulty, a one-make Seicento field), to
##     calibrate H against the 2026-11-24 playtest (stages 1-12 won by 10-22 s).
## STAGES=0,1,2 SEEDS=2 H=1.0 MODE=new godot --headless --path godot -s tests/_campaign_ladder_probe.gd
extends SceneTree

const OLD_GRID := ["p3", "p3", "p3", "p3", "p2", "p2", "p3", "p3", "p3", "p2", "p3", "p2", "pole", "pole"]

func _initialize() -> void:
	Brain.use_disk = false
	Campaign.save_file = "campaign_ladder_probe_%d.json" % OS.get_process_id() # parallel probes keep apart
	Campaign.reset_progress()
	var heat := float(OS.get_environment("HEAT")) if OS.get_environment("HEAT") != "" else 0.0
	if heat > 0.0:
		var prog := Campaign.load_progress()
		prog["heat"] = heat
		Campaign.save_progress(prog)
	var stages := (OS.get_environment("STAGES") if OS.get_environment("STAGES") != "" else "0").split(",")
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 1
	var h := float(OS.get_environment("H")) if OS.get_environment("H") != "" else 0.97
	var old := OS.get_environment("MODE") == "old"
	var car_over := OS.get_environment("CAR")
	for si in stages:
		var idx := int(si)
		var st: Dictionary = Campaign.get_stage(idx)
		var key := "stock" if old else (car_over if car_over != "" else ref_car(idx))
		for seed in seeds:
			var s := RaceSettings.new()
			s.player_name = "PLAYER"
			s.car_class = key
			Campaign.configure_stage(s, st, DifficultyProfile.AVERAGE)
			if old:
				s.grid = OLD_GRID[idx]
				s.field_classes = PackedStringArray()
				s.difficulty = String(st.base_difficulty)
				s.difficulty_shift = 0.0
			s.difficulty_shift += float(OS.get_environment("SHIFT")) if OS.get_environment("SHIFT") != "" else 0.0 # levels on top
			var models := {} if key == "stock" else {"car_model": CarCatalog.model(key)}
			var race := Race.new(s, null, 1000 + seed, models)
			race.set_autopilot(true)
			race.player.skill = h
			var inp := Race.PlayerInput.new()
			var ticks := 0
			var t0 := Time.get_ticks_msec()
			while race.phase != "finished" and ticks < 120 * 2400:
				race.step(1.0 / 120.0, inp)
				ticks += 1
			var res: Array = race.results()
			var ppos := 0
			var ptot = null
			for r in res:
				if r.car.is_player:
					ppos = r.pos
					ptot = r.total
			var win_tot = res[0].total
			var gap := 0.0
			if ppos == 1 and res.size() > 1 and res[1].total != null:
				gap = -(float(res[1].total) - float(ptot))
			elif ptot != null and win_tot != null:
				gap = float(ptot) - float(win_tot)
			var mix := {}
			for c in race.cars:
				if not c.is_player:
					mix[c.car_key] = int(mix.get(c.car_key, 0)) + 1
			var top := []
			for r in res.slice(0, 3):
				top.append("%s(%s)" % ["YOU" if r.car.is_player else r.car.name.get_slice(" ", 1), r.car.car_key])
			print("RESULT stage=%d %s mode=%s car=%s H=%.3f seed=%d lvl=%s%+.2f grid=%s start=P%d finish=P%d target=P%d gap=%+.1f mixed=%s %s top=%s wall=%.0fs" % [
				idx, st.track, "old" if old else "new", key, h, seed, s.difficulty, s.difficulty_shift, s.grid, race.player.grid, ppos,
				int(st.target_pos), gap, race.mixed, JSON.stringify(mix), ",".join(top), (Time.get_ticks_msec() - t0) / 1000.0])
			var times := []
			for r in res:
				times.append("%s%s:%s" % ["*" if r.car.is_player else "", r.car.car_key, "dnf" if r.total == null else "%.2f" % float(r.total)])
			print("TIMES stage=%d mode=%s seed=%d %s" % [idx, "old" if old else "new", seed, " ".join(times)])
			race.dispose()
	var path := ProjectSettings.globalize_path(SaveData.path(Campaign.save_file))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	quit()

## The car a player is expected to bring to stage idx: the quickest car of the stage's class that the missions
## have opened by then (a mission opens after the stage it follows is cleared), else the stock Seicento.
static func ref_car(idx: int) -> String:
	var st: Dictionary = Campaign.STAGES[idx]
	if st.has("car_class"):
		return String(st.car_class)
	var cls := Campaign.stage_class(st)
	var best := "stock"
	var best_v := 0.0
	for m in Missions.MISSIONS:
		var car := String(m.get("reward_car", ""))
		if car == "" or Campaign.index_of(String(m.after)) >= idx:
			continue
		if Campaign.class_of(car) == cls and float(CarCatalog.FIGURES[car][1]) > best_v:
			best = car
			best_v = float(CarCatalog.FIGURES[car][1])
	return best
