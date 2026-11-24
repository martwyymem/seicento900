## The campaign lives in the open world (roadmap E, user 2026-11-24): the missions' live-event medal gate
## (Missions.MEDALS_NEEDED, old saves kept), the objective the panel top left shows and the GPS follows
## (CampaignObjective), the results of a stage leading back to Brzeszcze instead of NEXT STAGE (Game.campaign_result_actions),
## the one Away Races gate for the stages abroad and the trip there (AwayCutscene), on a campaign save of this suite's own.
extends RefCounted

var completed := false
var errors: Array[String] = []

const TEST_SAVE := "test_campaign_world.json"
const GAME := preload("res://scripts/ui/game.gd")

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	Brain.use_disk = false
	LapRecords.use_disk = false
	var saved_file := Campaign.save_file
	Campaign.save_file = TEST_SAVE
	_medal_data()
	_medal_gate()
	_old_saves()
	_objective()
	_results()
	_cutscene("train")
	_cutscene("plane")
	await _world()
	Campaign.save_file = saved_file
	DirAccess.remove_absolute(SaveData.path(TEST_SAVE))
	completed = true
	return errors

func _write(prog: Dictionary) -> Dictionary:
	Campaign.save_progress(prog)
	return Campaign.load_progress()

## Wins the stages 0..n-1 (as the campaign records them).
func _win_to(n: int) -> Dictionary:
	Campaign.reset_progress()
	for i in n:
		Campaign.record_result(i, 1)
	return Campaign.load_progress()

func _medal_data() -> void:
	for m in Missions.MISSIONS:
		check(Missions.MEDALS_NEEDED.has(String(m.id)) and int(Missions.MEDALS_NEEDED[String(m.id)]) > 0,
			"mission %s has no live-event medal requirement" % m.id)
	var order := Missions.play_order()
	check(order.size() == Missions.MISSIONS.size(), "play_order lists %d missions" % order.size())
	check(Missions.medals_needed(order[0]) == 2, "the first mission should need 2 medal points (2 bronze), not %d" % Missions.medals_needed(order[0]))
	for k in range(1, order.size()):
		check(Missions.medals_needed(order[k]) > Missions.medals_needed(order[k - 1]),
			"the medal ladder does not rise at %s (%d after %d)" % [Missions.get_def(order[k]).id, Missions.medals_needed(order[k]),
			Missions.medals_needed(order[k - 1])])
	check(Missions.medal_points({"bronze": 2, "silver": 1, "gold": 1, "done": 4}) == 7, "bronze 1 + silver 2 + gold 3 points")
	check(Missions.medal_points({"bronze": "x", "silver": -3, "gold": 1.0}) == 3, "a damaged medal count counts as none")
	check(Missions.medal_points({}) == 0, "no medals, no points")

## A new campaign is gated: the quarter mile opens with stage 1 won AND 2 points; its card, the story's phone message
## and the dev "open everything" follow.
func _medal_gate() -> void:
	var prog := _win_to(0)
	check(Missions.gated(prog) and int(prog.get("gate", 0)) == Campaign.GATE, "a new campaign is not gated: %s" % prog)
	var drag := Missions.index_of("drag_quarter")
	check(not Missions.is_unlocked(drag, prog, 99), "the quarter mile opens before stage 1 is won")
	prog = _win_to(1)
	check(Missions.stage_reached(drag, prog), "stage 1 won does not reach the quarter mile")
	check(not Missions.is_unlocked(drag, prog, 0) and not Missions.is_unlocked(drag, prog, 1), "the quarter mile opens without 2 medal points")
	check(Missions.is_unlocked(drag, prog, 2) and Missions.is_unlocked(drag, prog, 5), "the quarter mile stays shut with 2 medal points")
	check(Missions.medal_locked(drag, prog, 1) and not Missions.medal_locked(drag, prog, 2), "medal_locked")
	check(not Missions.medal_locked(Missions.index_of("knockout_bor"), prog, 0), "a mission whose stage is not won reads as medal-locked")
	var c := Missions.card(drag, 1, 1)
	check(String(c[3]).contains("1/2") and String(c[3]).begins_with("LOCKED"), "the locked mission's card hint: %s" % c[3])
	check(String(c[2]).contains("1/2"), "the locked mission's card body does not say what it needs")
	check(not String(Missions.card(drag, 1, 2)[3]).begins_with("LOCKED"), "the card stays locked with the medals")
	# the phone message for the mission waits for the medals
	check(not "open_drag_quarter" in Story.pending(prog, 0, false, 1), "the quarter mile's phone message comes before its medals")
	check("open_drag_quarter" in Story.pending(prog, 0, false, 2), "no phone message once the quarter mile opens")
	check(Story.next_step(Campaign.load_progress(), 0, 1).contains("Stage 2"), "the story's next step is not the next stage")
	# a raced (or won) mission needs no medals any more, whatever they are now
	Missions.record(drag, {"pos": 4, "success": false})
	prog = Campaign.load_progress()
	check(Missions.is_unlocked(drag, prog, 0), "a mission already raced locks again without the medals")
	Missions.record(drag, {"pos": 1, "success": true})
	check(Missions.is_unlocked(drag, Campaign.load_progress(), 0) and Missions.is_cleared(drag), "a won mission locks again")

