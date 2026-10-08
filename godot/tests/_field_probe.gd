## Field probe (dev tool): one race with every bot on the full physics, run once with each driver on their
## own set-up and once with the whole field stock (same seed), and per driver: offs, spins, best lap, result.
## TRACK=gp LAPS=2 ASSISTS=full godot --headless --path godot -s tests/_field_probe.gd
extends SceneTree

func _run(key: String, laps: int, assists: String, stock: bool) -> Dictionary:
	var st := RaceSettings.new()
	st.track = key
	st.laps = laps
	st.opponents = 15
	st.grid = "back"
	st.assists = assists
	st.weather = OS.get_environment("WEATHER") if OS.get_environment("WEATHER") else "dry"
	var race := Race.new(st, null, 7)
	if stock:
		for car in race.cars:
			race.fit_setup(car, {})
	race.set_autopilot(true)
	var inp := Race.PlayerInput.new()
	var out := {}
	var off := {}
	var spins := {}
	var last_spin := {}
	for car in race.cars:
		off[car.name] = 0.0
		spins[car.name] = 0
		last_spin[car.name] = car.spin_t
	var dt := 1.0 / 120.0
	var t := 0.0
	while race.phase != "finished" and t < laps * race.cal.T0 * 2.5 + 60.0:
		race.step(dt, inp)
		t += dt
		for car in race.cars:
			if absf(car.d) > race.track.half + 0.5 and car.mode == "race":
				off[car.name] += dt
			if car.spin_t != last_spin[car.name]:
				# spin_t is stamped every tick a car is out of control: count a new moment, not each tick of one
				if car.spin_t - last_spin[car.name] > 1.0:
					spins[car.name] += 1
				last_spin[car.name] = car.spin_t
	for car in race.cars:
		out[car.name] = {"off": off[car.name], "spins": spins[car.name], "best": car.best_lap, "pos": car.pos,
			"dnf": car.dnf, "free": car.control == "free"}
	race.dispose()
	return out

func _initialize() -> void:
	Brain.use_disk = false
	var key := OS.get_environment("TRACK") if OS.get_environment("TRACK") else "gp"
	var laps := int(OS.get_environment("LAPS")) if OS.get_environment("LAPS") else 2
	var assists := OS.get_environment("ASSISTS") if OS.get_environment("ASSISTS") else "full"
	var own := _run(key, laps, assists, false)
	var base := _run(key, laps, assists, true)
	print("%-20s %-28s | %s" % ["", "own set-up: off s / spins / best / pos", "stock: off s / spins / best / pos"])
	var tot := [0.0, 0, 0.0, 0]
	for name in own:
		var a: Dictionary = own[name]
		var b: Dictionary = base[name]
		tot[0] += a.off
		tot[1] += a.spins
		tot[2] += b.off
		tot[3] += b.spins
		print("%-20s %6.1f %2d %8s P%-2d%s | %6.1f %2d %8s P%-2d%s" % [name, a.off, a.spins, Race.fmt_time(a.best), a.pos,
			" DNF" if a.dnf else "    ", b.off, b.spins, Race.fmt_time(b.best), b.pos, " DNF" if b.dnf else ""])
	print("TOTAL own: %.1f s off, %d spins | stock: %.1f s off, %d spins" % tot)
	quit()
