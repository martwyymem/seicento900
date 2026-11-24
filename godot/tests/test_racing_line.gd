## Dynamic racing-line chevrons & BRAKE cue:
## 1) Pure colour logic (PaceNotes.brake_zone: speed, distance, corner speed, decel -> GREEN / YELLOW / RED),
## 2) BRAKE cue (PaceNotes.brake_cue / track_brake_cue / RaceHud._live_brake_state: fires at the braking point
##    off the brakes, stays quiet when braking hard enough, when already slow enough, or on corner exit, and
##    agrees 100% with the red arrows),
## 3) RaceWorld 3D MultiMesh chevron pool (replaces the static line mesh, dynamic per-frame colouring,
##    full / braking / off modes, distance fade, forward orientation, and per-frame cost).
extends RefCounted

const WORLD := preload("res://scripts/ui/race_world.gd")

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func _race(track_key: String, cls: String) -> Race:
	var rs := RaceSettings.new()
	rs.track = track_key
	rs.laps = 1
	rs.opponents = 1
	rs.car_class = cls
	rs.race_control = false
	var cm: CarModel = CarCatalog.model(cls) if cls != "stock" else CarModel.new()
	return Race.new(rs, {"stints": [{"c": "M", "laps": 1}]}, 7, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})

func _slowest_s(tr: Track, corner_v: PackedFloat64Array) -> Array:
	var lo := 0
	for i in tr.n:
		if corner_v[i] < corner_v[lo]:
			lo = i
	return [float(lo) * tr.step, corner_v[lo]]

func run() -> Array:
	Brain.use_disk = false
	_test_color_logic()
	_test_brake_cue()
	_test_world_arrows()
	completed = true
	return errors

func _test_color_logic() -> void:
	# Stock Seicento at 40 m/s into a 15 m/s hairpin, decel = 9.0 m/s²:
	# d_brake = (1600 - 225) / 18 = 76.4 m; red <= 85.6 m; yellow <= 107.6 m; green > 107.6 m.
	check("far from corner is GREEN",
		PaceNotes.brake_zone(40.0, 150.0, 15.0, 9.0) == PaceNotes.BrakeZone.GREEN)
	check("approaching braking point is YELLOW",
		PaceNotes.brake_zone(40.0, 95.0, 15.0, 9.0) == PaceNotes.BrakeZone.YELLOW)
	check("at/inside braking point is RED",
		PaceNotes.brake_zone(40.0, 75.0, 15.0, 9.0) == PaceNotes.BrakeZone.RED)
	check("already at corner speed is GREEN even at dist=0",
		PaceNotes.brake_zone(15.0, 0.0, 15.0, 9.0) == PaceNotes.BrakeZone.GREEN)
	check("below corner speed is GREEN",
		PaceNotes.brake_zone(12.0, 5.0, 15.0, 9.0) == PaceNotes.BrakeZone.GREEN)
	check("small excess (< BRAKE_MIN_DROP) right at corner is YELLOW (lift, not hard brake)",
		PaceNotes.brake_zone(17.5, 2.0, 15.0, 9.0) == PaceNotes.BrakeZone.YELLOW)
	check("infinite corner speed (straight) is GREEN",
		PaceNotes.brake_zone(90.0, 0.0, INF, 20.0) == PaceNotes.BrakeZone.GREEN)

	# Lower decel (wet/snow) turns RED earlier than dry decel at the same distance and speed.
	var dry_z := PaceNotes.brake_zone(38.0, 90.0, 15.0, 9.0)
	var wet_z := PaceNotes.brake_zone(38.0, 90.0, 15.0, 5.0)
	check("wet/low decel escalates to RED before dry decel",
		wet_z == PaceNotes.BrakeZone.RED and dry_z < PaceNotes.BrakeZone.RED,
		"(dry=%d wet=%d)" % [dry_z, wet_z])

	# Monotonicity: decreasing distance never downgrades severity; increasing speed never downgrades severity.
	var prev_z := PaceNotes.BrakeZone.GREEN
	for d in [200.0, 140.0, 100.0, 80.0, 40.0, 0.0]:
		var z := PaceNotes.brake_zone(40.0, d, 15.0, 9.0)
		check("zone non-decreasing as distance shrinks (d=%.0f)" % d, z >= prev_z, "(%d < %d)" % [z, prev_z])
		prev_z = z
	prev_z = PaceNotes.BrakeZone.GREEN
	for v in [10.0, 15.0, 20.0, 30.0, 40.0, 55.0]:
		var z := PaceNotes.brake_zone(v, 50.0, 15.0, 9.0)
		check("zone non-decreasing as speed rises (v=%.0f)" % v, z >= prev_z, "(%d < %d)" % [z, prev_z])
		prev_z = z

	# Hypercar at 80 m/s requires much earlier braking than stock at 38 m/s into the same 15 m/s corner.
	var lim_stock := PaceNotes.brake_zone_distances(38.0, 15.0, PaceNotes.brake_decel(38.0, 15.0, 1.0, 0.0, 1.0))
	var lim_hyper := PaceNotes.brake_zone_distances(80.0, 18.0, PaceNotes.brake_decel(80.0, 18.0, 1.25, 0.0016, 1.0))
	check("hypercar red zone starts earlier than stock car's", lim_hyper.x > lim_stock.x + 20.0,
		"(hyper %.0f m, stock %.0f m)" % [lim_hyper.x, lim_stock.x])
	print("  dynamic red zone lead into tight corner: stock %.0f m @ 38 m/s, hypercar %.0f m @ 80 m/s" % [lim_stock.x, lim_hyper.x])