## A save from before the gate: what its stages had opened stays open, the rest waits for medals from then on; won stays
## won. A damaged gate value never locks anybody out.
func _old_saves() -> void:
	var t: Array = []
	var bor := Campaign.index_of("stage_3") # the stages up to and through Bór won
	var best := {}
	for i in bor + 1:
		t.append(String(Campaign.STAGES[i].trophy))
		best[str(i)] = 1
	var prog := _write({"unlocked": bor + 1, "best_pos": best, "trophies": t, "arc": Campaign.ARC,
		"missions": {"knockout_bor": {"cleared": true, "best": 1}}})
	check(int(prog.get("gate", 0)) == Campaign.GATE, "an old save did not take the gate on load")
	for id in ["drag_quarter", "sprint_rajsko", "sprint_s1"]:
		check(Missions.is_unlocked(Missions.index_of(id), prog, 0), "old save: %s (reached before the gate) needs medals now" % id)
	check(not Missions.is_unlocked(Missions.index_of("drift_kopalnia"), prog, 99), "old save: a mission past its stages opened")
	check(Missions.is_cleared(Missions.index_of("knockout_bor"), prog), "old save: a won mission is not won any more")
	# written back it keeps that, and the next mission (after stage 4) waits for its medals
	Campaign.save_progress(prog)
	Campaign.record_result(bor + 1, 1)
	prog = Campaign.load_progress()
	var kop := Missions.index_of("drift_kopalnia")
	check(Missions.is_unlocked(Missions.index_of("sprint_s1"), prog, 0), "old save: written back, an open mission locked")
	check(not Missions.is_unlocked(kop, prog, Missions.medals_needed(kop) - 1) and Missions.is_unlocked(kop, prog, Missions.medals_needed(kop)),
		"old save: the first mission after the gate does not wait for its %d points" % Missions.medals_needed(kop))
	# a hand-made save without the key (as older tests write): ungated
	check(Missions.is_unlocked(Missions.index_of("drag_quarter"), {"unlocked": 1, "trophies": [t[0]]}, 0), "a save without the gate key is gated")
	prog = _write({"unlocked": 1, "trophies": [t[0]], "gate": "junk"})
	check(Missions.is_unlocked(Missions.index_of("drag_quarter"), prog, 0), "a damaged gate value locked a mission")

