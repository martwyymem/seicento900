## Headless checks for HudMotion across RaceHud, OpenWorldHud, DashGauge and Options persistence:
## - With HUD motion On, a step in lateral acceleration moves the speedometer group most, tilts/skews DashGauge,
##   moves corner panels less, leaves centre text stationary, and settles back to the exact rest pose.
## - Reduced halves the amplitude; Off never moves anything.
## - OpenWorldHud reacts to turning and vertical landing kicks and settles back to exact rest.
## - The "HUD MOTION" option lives in Options -> Look and persists through graphics.cfg.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var saved_mode := HudMotion.mode
	var tree := Engine.get_main_loop() as SceneTree
	_check_race_hud(errors, tree)
	_check_open_world_hud(errors, tree)
	_check_persistence(errors, tree)
	HudMotion.mode = saved_mode
	completed = true
	return errors

static func _host(tree: SceneTree, canvas := Vector2(1600, 900)) -> Control:
	var h := Control.new()
	h.size = canvas
	tree.root.add_child(h)
	return h

func _check_race_hud(errors: Array[String], tree: SceneTree) -> void:
	var rs := RaceSettings.new()
	rs.track = "monza"
	rs.opponents = 3
	var race := Race.new(rs)
	var host := _host(tree, Vector2(1600, 900))
	var hud := RaceHud.new()
	host.add_child(hud)
	hud.start(race, null, null)
	race.phase = "racing"
	race.race_time = 2.0
	race.player.control = "free"
	race.player.phys = PhysState.new()
	race.player.speed = 25.0

	# Rest pose at start
	if hud.dash_group.position != Vector2.ZERO or hud.dash.rotation != 0.0 or hud.dash.scale != Vector2.ONE \
			or hud.dash.tilt_skew != Vector2.ZERO or hud.corners_group.position != Vector2.ZERO:
		errors.append("RaceHud should start at exact rest pose: dash=%s rot=%.4f" % [hud.dash_group.position, hud.dash.rotation])

	# Step in lateral acceleration (+1 g turning right) with HUD motion On
	HudMotion.mode = HudMotion.MODE_ON
	race.player.phys.ay_f = 9.81
	race.player.phys.ax_f = 0.0
	var dt := 1.0 / 60.0
	var peak_dash_x := 0.0
	var peak_corner_x := 0.0
	var peak_rot := 0.0
	var banner_before := hud.banner.position
	for _i in 30: # 0.5 s sustained 1 g right turn
		hud.update(dt)
		if absf(hud.dash_group.position.x) > absf(peak_dash_x):
			peak_dash_x = hud.dash_group.position.x
		if absf(hud.corners_group.position.x) > absf(peak_corner_x):
			peak_corner_x = hud.corners_group.position.x
		if absf(hud.dash.rotation) > absf(peak_rot):
			peak_rot = hud.dash.rotation
	if peak_dash_x >= -4.0 or peak_dash_x < -12.5:
		errors.append("RaceHud On: 1 g right turn should shift dash_group left in [-12.5, -4] px, got %.2f" % peak_dash_x)
	if absf(peak_corner_x) < 1.5 or absf(peak_corner_x) >= absf(peak_dash_x) * 0.75:
		errors.append("RaceHud On: corner panels (%.2f px) should move less than speedometer (%.2f px)" % [peak_corner_x, peak_dash_x])
	if peak_rot >= -0.005 or absf(peak_rot) > deg_to_rad(1.6):
		errors.append("RaceHud On: dash rotation out of expected band: %.3f deg" % rad_to_deg(peak_rot))
	if hud.dash.tilt_skew == Vector2.ZERO:
		errors.append("RaceHud On: DashGauge should get subtle perspective skew during a corner")
	if hud.banner.position != banner_before or hud.banner.rotation != 0.0:
		errors.append("RaceHud On: centre banner should stay put during sway")

	# Release acceleration -> check fast settle (~0.35 s) and exact rest pose
	race.player.phys.ay_f = 0.0
	for _i in 24: # 0.4 s
		hud.update(dt)
	if absf(hud.dash_group.position.x) > absf(peak_dash_x) * 0.08:
		errors.append("RaceHud On: spring should settle within ~0.4 s (still at %.3f of %.2f)" % [hud.dash_group.position.x, peak_dash_x])
	for _i in 60: # another 1.0 s to snap to exact zero
		hud.update(dt)
	if hud.dash_group.position != Vector2.ZERO or hud.dash.rotation != 0.0 or hud.dash.scale != Vector2.ONE \
			or hud.dash.tilt_skew != Vector2.ZERO or hud.corners_group.position != Vector2.ZERO:
		errors.append("RaceHud On: did not settle to exact rest pose: pos=%s rot=%g scale=%s skew=%s" % [
			hud.dash_group.position, hud.dash.rotation, hud.dash.scale, hud.dash.tilt_skew])
	for c: Control in hud._corner_panels:
		if c.rotation != 0.0:
			errors.append("RaceHud On: corner panel rotation did not settle to exact 0 (%g)" % c.rotation)

	# Reduced mode: half amplitude
	HudMotion.mode = HudMotion.MODE_REDUCED
	race.player.phys.ay_f = 9.81
	var reduced_peak := 0.0
	for _i in 30:
		hud.update(dt)
		if absf(hud.dash_group.position.x) > absf(reduced_peak):
			reduced_peak = hud.dash_group.position.x
	if absf(reduced_peak - peak_dash_x * 0.5) > 0.25:
		errors.append("RaceHud Reduced: expected half amplitude (%.2f), got %.2f" % [peak_dash_x * 0.5, reduced_peak])

	# Off mode: snaps to rest and never moves on lateral/longitudinal steps
	HudMotion.mode = HudMotion.MODE_OFF
	race.player.phys.ay_f = 15.0
	race.player.phys.ax_f = -12.0
	for _i in 30:
		hud.update(dt)
		if hud.dash_group.position != Vector2.ZERO or hud.dash.rotation != 0.0 or hud.dash.scale != Vector2.ONE \
				or hud.dash.tilt_skew != Vector2.ZERO or hud.corners_group.position != Vector2.ZERO:
			errors.append("RaceHud Off: moved while HUD motion is Off (pos=%s rot=%g)" % [hud.dash_group.position, hud.dash.rotation])
			break

	host.free()
	race.dispose()

