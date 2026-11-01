## Rally pace on loose stages: the co-driver (the player's car on autopilot) drives each gravel stage of the
## events on tarmac and on gravel, dry; prints its stage time, the rivals' clean time for a co-driver-pace driver
## (Rally.base_times) and the ratio between the two. godot --headless --path godot -s tests/_rally_surface_probe.gd
## Dirt on the baked stages: SURFACES=tarmac,dirt STAGES=rajsko_wilczkowice,kolonia_stawowa,... (same command)
extends SceneTree

func _drive(sdef: Dictionary) -> Array:
	var rs := RaceSettings.new()
	Rally.configure_stage(rs, sdef)
	var race := Race.new(rs, null, 9)
	race.set_autopilot(true)
	var idle := Race.PlayerInput.new()
	var ticks := 0
	while race.phase != "finished" and ticks < 120 * 900:
		race.step(1.0 / 120.0, idle)
		ticks += 1
	var t = race.stage.time
	var base: Dictionary = Rally.base_times(race, [Qualifying.CO_DRIVER])
	race.dispose()
	return [t, base.times[0]]

func _initialize() -> void:
	await process_frame
	Brain.use_disk = false
	LapRecords.use_disk = false
	print("stage                 surface  codriver_s  rival_base_s  ratio")
	# SURFACES=tarmac,dirt (default tarmac,gravel); STAGES=rajsko_wilczkowice,... (baked point-to-point stages instead)
	var surfaces := (OS.get_environment("SURFACES") if OS.get_environment("SURFACES") != "" else "tarmac,gravel").split(",")
	var stages: Array = [{"track": "bor", "from": 0.0, "to": 0.0}, {"track": "wilamowice", "from": 0.0, "to": 0.0}, {"track": "bor", "from": 0.0, "to": 1700.0}]
	if OS.get_environment("STAGES") != "":
		stages = Array(OS.get_environment("STAGES").split(",")).map(func(k: String) -> Dictionary:
			var sp := Rally.span({"track": k, "baked": true})
			return {"track": k, "from": sp.x, "to": sp.y})
	for sd in stages:
		var times := {}
		for surface in surfaces:
			var d: Dictionary = sd.duplicate()
			d.merge({"surface": surface, "weather": "dry", "hour": 12.0})
			var r := _drive(d)
			times[surface] = r[0]
			print("%-10s %6.0f-%-6.0f %-7s  %10s  %12.2f  %5.3f" % [sd.track, sd.from, sd.to, surface,
				"%.2f" % r[0] if r[0] != null else "DNF", r[1], (r[0] / r[1]) if r[0] != null else 0.0])
		var loose: String = surfaces[surfaces.size() - 1]
		if times.get("tarmac") != null and times.get(loose) != null:
			print("    %s / tarmac co-driver: %.3f   conditions_factor(%s): %.3f" % [loose, times[loose] / times.tarmac, loose, Rally.conditions_factor(loose, "dry")])
	quit()