func _objective() -> void:
	var prog := _win_to(0)
	var o := CampaignObjective.current(prog, 0, 0)
	check(o.kind == "stage" and int(o.index) == 0 and String(o.line).begins_with("Stage 1") and String(o.line).contains("drive to"),
		"new campaign objective: %s" % o)
	check(String(o.side) == "", "new campaign: a side objective %s" % o.side)
	prog = _win_to(1)
	o = CampaignObjective.current(prog, 0, 1)
	check(o.kind == "stage" and int(o.index) == 1, "after stage 1: %s" % o)
	check(String(o.side).contains("1 more live-event medal point") and String(o.side).contains("Ćwierć Mili"), "after stage 1 with 1 point, side: %s" % o.side)
	o = CampaignObjective.current(prog, 0, 2)
	check(String(o.side).begins_with("Mission open") and String(o.side).contains("Ćwierć Mili"), "after stage 1 with 2 points, side: %s" % o.side)
	# Monza is abroad: the objective sends you to the Away Races gate
	var monza := Campaign.index_of("stage_monza")
	prog = _win_to(monza)
	o = CampaignObjective.current(prog, 0, 999)
	check(o.kind == "stage" and int(o.index) == monza and String(o.line).contains("Away Races"), "Monza's objective: %s" % o)
	check(CampaignObjective.away_stage(prog, 0) == monza, "the gate holds %d, not Monza" % CampaignObjective.away_stage(prog, 0))
	check(CampaignObjective.stage_is_away(monza) and not CampaignObjective.stage_is_away(0) and not CampaignObjective.stage_is_away(Campaign.STAGES.size() - 1),
		"stage_is_away")
	for st in Campaign.STAGES:
		if String(st.track) in ["monza", "nordschleife", "lemans", "tokyo"]:
			check(CampaignObjective.is_away(String(st.track)), "%s is not raced from the Away Races gate" % st.track)
	# every stage short of the Goliath won and no mission raced: the first medal-locked mission, then a mission
	var last := Campaign.STAGES.size() - 1
	prog = _win_to(last)
	o = CampaignObjective.current(prog, 0, 0)
	check(o.kind == "medals" and int(o.index) == Missions.index_of("drag_quarter") and String(o.line).contains("(0/2)"), "medals objective: %s" % o)
	o = CampaignObjective.current(prog, 0, 2)
	check(o.kind == "mission" and int(o.index) == Missions.index_of("drag_quarter") and String(o.line).contains("beacon"), "mission objective: %s" % o)
	check(CampaignObjective.away_stage(prog, 0) == Campaign.index_of("stage_9"), "with every abroad stage won the gate holds the last one (Tokyo)")
	for idx in Missions.play_order():
		Missions.record(idx, {"pos": 1, "success": true, "tier": 3, "score": 99999, "time": 30.0})
	prog = Campaign.load_progress()
	o = CampaignObjective.current(prog, 0, 999)
	check(o.kind == "fans" and String(o.line).contains("Goliath"), "the Goliath's fans objective: %s" % o)
	var top := int(FanLevels.THRESHOLDS[FanLevels.THRESHOLDS.size() - 1])
	o = CampaignObjective.current(prog, top, 999)
	check(o.kind == "stage" and int(o.index) == last, "with the fans the Goliath is the objective: %s" % o)
	(prog.trophies as Array).append(String(Campaign.STAGES[last].trophy))
	o = CampaignObjective.current(prog, top, 999)
	check(o.kind == "done" and String(o.line) != "", "a finished campaign: %s" % o)

func _results() -> void:
	for cleared in [true, false]:
		for last in [false, true]:
			var acts: Array = GAME.campaign_result_actions(cleared, last, true)
			var labels := acts.map(func(a): return String(a[0]))
			check(not acts.is_empty() and String(acts[0][1]) == "world" and String(acts[0][0]).contains("BRZESZCZE"),
				"campaign results (cleared %s): the first button is not back to Brzeszcze: %s" % [cleared, labels])
			check(not labels.any(func(l): return String(l).contains("NEXT")), "campaign results still offer %s" % [labels])
			check(acts.any(func(a): return String(a[1]) == "retry"), "campaign results lost the retry: %s" % [labels])
	check(String(GAME.campaign_result_actions(false, false, true)[1][0]) == "RETRY STAGE", "a missed stage is retried with RETRY STAGE")
	check(GAME.campaign_result_actions(true, false, false).is_empty(), "without the open world the old flow should stand")