func _check_open_world_hud(errors: Array[String], tree: SceneTree) -> void:
	var host := _host(tree, Vector2(1600, 900))
	var hud := OpenWorldHud.new()
	host.add_child(hud)
	var dt := 1.0 / 60.0
	var pos := Vector2.ZERO
	var heading := 0.0
	var speed_mps := 25.0 # 90 km/h

	# Seed kinematics at straight driving
	HudMotion.mode = HudMotion.MODE_ON
	hud.update_drive(speed_mps * 3.6, 3, 4200.0, 6500.0, pos, heading, dt, 0.0)
	if hud.speedo_group.position != Vector2.ZERO or hud.speedo.rotation != 0.0:
		errors.append("OpenWorldHud: first frame should stay at rest, got %s" % hud.speedo_group.position)

	# Sustained right turn (~1.0 g: v * yaw_rate = 25 * 0.4 = 10 m/s^2)
	var peak_x := 0.0
	var peak_corner_x := 0.0
	for _i in 30:
		heading += 0.4 * dt
		pos += Vector2(cos(heading), sin(heading)) * speed_mps * dt
		hud.update_drive(speed_mps * 3.6, 3, 4200.0, 6500.0, pos, heading, dt, 0.0)
		if absf(hud.speedo_group.position.x) > absf(peak_x):
			peak_x = hud.speedo_group.position.x
		if absf(hud.corners_group.position.x) > absf(peak_corner_x):
			peak_corner_x = hud.corners_group.position.x
	if peak_x >= -4.0 or peak_x < -12.5:
		errors.append("OpenWorldHud On: 1 g turn should shift speedo_group left in [-12.5, -4] px, got %.2f" % peak_x)
	if absf(peak_corner_x) < 1.5 or absf(peak_corner_x) >= absf(peak_x) * 0.75:
		errors.append("OpenWorldHud On: corners (%.2f px) should move less than speedo (%.2f px)" % [peak_corner_x, peak_x])

	# Vertical landing kick: a fall building up to -6 m/s (gravity adds ~0.16 m/s a frame, under the bump dead-zone,
	# so it gives no kick of its own), then touchdown to 0 in one frame
	var vz := 0.0
	while vz > -6.0:
		vz = maxf(vz - 0.16, -6.0)
		pos += Vector2(cos(heading), sin(heading)) * speed_mps * dt
		hud.update_drive(speed_mps * 3.6, 3, 4200.0, 6500.0, pos, heading, dt, vz)
	var peak_bump_y := 0.0
	for _i in 12:
		pos += Vector2(cos(heading), sin(heading)) * speed_mps * dt
		hud.update_drive(speed_mps * 3.6, 3, 4200.0, 6500.0, pos, heading, dt, 0.0)
		if hud.speedo_group.position.y > peak_bump_y:
			peak_bump_y = hud.speedo_group.position.y
	if peak_bump_y < 1.0:
		errors.append("OpenWorldHud On: landing kick should push speedo_group down (> 1 px), got %.2f" % peak_bump_y)

	# Straighten out and settle back to exact rest pose
	for _i in 80:
		pos += Vector2(cos(heading), sin(heading)) * speed_mps * dt
		hud.update_drive(speed_mps * 3.6, 3, 4200.0, 6500.0, pos, heading, dt, 0.0)
	if hud.speedo_group.position != Vector2.ZERO or hud.speedo.rotation != 0.0 or hud.speedo.scale != Vector2.ONE \
			or hud.speedo.tilt_skew != Vector2.ZERO or hud.corners_group.position != Vector2.ZERO:
		errors.append("OpenWorldHud On: did not settle to exact rest pose: pos=%s rot=%g skew=%s" % [
			hud.speedo_group.position, hud.speedo.rotation, hud.speedo.tilt_skew])

	# Off mode: never moves
	HudMotion.mode = HudMotion.MODE_OFF
	for _i in 30:
		heading += 0.5 * dt
		pos += Vector2(cos(heading), sin(heading)) * speed_mps * dt
		hud.update_drive(speed_mps * 3.6, 3, 4200.0, 6500.0, pos, heading, dt, 0.0)
		if hud.speedo_group.position != Vector2.ZERO or hud.speedo.rotation != 0.0 or hud.corners_group.position != Vector2.ZERO:
			errors.append("OpenWorldHud Off: moved while HUD motion is Off (%s)" % hud.speedo_group.position)
			break

	host.free()

