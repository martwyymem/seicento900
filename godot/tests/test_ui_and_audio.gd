## Test suite for RaceAudio, RaceWorld procedural features, and UI/Championship systems.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []

	# 1. Test RaceAudio
	var audio := RaceAudio.new()
	var dummy_car := {
		"rpm": 4200.0,
		"throttle": 0.85,
		"slip": 0.1,
		"understeer": 0.05,
		"gear": 2
	}
	audio.update_car(dummy_car, true)
	audio.trigger_shift(true, 0.9)
	audio.beep(880.0, 2)
	if audio.muted:
		errors.append("Default audio should not be muted")
	audio.toggle_mute()
	if not audio.muted:
		errors.append("Audio should be muted after toggle")
	audio.toggle_mute()

	# 2. Test RaceWorld procedural 3D features
	var tr: Track = Race.get_track("gp")
	var world_script: GDScript = load("res://scripts/ui/race_world.gd")
	var world = world_script.new()
	world.set_track(tr)

	var track_node: Node3D = world.track_root
	if not track_node:
		errors.append("Track root should exist")
	elif not track_node.get_node_or_null("Asphalt"):
		errors.append("Asphalt mesh should exist")
	elif not track_node.get_node_or_null("Runoff"):
		errors.append("Runoff mesh should exist")
	elif not track_node.get_node_or_null("Kerbs"):
		errors.append("Kerbs mesh should exist")
	elif not track_node.get_node_or_null("PitLane"):
		errors.append("PitLane mesh should exist")
	elif not track_node.get_node_or_null("PitWall"):
		errors.append("PitWall mesh should exist")
	elif not track_node.get_node_or_null("RacingLine"):
		errors.append("RacingLine mesh should exist")

	if world.start_lights.size() != 5:
		errors.append("Expected 5 start lights on gantry, got %d" % world.start_lights.size())
	if world.tv_cameras.size() < 4:
		errors.append("Expected at least 4 TV camera positions, got %d" % world.tv_cameras.size())

	var initial_mode: int = world.camera_mode
	world.cycle_camera()
	if world.camera_mode == initial_mode:
		errors.append("Camera mode should cycle")
	var rl_on: bool = world.toggle_racing_line()
	if rl_on:
		errors.append("Racing line toggle should flip to false")

	# 3. Test Championship scoring & persistence
	var rs := RaceSettings.new()
	rs.track = "monza"
	rs.laps = 1
	rs.opponents = 4
	var race := Race.new(rs)
	var inp := Race.PlayerInput.new()
	for i in 60:
		race.step(1.0 / 120.0, inp)

	var results := race.results()
	if results.size() != 5:
		errors.append("Expected 5 cars in results, got %d" % results.size())

	completed = true
	return errors
