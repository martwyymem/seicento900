## Probe (headless): the autopilot's lap times on the given tracks against a small field, to size race laps.
## TRACKS=bielsko,krakow godot --headless --path godot -s tests/_street_lap_probe.gd
extends SceneTree

func _initialize() -> void:
	Brain.use_disk = false
	for t in OS.get_environment("TRACKS").split(","):
		var s := RaceSettings.new()
		s.track = t
		s.laps = 3
		s.opponents = 5
		s.difficulty = "medium"
		s.player_name = "PLAYER"
		var race := Race.new(s, null, 7)
		race.set_autopilot(true)
		var inp := Race.PlayerInput.new()
		var ticks := 0
		while race.phase != "finished" and ticks < 120 * 1500:
			race.step(1.0 / 120.0, inp)
			ticks += 1
		var bests := []
		for r in race.results():
			bests.append("%s%s" % ["*" if r.car.is_player else "", Race.fmt_time(r.car.best_lap)])
		print("%s L=%.0f race %.0fs bests %s" % [t, race.track.L, ticks / 120.0, " ".join(bests)])
	quit()