func _check_persistence(errors: Array[String], tree: SceneTree) -> void:
	var cfg_path := SaveData.path("graphics.cfg")
	var backup := FileAccess.get_file_as_bytes(cfg_path) if FileAccess.file_exists(cfg_path) else PackedByteArray()
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)

	if not is_instance_valid(game.hud_motion_picker):
		errors.append("Options should have hud_motion_picker")
	else:
		var picker: MenuSelector = game.hud_motion_picker
		var labels: Array[String] = []
		for i in picker.item_count:
			labels.append(picker.get_item_text(i))
		if labels != ["On", "Reduced", "Off"]:
			errors.append("HUD motion picker entries should be [On, Reduced, Off], got %s" % [labels])
		var items: Array = game._options_focus_items()
		if not items.has(picker):
			errors.append("HUD motion picker should be reachable with the d-pad / keyboard")

		for want in [HudMotion.MODE_REDUCED, HudMotion.MODE_OFF, HudMotion.MODE_ON]:
			game._on_hud_motion_selected(want)
			HudMotion.mode = (want + 1) % 3
			game._load_graphics_settings()
			if HudMotion.mode != want or picker.selected != want:
				errors.append("HUD motion mode %d did not persist across save/load (got mode=%d picker=%d)" % [want, HudMotion.mode, picker.selected])

	_restore_cfg(cfg_path, backup)
	game.free()

static func _restore_cfg(cfg_path: String, backup: PackedByteArray) -> void:
	if backup.is_empty():
		if FileAccess.file_exists(cfg_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	else:
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