func _cutscene(by: String) -> void:
	var cs := AwayCutscene.new()
	cs.setup(by, {}, 0.8)
	check(cs.by == by and cs.fade > 0.99 and not cs.done, "%s trip: does not start from black" % by)
	var dt := 1.0 / 60.0
	var x0 := cs.car_xform.origin.x
	var mid_fade := 1.0
	var aboard_y := 0.0
	var steps := 0
	var prev_x := x0
	var backwards := false
	while not cs.done and steps < 2000:
		cs.step(dt)
		steps += 1
		if absf(cs.t - 2.0) < dt * 0.5:
			mid_fade = cs.fade
		if absf(cs.t - AwayCutscene.DRIVE_TO - 0.05) < dt * 0.5:
			aboard_y = cs.car_xform.origin.y
		if cs.car_xform.origin.x < prev_x - 0.001:
			backwards = true
		prev_x = cs.car_xform.origin.x
		var to_car := cs.car_xform.origin - cs.cam_xform.origin
		if to_car.length() > 1.0 and (-cs.cam_xform.basis.z).dot(to_car.normalized()) < 0.5 and cs.t < AwayCutscene.DRIVE_TO:
			check(false, "%s trip: the camera looks away from the car at %.2f s" % [by, cs.t])
			break
	check(cs.done and absf(cs.t - AwayCutscene.LENGTH) < 0.05, "%s trip: %d steps, done %s at %.2f s" % [by, steps, cs.done, cs.t])
	check(mid_fade < 0.01 and cs.fade > 0.99, "%s trip: the fade (%.2f in the middle, %.2f at the end)" % [by, mid_fade, cs.fade])
	check(not backwards and cs.car_xform.origin.x - x0 > 30.0, "%s trip: the car went %.1f m (backwards %s)" % [by, cs.car_xform.origin.x - x0, backwards])
	check(absf(aboard_y - AwayCutscene.DECK) < 0.15, "%s trip: the car is at %.2f m once aboard, not on the deck" % [by, aboard_y])
	check(cs.car_xform.origin.distance_to(AwayCutscene.SET_ORIGIN) < 2000.0 and AwayCutscene.SET_ORIGIN.length() > 42000.0 + 6000.0,
		"%s trip: the set is not out beyond the camera's reach from the town" % by)
	cs.free()
	# skipped a second in: black and done within the skip fade
	cs = AwayCutscene.new()
	cs.setup(by)
	for i in 60:
		cs.step(dt)
	cs.skip()
	var n := 0
	while not cs.done and n < 600:
		cs.step(dt)
		n += 1
	check(cs.done and cs.skipped and n * dt <= AwayCutscene.SKIP_FADE + 2.0 * dt and cs.fade > 0.99, "%s trip: a skip took %.2f s" % [by, n * dt])
	cs.free()