func _test_brake_cue() -> void:
	# Pure PaceNotes.brake_cue with brake_input & actual_decel
	# v = 40 m/s, v_corner = 15 m/s, decel = 9.0 m/s², dist = 80 m -> d_brake = 76.4 m, a_req = 8.59 m/s²
	var cue_far := PaceNotes.brake_cue(160.0, 40.0, 15.0, 9.0, 0.0, 0.0)
	check("BRAKE cue off far before braking point", not cue_far.brake)

	var cue_coast := PaceNotes.brake_cue(80.0, 40.0, 15.0, 9.0, 0.0, 0.0)
	check("BRAKE cue ON at braking point when not braking", cue_coast.brake and cue_coast.zone == PaceNotes.BrakeZone.RED)

	var cue_braking := PaceNotes.brake_cue(80.0, 40.0, 15.0, 9.0, 0.9, 9.2)
	check("BRAKE cue goes QUIET when already braking hard enough", not cue_braking.brake and cue_braking.zone == PaceNotes.BrakeZone.RED)

	var cue_light := PaceNotes.brake_cue(80.0, 40.0, 15.0, 9.0, 0.2, 2.0)
	check("BRAKE cue stays ON when only lightly tapping brake", cue_light.brake)

	var cue_ice := PaceNotes.brake_cue(80.0, 40.0, 15.0, 9.0, 1.0, 2.5)
	check("BRAKE cue stays ON when pedal is down but actual decel is too low", cue_ice.brake)

	var cue_slow := PaceNotes.brake_cue(20.0, 15.0, 15.0, 9.0, 0.0, 0.0)
	check("BRAKE cue QUIET when already at corner speed", not cue_slow.brake)

	var cue_slower := PaceNotes.brake_cue(10.0, 12.0, 15.0, 9.0, 0.0, 0.0)
	check("BRAKE cue QUIET when slower than corner speed", not cue_slower.brake)

	# End-to-end RaceHud._live_brake_state on GP circuit + agreement with fill_arrow_zones
	var race := _race("gp", "stock")
	race.phase = "racing"
	var p := race.player
	p.mode = "race"
	p.control = "free"
	p.phys = PhysState.new()
	var tr := race.track
	var corner_v := PaceNotes.corner_profile(tr, race.brake_k, race.brake_aero, race._loose)
	var slowest := _slowest_s(tr, corner_v)
	var s_apex: float = slowest[0]
	var v_apex: float = slowest[1]

	var hud := RaceHud.new()
	hud.race = race
	var cd := CoDriver.new(race)
	cd.voice_on = false
	hud.co_driver = cd

	# 1. Approaching apex too fast, off the brakes -> BRAKE ON
	p.s = tr.wrap_s(s_apex - 45.0)
	p.speed = 38.0
	p.v = 38.0
	p.brake = 0.0
	p.phys.ax_f = 0.0
	cd.update(true, 1)
	var st_fast := hud._live_brake_state(cd.current())
	check("HUD BRAKE cue lights 45 m before GP slowest apex at 38 m/s off brakes", bool(st_fast.brake_alert))

	# 2. 78 m before apex (just inside the braking zone): off brakes -> ON; braking at 10.5 m/s² -> QUIET!
	p.s = tr.wrap_s(s_apex - 78.0)
	p.speed = 38.0
	p.v = 38.0
	p.brake = 0.0
	p.phys.ax_f = 0.0
	var st_78_off := hud._live_brake_state(cd.current())
	check("HUD BRAKE cue lights 78 m before apex at 38 m/s off brakes", bool(st_78_off.brake_alert))
	p.brake = 1.0
	p.phys.ax_f = -10.5
	var st_78_brk := hud._live_brake_state(cd.current())
	check("HUD BRAKE cue goes QUIET 78 m before apex while braking at 10.5 m/s²", not bool(st_78_brk.brake_alert))
	# And if way too late (45 m before apex at 38 m/s), 10.5 m/s² is NOT enough -> stays ON
	p.s = tr.wrap_s(s_apex - 45.0)
	var st_45_late := hud._live_brake_state(cd.current())
	check("HUD BRAKE cue stays ON when braking way too late (decel insufficient)", bool(st_45_late.brake_alert))

	# 3. Already slow enough before the apex, off brakes -> BRAKE QUIET
	p.s = tr.wrap_s(s_apex - 15.0)
	p.speed = v_apex
	p.v = v_apex
	p.brake = 0.0
	p.phys.ax_f = 0.0
	var st_slow := hud._live_brake_state(cd.current())
	check("HUD BRAKE cue stays QUIET when already at corner speed", not bool(st_slow.brake_alert))

	# 4. Corner exit (past apex, accelerating) -> BRAKE QUIET even if pace note is still live
	p.s = tr.wrap_s(s_apex + 18.0)
	p.speed = v_apex + 7.0
	p.v = v_apex + 7.0
	p.brake = 0.0
	p.phys.ax_f = 2.0
	var st_exit := hud._live_brake_state(cd.current())
	check("HUD BRAKE cue stays QUIET on corner exit past the apex", not bool(st_exit.brake_alert))

	# 5. Full-lap agreement check: HUD BRAKE (off brakes) == RED arrow at p.s at every 10 m step around GP
	var mu := race.plan_grip(p)
	var zones := PackedInt32Array()
	zones.resize(1)
	var mismatches := 0
	var red_count := 0
	p.brake = 0.0
	p.phys.ax_f = 0.0
	p.speed = 38.0
	p.v = 38.0
	var s_walk := 0.0
	while s_walk < tr.L:
		p.s = s_walk
		var hud_on := bool(hud._live_brake_state([]).brake_alert)
		PaceNotes.fill_arrow_zones(tr, corner_v, s_walk, 5.0, 1, 38.0, race.brake_k, race.brake_aero, mu, zones)
		var arrow_red := zones[0] == PaceNotes.BrakeZone.RED
		if arrow_red:
			red_count += 1
		if hud_on != arrow_red:
			mismatches += 1
		s_walk += 10.0
	check("HUD BRAKE cue and RED arrows agree 100%% around the entire GP lap", mismatches == 0 and red_count > 5,
		"(mismatches=%d, red_samples=%d)" % [mismatches, red_count])

	hud.free()
	race.dispose()

