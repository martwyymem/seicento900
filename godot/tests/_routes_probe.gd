## The open-world routes driven by the co-driver (the player's car on autopilot): Mały Bór's stage on gravel, dry
## (stage time, DNF, where the race ends against the stage finish and the run-off) and one lap of the S1 Sprint on
## tarmac (for TRACK_DEFAULTS laps), a lap of Brzeszcze Kopalnia, and the second slice's stages on their surface. godot --headless --path godot -s tests/_routes_probe.gd
extends SceneTree

func _drive(sdef: Dictionary) -> Dictionary:
	var rs := RaceSettings.new()
	Rally.configure_stage(rs, sdef)
	var race := Race.new(rs, null, 9)
	race.set_autopilot(true)
	var idle := Race.PlayerInput.new()
	var ticks := 0
	var t0 := Time.get_ticks_msec()
	while race.phase != "finished" and ticks < 120 * 900:
		race.step(1.0 / 120.0, idle)
		ticks += 1
	var p := race.player
	var out := {"time": race.stage.time, "dnf": p.dnf, "phase": race.phase, "s": p.s, "lap": p.lap,
		"to": rs.stage_to, "L": race.track.L, "ms": Time.get_ticks_msec() - t0,
		"base": Rally.base_times(race, [Qualifying.CO_DRIVER]).times[0]}
	race.dispose()
	return out

func _initialize() -> void:
	await process_frame
	Brain.use_disk = false
	LapRecords.use_disk = false
	for sd in [{"track": "maly_bor", "baked": true, "surface": "gravel"}, {"track": "maly_bor", "baked": true, "surface": "tarmac"},
			{"track": "s1_sprint", "from": 0.0, "to": 0.0, "surface": "tarmac"}, {"track": "brzeszcze", "from": 0.0, "to": 0.0, "surface": "tarmac"},
			{"track": "kolonia_stawowa", "baked": true, "surface": "gravel"}, {"track": "babudy_gora", "baked": true, "surface": "gravel"},
			{"track": "rajsko_wilczkowice", "baked": true, "surface": "dirt"}, {"track": "lipowiec_kobylec", "baked": true, "surface": "gravel"}]:
		var d: Dictionary = sd.duplicate()
		d.merge({"weather": "dry", "hour": 12.0})
		var r := _drive(d)
		print("%-10s %-7s time %s  dnf %s  phase %s  ends at s %.0f (lap %d), finish %.0f of %.0f  rival base %.1f  (%d ms)" % [
			sd.track, sd.surface, "%.2f" % r.time if r.time != null else "-", r.dnf, r.phase, r.s, r.lap, r.to, r.L, r.base, r.ms])
	quit()