## A partly built open world (no town meshes): the one Away Races gate, the objective panel and GPS on it, the medal
## beacons, and entering the gate plays the trip and asks for the stage.
func _world() -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	check(map != null, "the map did not load")
	if map == null:
		return
	var world_file := SaveData.path(WorldProgress.SAVE_FILE)
	var saved_world: Variant = FileAccess.get_file_as_string(world_file) if FileAccess.file_exists(world_file) else null
	var monza := Campaign.index_of("stage_monza")
	var prog := _win_to(monza)
	for idx in Missions.play_order():
		Story.mark_seen(["open_" + String(Missions.get_def(idx).id)])
	Story.mark_seen([Story.before_key(monza)]) # (the story card would come first: tests/test_story.gd covers it)
	var tree := Engine.get_main_loop() as SceneTree
	var ow := OpenWorld.new()
	ow.size = Vector2(1600, 900)
	tree.root.add_child(ow)
	await tree.process_frame
	ow.map = map
	ow.progress = WorldProgress.new()
	ow.world = Node3D.new()
	ow.add_child(ow.world)
	ow.route_mesh = MeshInstance3D.new()
	ow.world.add_child(ow.route_mesh)
	ow.builder = TownBuilder.new(map, ow.world)
	ow.drive = FreeCar.new(map)
	var fest: Array = map.spots.festival
	ow.drive.place(Vector2(fest[0], fest[1]) + Vector2(300.0, 0.0), 0.0)
	ow._refresh_events()
	var aways := ow.events.filter(func(e): return e.has("away"))
	check(aways.size() == 1, "%d Away Races gates" % aways.size())
	for e in ow.events:
		if not e.has("away") and not e.has("mission") and not e.has("live"):
			check(not CampaignObjective.stage_is_away(int(e.stage)), "the stage abroad %s has a beacon of its own" % e.title)
	if aways.size() == 1:
		var g: Dictionary = aways[0]
		check(int(g.stage) == monza and g.open and not g.done, "the gate holds %s (open %s)" % [g.title, g.open])
		check(not map.road_at(g.pos.x, g.pos.y, -INF, 2.0).is_empty(), "the Away Races gate %s is not on a road" % g.pos)
		var fpos := Vector2(fest[0], fest[1])
		for e in ow.events:
			if e != g and not e.has("live"):
				check((e.pos as Vector2).distance_to(g.pos) > 14.0, "the gate stands on top of %s" % e.title)
		check(ow.builder.beacon_nodes.has("away"), "the gate has no beacon")
		check(fpos.distance_to(g.pos) < 120.0, "the gate is %.0f m from the Fest" % fpos.distance_to(g.pos))
	# the objective: on the panel, the GPS on the gate
	check(ow.objective.kind == "stage" and int(ow.objective.index) == monza, "the world's objective: %s" % ow.objective)
	check(ow.hud.objective_line.text == String(ow.objective.line) and ow.hud.objective_line.text.contains("Away Races"),
		"the objective panel says '%s'" % ow.hud.objective_line.text)
	check(ow.hud.objective_shown(), "the objective panel is hidden")
	var gi := ow._next_open_event()
	check(gi >= 0 and ow.events[gi].has("away"), "the GPS goes to %s, not the gate" % (ow.events[gi].title if gi >= 0 else "nothing"))
	ow.hud._layout()
	check(ow.hud.objective_plate.position.y <= ow.hud.stats_plate.position.y - ow.hud.objective_plate.size.y + 0.5,
		"the fans card is not under the objective panel")
	check(ow.hud.objective_plate.position.x < 400.0 and ow.hud.objective_plate.position.y < 200.0, "the objective panel is not top left: %s" % ow.hud.objective_plate.position)
	ow.hud.show_objective(false)
	check(not ow.hud.objective_shown(), "show_objective(false) left it up")
	ow.hud.show_objective(true)
	# the medal-locked missions stand greyed with their beacon, not open
	var locked := ow.events.filter(func(e): return e.has("mission") and bool(e.get("medals", false)))
	check(not locked.is_empty() and locked.all(func(e): return not e.open), "no greyed medal-locked missions on the map")
	if not locked.is_empty():
		check(ow.builder.beacon_nodes.has("mission_%d" % int(locked[0].mission)), "a medal-locked mission has no beacon")
	# two bronze medals: the quarter mile opens with a banner
	var drag := Missions.index_of("drag_quarter")
	var before := Missions.medal_points(ow.progress.live)
	ow.progress.record_live("sprint", 1)
	ow.progress.record_live("drift", 1)
	ow._medals_opened(Campaign.load_progress(), before)
	var dq := ow.events.filter(func(e): return e.has("mission") and int(e.stage) == drag)
	check(not dq.is_empty() and dq[0].open and not bool(dq[0].get("medals", false)), "two bronze medals did not open the quarter mile")
	var banner := false
	for b in ow.hud.banners.get_children():
		banner = banner or String(b.get_meta("key", "")).begins_with("MISSION OPEN")
	check(banner, "no MISSION OPEN banner")
	# entering the gate: the trip, then the stage
	var asked := []
	ow.stage_requested.connect(func(i: int): asked.append(i))
	ow.active_event = -1
	for k in ow.events.size():
		if ow.events[k].has("away"):
			ow.active_event = k
	ow._start_active_event()
	check(ow.cutscene != null and not ow.hud.visible and asked.is_empty(), "entering the gate did not start the trip")
	var steps := 0
	while ow.cutscene != null and steps < 600:
		ow._update_cutscene(1.0 / 30.0)
		steps += 1
	check(asked == [monza], "after the trip the world asked for %s, not Monza (%d)" % [asked, monza])
	check(ow.cutscene == null and ow.hud.visible and steps * (1.0 / 30.0) < AwayCutscene.LENGTH + 0.2, "the trip did not end cleanly (%d steps)" % steps)
	# skipped: straight to the stage
	asked.clear()
	ow._start_active_event()
	ow._update_cutscene(0.5)
	ow.cutscene.skip()
	for i in 30:
		if ow.cutscene == null:
			break
		ow._update_cutscene(1.0 / 30.0)
	check(asked == [monza], "a skipped trip asked for %s" % [asked])
	# back from a stage abroad (Monza, or Tokyo while the gate holds another): the car comes back at the gate
	for st in [monza, Campaign.index_of("stage_9")]:
		var at := ow.spawn_event(st)
		check(at >= 0 and ow.events[at].has("away"), "back from %s the car is not put back at the gate" % Campaign.STAGES[st].id)
	var home := ow.spawn_event(0)
	check(home >= 0 and not ow.events[home].has("away") and int(ow.events[home].stage) == 0, "back from stage 1 the car is not at its beacon")
	ow.queue_free()
	await tree.process_frame
	# (OpenWorld._save wrote the sandbox's open-world save: put it back as it was)
	if saved_world == null:
		DirAccess.remove_absolute(SaveData.path(WorldProgress.SAVE_FILE))
	else:
		var f := FileAccess.open(SaveData.path(WorldProgress.SAVE_FILE), FileAccess.WRITE)
		if f:
			f.store_string(String(saved_world))