func _test_world_arrows() -> void:
	var race := _race("gp", "stock")
	var world = WORLD.new()
	world.set_track(race.track)
	check("racing_line_node is a MultiMeshInstance3D (static line mesh replaced)",
		world.racing_line_node is MultiMeshInstance3D and world.racing_line_node.name == "RacingLine")
	check("overview shows 0 arrows before race starts",
		world._racing_arrows_mm != null and world._racing_arrows_mm.visible_instance_count == 0)

	world.set_race(race)
	race.phase = "racing"
	var p := race.player
	p.mode = "race"
	p.control = "free"
	var tr := race.track
	var corner_v := PaceNotes.corner_profile(tr, race.brake_k, race.brake_aero, race._loose)
	var slowest := _slowest_s(tr, corner_v)
	var s_apex: float = slowest[0]

	# Place player 80 m before GP's slowest corner
	p.s = tr.wrap_s(s_apex - 80.0)
	world._focus_car = p
	world._focus_s = p.s

	# Slow speed (8 m/s) in full mode: arrows visible, all GREEN, pointing forward, fading with distance
	p.speed = 8.0
	p.v = 8.0
	world.set_racing_line_mode("full")
	var mm: MultiMesh = world._racing_arrows_mm
	var buf: PackedFloat32Array = world._rl_buffer
	var n_slow := mm.visible_instance_count
	check("full mode at 8 m/s draws chevrons ahead of car", n_slow >= 20 and n_slow <= WORLD.ARROW_POOL, "(count=%d)" % n_slow)
	var all_green := true
	for i in n_slow:
		var o := i * 16
		var c := Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15])
		if c.g <= c.r:
			all_green = false
			break
	check("at 8 m/s approaching corner every chevron is GREEN", all_green)
	if n_slow >= 6:
		var mid_a := buf[4 * 16 + 15]
		var far_a := buf[(n_slow - 1) * 16 + 15]
		check("distant chevrons fade out with distance", far_a < mid_a, "(mid=%.2f far=%.2f)" % [mid_a, far_a])
		# Check nearest chevron points forward along the track direction (-basis.z is stored at +2, +6, +10 negated)
		var arrow_fwd := Vector3(-buf[2], -buf[6], -buf[10]).normalized()
		var s_check := ceilf((p.s + WORLD.ARROW_START) / WORLD.ARROW_SPACING) * WORLD.ARROW_SPACING
		var tx := tr.sample(tr.TX, s_check)
		var ty := tr.sample(tr.TY, s_check)
		var track_fwd := Vector3(tx, 0.0, ty).normalized()
		check("chevron points along direction of travel", arrow_fwd.dot(track_fwd) > 0.7,
			"(dot=%.2f)" % arrow_fwd.dot(track_fwd))

	# Fast speed (40 m/s) at same spot: RED chevrons appear dynamically!
	p.speed = 40.0
	p.v = 40.0
	world._update_racing_arrows()
	var n_fast := mm.visible_instance_count
	var reds := 0
	var yellows := 0
	for i in n_fast:
		var o := i * 16
		var c := Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15])
		if c.r > 0.8 and c.g < 0.4:
			reds += 1
		elif c.r > 0.8 and c.g > 0.6:
			yellows += 1
	check("at 40 m/s approaching corner RED chevrons appear dynamically", reds > 0,
		"(reds=%d yellows=%d total=%d)" % [reds, yellows, n_fast])

	# Braking-only mode: hides green arrows (0 visible at 8 m/s; only yellow/red visible at 40 m/s)
	world.set_racing_line_mode("braking")
	var n_brk_fast := mm.visible_instance_count
	var any_green := false
	for i in n_brk_fast:
		var o := i * 16
		var c := Color(buf[o + 12], buf[o + 13], buf[o + 14], buf[o + 15])
		if c.g > 0.7 and c.r < 0.4:
			any_green = true
			break
	check("braking mode at 40 m/s shows only braking/lift chevrons (no green)", n_brk_fast > 0 and n_brk_fast < n_fast and not any_green,
		"(braking=%d full=%d any_green=%s)" % [n_brk_fast, n_fast, str(any_green)])

	p.speed = 8.0
	p.v = 8.0
	world._update_racing_arrows()
	check("braking mode at 8 m/s (no braking needed) hides all chevrons", mm.visible_instance_count == 0,
		"(count=%d)" % mm.visible_instance_count)

	# Off mode & toggle
	p.speed = 40.0
	p.v = 40.0
	world.set_racing_line_mode("off")
	check("off mode hides racing_line_node and emits 0 chevrons",
		not world.racing_line_node.visible and mm.visible_instance_count == 0)
	var toggled_on: bool = world.toggle_racing_line()
	check("toggle_racing_line turns chevrons back on", toggled_on and world.racing_line_node.visible and mm.visible_instance_count > 0)

	# Pit lane hides chevrons
	p.mode = "pit"
	world._update_racing_arrows()
	check("pit lane hides chevrons", mm.visible_instance_count == 0)
	p.mode = "race"

	# Per-frame performance measurement over 500 frames (moving around GP at 38 m/s)
	world.set_racing_line_mode("full")
	p.speed = 38.0
	p.v = 38.0
	var iters := 500
	var t0 := Time.get_ticks_usec()
	for k in iters:
		world._focus_s = tr.wrap_s(float(k) * 7.5)
		world._update_racing_arrows()
	var avg_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(iters)
	check("dynamic arrow update is fast (< 1.0 ms/frame)", avg_ms < 1.0, "(%.3f ms/frame)" % avg_ms)
	print("  dynamic racing-line chevron update: %.3f ms/frame (%d frames, %d pool)" % [avg_ms, iters, WORLD.ARROW_POOL])

	world.free()
	race.dispose()
