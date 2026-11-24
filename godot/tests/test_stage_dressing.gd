## Course dressing & animated MultiMesh spectators on street stages and rally stages:
## - Present on street stages (street_stage = true) and rally stages (both baked point-to-point and split spans)
## - Absent on circuits that already carry trackside furniture (even in rally mode) and absent in the open world
## - Placed strictly clear of the road surface, run-off, drawn buildings/landmarks, water, and Oświęcim's memorial side
## - Spectators batched in MultiMeshes with spectator.gdshader and capped per stage.
extends RefCounted

const STAGE_DRESSING := preload("res://scripts/ui/stage_dressing.gd")
const RACE_WORLD := preload("res://scripts/ui/race_world.gd")

var completed := false
var errors: Array[String] = []


func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])


func _min_track_dist(tr: Track, tx: float, tz: float) -> float:
	var best2 := INF
	for i in tr.n:
		var dx := tr.X[i] - tx
		var dz := tr.Y[i] - tz
		var d2 := dx * dx + dz * dz
		if d2 < best2:
			best2 = d2
	return sqrt(best2)


func _verify_clearances(key: String, rw: Node3D) -> void:
	var sd: RefCounted = rw.stage_dressing
	var tr: Track = rw.track
	var edge := tr.half + tr.cfg.runoff
	var c: Vector2 = rw.world_center

	# 1. Every arch leg stands strictly outside the road and run-off, and clear of buildings
	for leg: Vector3 in sd.arch_legs:
		var tx := leg.x + c.x
		var tz := leg.z + c.y
		var dist := _min_track_dist(tr, tx, tz)
		if dist <= edge + 0.35:
			check("%s arch leg clear of road/run-off" % key, false, "(dist %.2f m <= %.2f m)" % [dist, edge + 0.35])
			break
		if sd._hits_building(Vector2(leg.x, leg.z), 0.3):
			check("%s arch leg clear of buildings" % key, false, "(at %.1f, %.1f)" % [leg.x, leg.z])
			break

	# 2. Every roadside sign and barrier tape stands strictly off the road and run-off, and clear of buildings
	for part in ["StageChevronLeft", "StageChevronRight", "StageWarningSign", "StageTapeBarrier"]:
		for pos: Vector3 in sd.placements.get(part, []):
			var tx := pos.x + c.x
			var tz := pos.z + c.y
			var dist := _min_track_dist(tr, tx, tz)
			if dist <= edge + 0.7:
				check("%s %s clear of road/run-off" % [key, part], false, "(dist %.2f m <= %.2f m)" % [dist, edge + 0.7])
				break
			if sd._hits_building(Vector2(pos.x, pos.z), 0.35):
				check("%s %s clear of buildings" % [key, part], false, "(at %.1f, %.1f)" % [pos.x, pos.z])
				break
			if key == "oswiecim" and Vector2(tx, tz).distance_to(STAGE_DRESSING.OSWIECIM_MEMORIAL) < STAGE_DRESSING.OSWIECIM_EXCLUDE_R - 1.0:
				check("oswiecim %s stays clear of memorial side" % part, false, "(at %.1f, %.1f)" % [tx, tz])
				break

	# 3. Every spectator stands strictly behind the road/run-off and clear of buildings & Oświęcim memorial side
	for pos: Vector3 in sd.spectator_positions:
		var tx := pos.x + c.x
		var tz := pos.z + c.y
		var dist := _min_track_dist(tr, tx, tz)
		if dist <= edge + 1.4:
			check("%s spectator clear of road/run-off" % key, false, "(dist %.2f m <= %.2f m)" % [dist, edge + 1.4])
			break
		if sd._hits_building(Vector2(pos.x, pos.z), 0.35):
			check("%s spectator clear of buildings" % key, false, "(at %.1f, %.1f)" % [pos.x, pos.z])
			break
		if key == "oswiecim" and Vector2(tx, tz).distance_to(STAGE_DRESSING.OSWIECIM_MEMORIAL) < STAGE_DRESSING.OSWIECIM_EXCLUDE_R - 1.0:
			check("oswiecim spectators stay clear of memorial side", false, "(at %.1f, %.1f)" % [tx, tz])
			break


func run() -> Array[String]:
	var rw: Node3D = RACE_WORLD.new()
	Engine.get_main_loop().root.add_child(rw)

	# 1. Street stages: start arch, tape, chevrons, warning boards, and MultiMesh spectators
	for key in ["wilamowice", "oswiecim", "brzeszcze"]:
		rw.set_track(Race.get_track(key))
		var node: Node = rw.track_root.get_node_or_null("StageDressing")
		check("%s creates StageDressing node" % key, node != null)
		var st: Dictionary = rw.stage_dressing.stats
		check("%s places a start arch" % key, int(st.get("arches", 0)) == 1, str(st))
		check("%s places chevron boards" % key, int(st.get("chevrons", 0)) > 0, str(st))
		check("%s places warning boards" % key, int(st.get("warnings", 0)) > 0, str(st))
		check("%s places barrier tape" % key, int(st.get("tape", 0)) > 0, str(st))
		var specs: int = int(st.get("spectators", 0))
		check("%s places capped MultiMesh spectators" % key, specs >= 20 and specs <= 600, "(count=%d)" % specs)
		if node:
			var found_spec_mm := false
			for ch in node.get_children():
				if ch is MultiMeshInstance3D and String(ch.name).begins_with("Spectators"):
					var mmi := ch as MultiMeshInstance3D
					found_spec_mm = true
					check("%s spectator MultiMesh uses spectator.gdshader" % key,
						mmi.material_override is ShaderMaterial and (mmi.material_override as ShaderMaterial).shader == STAGE_DRESSING.SPECTATOR_SHADER)
					check("%s spectator MultiMesh enables custom_data" % key, mmi.multimesh != null and mmi.multimesh.use_custom_data)
					check("%s spectator MultiMesh disables shadows" % key, mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
					break
			check("%s has batched spectator MultiMesh" % key, found_spec_mm)
		_verify_clearances(key, rw)

	# 2. Point-to-point rally stage (maly_bor): BOTH Start AND Finish arches + dressing + spectators
	var rs_rally := RaceSettings.new()
	Rally.configure_stage(rs_rally, Rally.event("bor").stages[1]) # Mały Bór (baked point-to-point)
	var rally_race := Race.new(rs_rally)
	rw.set_race(rally_race)
	var r_node: Node = rw.track_root.get_node_or_null("StageDressing")
	var r_st: Dictionary = rw.stage_dressing.stats
	check("maly_bor rally stage creates StageDressing", r_node != null)
	check("maly_bor rally stage places start and finish arches",
		r_node != null and r_node.has_node("StageArchStart") and r_node.has_node("StageArchFinish") and int(r_st.get("arches", 0)) == 2,
		str(r_st))
	check("maly_bor rally stage places tape, chevrons, warnings, spectators",
		int(r_st.get("tape", 0)) > 0 and int(r_st.get("chevrons", 0)) > 0 and int(r_st.get("warnings", 0)) > 0 and int(r_st.get("spectators", 0)) >= 20,
		str(r_st))
	_verify_clearances("maly_bor", rw)

	# 3. Split rally stage on a closed-loop street track (Bielsko 400..2400): re-spans cleanly with both arches
	var rs_split := RaceSettings.new()
	Rally.configure_stage(rs_split, Rally.event("beskidy").stages[1]) # Szyndzielnia Zjazd (400..2400)
	rw.set_race(Race.new(rs_split))
	var s_node: Node = rw.track_root.get_node_or_null("StageDressing")
	check("bielsko split rally stage places both start and finish arches",
		s_node != null and s_node.has_node("StageArchStart") and s_node.has_node("StageArchFinish"),
		str(rw.stage_dressing.stats))
	_verify_clearances("bielsko_rally", rw)

	# Shader update runs cleanly without error
	rw.stage_dressing.update(Vector3(10.0, 0.0, 20.0), Vector3(15.0, 0.0, 0.0), 0.5)
	check("spectator shader uniforms update",
		rw.stage_dressing.spectator_mat != null
		and (rw.stage_dressing.spectator_mat.get_shader_parameter("car_pos") as Vector3).is_equal_approx(Vector3(10.0, 0.0, 20.0)))

	# 4. Circuits (already have trackside furniture): NEVER receive StageDressing, even in rally mode
	for ckey in ["gp", "monza", "nordschleife"]:
		rw.set_track(Race.get_track(ckey))
		check("%s circuit has no StageDressing" % ckey,
			rw.track_root.get_node_or_null("StageDressing") == null and rw.stage_dressing.stats.is_empty())
	var rs_eifel := RaceSettings.new()
	Rally.configure_stage(rs_eifel, Rally.event("eifel").stages[1]) # Nordschleife circuit in rally mode
	rw.set_race(Race.new(rs_eifel))
	check("nordschleife circuit gets no StageDressing even in rally mode",
		rw.track_root.get_node_or_null("StageDressing") == null and rw.stage_dressing.stats.is_empty())

	# 5. Open world does not load or use StageDressing
	for ow_script in ["res://scripts/world/open_world.gd", "res://scripts/world/town_builder.gd", "res://scripts/world/festival_dressing.gd"]:
		var src := FileAccess.get_file_as_string(ow_script)
		check("%s does not reference stage_dressing" % ow_script.get_file(), not src.contains("stage_dressing"))

	# 6. Determinism check on street stage rebuild
	rw.set_track(Race.get_track("wilamowice"))
	var sig_a: PackedVector3Array = rw.stage_dressing.spectator_positions.duplicate()
	var stats_a: Dictionary = rw.stage_dressing.stats.duplicate()
	rw.set_track(Race.get_track("wilamowice"))
	check("wilamowice stage dressing is deterministic",
		rw.stage_dressing.stats == stats_a and rw.stage_dressing.spectator_positions == sig_a)

	rw.free()
	completed = true
	return errors
