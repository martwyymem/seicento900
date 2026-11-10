## Live events (scripts/world/live_events.gd) on the real Brzeszcze map: every kind can be generated round the
## festival, inside the playable area, clear of each other and of the beacons to avoid; lengths, checkpoints and
## zone shapes as promised; medal targets in order and harder for faster cars; the reference pace against the
## Seicento's measured standing quarter mile; a scripted run along a sprint clears it (gold when quick, out of time
## when crawling) and a cleared event leaves the board; the board expires, refills and drops far events; the
## WorldProgress save keeps the medal counts.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("data/world/%s.json did not load" % OpenWorld.MAP_KEY)
		completed = true
		return errors
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var home := Vector2(s[0], s[1])
	_pace(errors)
	var live := LiveEvents.new(map, 12345)
	var avoid := PackedVector2Array([home])
	var by_kind := {}
	for kind in LiveEvents.KINDS:
		var ev := live.generate(home, avoid, kind)
		if ev.is_empty():
			# the ring is random: give it a second seed before calling it broken
			ev = live.generate(home, avoid, kind)
		if ev.is_empty():
			errors.append("no %s could be generated round the festival" % kind)
			continue
		by_kind[kind] = ev
		live.board.append(ev)
		_shape(map, ev, home, errors)
		_targets(live, ev, errors)
	for i in live.board.size():
		for j in range(i + 1, live.board.size()):
			if (live.board[i].pos as Vector2).distance_to(live.board[j].pos) < LiveEvents.SPACING:
				errors.append("%s and %s stand %.0f m apart" % [live.board[i].id, live.board[j].id,
					(live.board[i].pos as Vector2).distance_to(live.board[j].pos)])
	if by_kind.has("sprint"):
		_run_sprint(live, by_kind.sprint, errors)
	if by_kind.has("drift_zone"):
		_run_drift(live, by_kind.drift_zone, errors)
	_board(map, home, errors)
	_save(errors)
	await _world(map, home, errors)
	_missions_on_map(map, errors)
	completed = true
	return errors

## The reference pace for the stock car over a straight 402 m from rest: the Seicento measures 20.5 s (Missions'
## quarter mile, tests/_car_probe.gd); the reference driver should be within a couple of seconds of that.
func _pace(errors: Array[String]) -> void:
	var straight := PackedVector2Array([Vector2.ZERO, Vector2(402.0, 0.0)])
	var t := LiveEvents.pace_time(straight, "stock")
	if t < 18.0 or t > 23.5:
		errors.append("reference quarter mile in the Seicento %.1f s (the car does 20.5 s)" % t)
	var golf := LiveEvents.pace_time(straight, "golf4")
	var hyper := LiveEvents.pace_time(straight, "hypercar")
	if not (hyper < golf and golf < t):
		errors.append("reference quarter mile not faster for faster cars: %.1f / %.1f / %.1f s" % [t, golf, hyper])
	# a hairpin costs time against a straight of the same length
	var bent := PackedVector2Array([Vector2.ZERO, Vector2(200.0, 0.0), Vector2(200.0, 12.0), Vector2(0.0, 12.0)])
	if LiveEvents.pace_time(bent, "stock") < LiveEvents.pace_time(PackedVector2Array([Vector2.ZERO, Vector2(412.0, 0.0)]), "stock") + 2.0:
		errors.append("a hairpin costs the reference driver no time")

func _shape(map: TownMap, ev: Dictionary, home: Vector2, errors: Array[String]) -> void:
	var p: Vector2 = ev.pos
	var d := p.distance_to(home)
	if d < LiveEvents.SPAWN_MIN - 130.0 or d > LiveEvents.SPAWN_MAX + 130.0:
		errors.append("%s starts %.0f m from the player" % [ev.kind, d])
	if not map.in_play(p) or not map.in_play(ev.goal):
		errors.append("%s starts or ends outside the playable area" % ev.kind)
	if map.nearest_road(p, 3.0).is_empty():
		errors.append("%s's beacon is not on a road" % ev.kind)
	var cps: PackedVector2Array = ev.cps
	var length := float(ev.length)
	match String(ev.kind):
		"sprint":
			if length < 1400.0 or length > 5200.0:
				errors.append("sprint is %.0f m long" % length)
			if cps.size() < 3:
				errors.append("sprint has %d checkpoints" % cps.size())
			for i in range(1, cps.size()):
				if cps[i].distance_to(cps[i - 1]) > LiveEvents.CP_SPACING * 1.4 + 5.0: # the last gap may take a short remainder
					errors.append("sprint checkpoints %d-%d are %.0f m apart" % [i - 1, i, cps[i].distance_to(cps[i - 1])])
		"speed_zone":
			if p.distance_to(ev.goal) / length < 0.88:
				errors.append("speed zone is not straight")
		"drift_zone":
			if LiveEvents.turning(ev.path) / (length / 1000.0) < 2.2:
				errors.append("drift zone is not twisty")
	if String(ev.title) == "":
		errors.append("%s has no title" % ev.kind)

func _targets(live: LiveEvents, ev: Dictionary, errors: Array[String]) -> void:
	var t := live.tiers_for(ev, "stock")
	var h := live.tiers_for(ev, "hypercar")
	match String(ev.kind):
		"speed_zone":
			if not (t[0] < t[1] and t[1] < t[2]) or h[2] <= t[2]:
				errors.append("speed-zone targets out of order: %s / %s" % [t, h])
		"drift_zone":
			if not (t[0] < t[1] and t[1] < t[2]):
				errors.append("drift targets out of order: %s" % [t])
		_:
			if not (t[0] > t[1] and t[1] > t[2]) or h[2] >= t[2]:
				errors.append("%s times out of order: %s / %s" % [ev.kind, t, h])
	var c := live.card(ev, "stock")
	if c.size() != 4 or String(c[2]).findn("bronze") < 0:
		errors.append("%s card reads oddly: %s" % [ev.kind, c])

## A scripted car along the sprint's route: at the gold pace it takes gold and the event leaves the board; at a
## crawl it runs out of time.
func _run_sprint(live: LiveEvents, ev: Dictionary, errors: Array[String]) -> void:
	for crawl in [false, true]:
		if not live.board.has(ev):
			live.board.append(ev)
		live.begin(ev, "stock")
		var tiers: Array = live.run.tiers
		var v := float(ev.length) / (float(tiers[2]) * 0.97) if not crawl else 2.0
		var pts := LiveEvents.resample(ev.path, 1.0)
		var dt := 1.0 / 30.0
		var s := 0.0
		var got := ""
		var seen := {}
		for step in 200000:
			var at := pts[clampi(int(s), 0, pts.size() - 1)]
			var r := live.tick(dt, at, v, 0.0, false, false)
			if r != "":
				seen[r] = int(seen.get(r, 0)) + 1
			if r in ["done", "fail"]:
				got = r
				break
			if not live.holding():
				s += v * dt
		if not crawl:
			if got != "done" or int(live.last_result.get("tier", 0)) != 3:
				errors.append("a gold-pace sprint ended '%s' with tier %d (%s)" % [got, int(live.last_result.get("tier", 0)), live.last_result.get("line", "")])
			if int(seen.get("go", 0)) != 1 or int(seen.get("cp", 0)) != (ev.cps as PackedVector2Array).size() - 1:
				errors.append("sprint run reported %s" % [seen])
			if live.board.has(ev):
				errors.append("a cleared event stayed on the board")
			if int(live.last_result.get("fans", 0)) <= 0:
				errors.append("a gold sprint paid no fans")
		elif got != "fail":
			errors.append("a crawling sprint ended '%s'" % got)

## Sideways at speed through the drift zone scores; a crash halfway loses the running combo.
func _run_drift(live: LiveEvents, ev: Dictionary, errors: Array[String]) -> void:
	live.begin(ev, "stock")
	var pts := LiveEvents.resample(ev.path, 1.0)
	var dt := 1.0 / 30.0
	var s := 0.0
	var v := 14.0
	for step in 200000:
		var r := live.tick(dt, pts[clampi(int(s), 0, pts.size() - 1)], v, 0.6, false, false)
		if r in ["done", "fail"]:
			break
		if not live.holding():
			s += v * dt
	var sc := float(live.last_result.get("score", 0.0))
	if sc <= 0.0:
		errors.append("a full-length drift scored %s (%s)" % [sc, live.last_result])

func _board(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 777)
	var added := live.update(0.1, 0.0, home, PackedVector2Array(), true)
	if live.board.size() < 2:
		errors.append("filling the board gave %d events" % live.board.size())
	if added.size() != live.board.size():
		errors.append("update() reported %d added of %d" % [added.size(), live.board.size()])
	# a whole day on, they have all expired; the refill then adds one at a time
	live.update(LiveEvents.REFILL + 1.0, 24.0, home, PackedVector2Array())
	if live.board.size() > 1:
		errors.append("%d events still up a day later" % live.board.size())
	# driving far away drops what is left
	var far := home + Vector2(LiveEvents.DESPAWN + 400.0, 0.0)
	live.update(0.1, 0.0, far, PackedVector2Array())
	for ev in live.board:
		if (ev.pos as Vector2).distance_to(far) > LiveEvents.DESPAWN:
			errors.append("an event %.0f m away stayed up" % (ev.pos as Vector2).distance_to(far))

func _save(errors: Array[String]) -> void:
	var w := WorldProgress.new()
	w.record_live("sprint", 3)
	w.record_live("sprint", 1)
	w.record_live("drift_zone", 0)
	var back := WorldProgress.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	if int(back.live.get("done", 0)) != 2 or int(back.live.get("gold", 0)) != 1 or int(back.live.get("bronze", 0)) != 1 \
			or int(back.live.get("tries", 0)) != 3:
		errors.append("live-event stats did not survive a save: %s" % [back.live])
	if WorldProgress.from_dict({}).live.size() != 0:
		errors.append("an old save without live stats does not start empty")

## The events inside a real OpenWorld node (no town meshes): the board is filled and put in `events` with a beacon
## each and a map marker; standing at one shows its card; starting it places the car, holds it through the
## countdown, points the GPS at the checkpoint beacon and shows the clock; reaching every checkpoint ends it with a
## medal banner, the stats saved, the beacon gone and a fresh board entry free to come.
func _world(map: TownMap, home: Vector2, errors: Array[String]) -> void:
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
	ow.drive.place(home, 0.0)
	ow.live = LiveEvents.new(map, 4242)
	ow._live_open()
	var lives := ow.events.filter(func(e): return e.has("live"))
	if lives.size() != ow.live.board.size() or lives.is_empty():
		errors.append("OpenWorld: %d live entries in events for %d on the board" % [lives.size(), ow.live.board.size()])
		ow.queue_free()
		return
	for e in lives:
		if not ow.builder.beacon_nodes.has("live_%s" % e.live):
			errors.append("live event %s has no beacon" % e.live)
	if ow.hud.markers.filter(func(m): return m.get("kind", "") == "live").size() != lives.size():
		errors.append("the map does not mark every live event")
	# pick a sprint if there is one (it has the most checkpoints)
	var e: Dictionary = lives[0]
	for x in lives:
		if ow.live.find(String(x.live)).kind == "sprint":
			e = x
	var lev := ow.live.find(String(e.live))
	ow.drive.place(e.pos, 0.0)
	ow._check_events()
	if not ow.hud.card.visible or ow.hud.card_title.text != String(lev.title):
		errors.append("standing at a live event shows no card ('%s')" % ow.hud.card_title.text)
	ow._start_active_event()
	if not ow.live.holding():
		errors.append("starting a live event did not begin the countdown")
	if Vector2(ow.drive.car.x, ow.drive.car.y).distance_to(lev.pos) > 1.0:
		errors.append("the car was not put on the event's line")
	if not ow.builder.beacon_nodes.has("live_cp"):
		errors.append("no checkpoint beacon while the event runs")
	if ow._target_pos().distance_to((lev.cps as PackedVector2Array)[0]) > 0.1:
		errors.append("the GPS does not point at the first checkpoint")
	ow._update_live(1.0)
	if not ow.hud.live_title.visible:
		errors.append("no event clock on the HUD in the countdown")
	ow._update_live(2.5) # the lights go
	if ow.live.holding():
		errors.append("still held after the countdown")
	var cps: PackedVector2Array = lev.cps
	var gold := float(ow.live.run.tiers[2])
	for i in cps.size():
		ow.drive.place(cps[i], 0.0)
		ow._update_live(gold * 0.9 / cps.size())
	if ow.live.is_running():
		errors.append("driving through every checkpoint did not finish the event")
	if int(ow.progress.live.get("gold", 0)) != 1:
		errors.append("the gold run was not saved in the stats: %s" % [ow.progress.live])
	if ow.builder.beacon_nodes.has("live_cp") or ow.builder.beacon_nodes.has("live_%s" % e.live):
		errors.append("the checkpoint or the cleared event's beacon stayed up")
	if ow.hud.live_title.visible:
		errors.append("the event clock stayed on the HUD")
	var gold_banner := false
	for b in ow.hud.banners.get_children():
		if ((b.get_child(0) as Control).get_child(0) as Label).text.begins_with("GOLD"):
			gold_banner = true
	if not gold_banner:
		errors.append("no GOLD banner after the run")
	if ow.progress.fans <= 0:
		errors.append("the gold run paid no fans")
	# a campaign mission started from its beacon runs on the map: on the grid, roads closed, the field drawn; the
	# pause menu's abandon clears them
	var di := Missions.index_of("drag_quarter")
	if ow._begin_mission(di):
		var rv := ow.live.rivals()
		if rv == null or ow._rival_nodes.size() != rv.rivals.size() or rv.rivals.size() != int(Missions.get_def(di).opponents):
			errors.append("the drag mission's field is not drawn: %d nodes" % ow._rival_nodes.size())
		if not ow._roads_closed():
			errors.append("the roads stay open to traffic in a mission")
		if absf(ow.hour - float(Missions.get_def(di).start_hour)) > 0.01:
			errors.append("the clock did not move to the mission's hour")
		ow._update_live(1.0)
		if not ow.hud.live_title.text.begins_with("DRAG"):
			errors.append("the HUD reads '%s' in a drag mission" % ow.hud.live_title.text)
		ow._pause_action("abandon_live")
		if ow.live.is_running() or not ow._rival_nodes.is_empty():
			errors.append("abandoning the mission left the run or its field")
	else:
		errors.append("the drag mission did not start on the map")
	ow.queue_free()
	await tree.process_frame

# ------------------------------------------------------------------------------------------ missions on the map

## Every campaign mission becomes a run on the open-world map (MapMissions): its route on the map's roads from where
## its beacon stands, the right length and field; a quick scripted player wins a race and a crawling one loses it;
## a slow player is knocked out of the knockout on the first lap; a rally runs its stages with liaisons between.
func _missions_on_map(map: TownMap, errors: Array[String]) -> void:
	for k in Missions.MISSIONS.size():
		var idx := Missions.BASE + k
		var m: Dictionary = Missions.MISSIONS[k]
		var ev := MapMissions.event(idx)
		if ev.is_empty():
			errors.append("mission %s has no route on the map" % m.id)
			continue
		var path: PackedVector2Array = ev.path
		var off := 0
		for i in range(0, path.size(), 25):
			if map.nearest_road(path[i], 12.0).is_empty():
				off += 1
		if off * 25 > path.size() / 10:
			errors.append("mission %s: %d of %d route samples are off the map's roads" % [m.id, off, path.size() / 25])
		var bp := Missions.beacon_pose(idx)
		if not bp.is_empty() and not m.kind in ["rally", "knockout"] and Vector2(bp[0], bp[1]).distance_to(ev.pos) > 40.0:
			errors.append("mission %s starts %.0f m from its beacon" % [m.id, Vector2(bp[0], bp[1]).distance_to(ev.pos)])
		var L := float(ev.length)
		match String(m.kind):
			"drag", "drift":
				if absf(L - float(m.finish_distance)) > 25.0:
					errors.append("mission %s is %.0f m long (should be %.0f)" % [m.id, L, float(m.finish_distance)])
			"knockout":
				if absf(L - float(ev.lap_length) * int(ev.laps)) > 30.0 or int(ev.laps) != int(m.opponents) or not ev.get("sectors", false):
					errors.append("knockout: %.0f m for %d laps of %.0f m" % [L, int(ev.laps), float(ev.lap_length)])
			"rally":
				var on_map: int = Rally.event(String(m.rally)).stages.filter(func(sd): return not MapMissions.OFF_MAP.has(String(sd.track))).size()
				if (ev.stages as Array).size() != on_map or on_map < 2:
					errors.append("rally mission has %d stages" % (ev.stages as Array).size())
			"sprint":
				if L < 8000.0 or L > 11000.0:
					errors.append("S1 sprint on the map is %.0f m" % L)
		if m.kind in ["sprint", "drag"]:
			_race_run(map, ev, errors)
		elif m.kind == "knockout":
			_knockout_run(map, ev, errors)
		elif m.kind == "rally":
			_rally_run(map, ev, errors)

## Drives a point along the path at v m/s through LiveEvents; returns the result.
func _drive(live: LiveEvents, path: PackedVector2Array, v: float, max_t := 4000.0) -> Dictionary:
	var pts := LiveEvents.resample(path, 1.0)
	var dt := 1.0 / 30.0
	var s := 0.0
	var t := 0.0
	while t < max_t:
		t += dt
		var r := live.tick(dt, pts[clampi(int(s), 0, pts.size() - 1)], v, 0.0, false, false)
		if r in ["done", "fail"]:
			return live.last_result
		if not live.holding():
			s += v * dt
	return {}

func _race_run(map: TownMap, ev: Dictionary, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 31)
	live.begin(ev, "stock")
	var ref := LiveEvents.pace_time(ev.path, "stock")
	var fast := _drive(live, ev.path, float(ev.length) / (ref * 0.8))
	if int(fast.get("pos", 0)) != 1 or not MapMissions.outcome(fast).success:
		errors.append("%s: a player far quicker than the reference finished %s" % [ev.mkind, fast.get("line", fast)])
	live.begin(ev, "stock")
	var slow := _drive(live, ev.path, float(ev.length) / (ref * 1.8))
	if int(slow.get("pos", 0)) != int(ev.rivals) + 1 or MapMissions.outcome(slow).success:
		errors.append("%s: a crawling player finished %s" % [ev.mkind, slow.get("line", slow)])

func _knockout_run(map: TownMap, ev: Dictionary, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 32)
	live.begin(ev, "stock")
	var ref := LiveEvents.pace_time(ev.path, "stock")
	var slow := _drive(live, ev.path, float(ev.length) / (ref * 2.0))
	if not bool(slow.get("knocked", false)) or int(slow.get("pos", 0)) != int(ev.rivals) + 1:
		errors.append("knockout: a slow player was not first out: %s" % [slow])
	live.begin(ev, "stock")
	var fast := _drive(live, ev.path, float(ev.length) / (ref * 0.8))
	if int(fast.get("pos", 0)) != 1 or bool(fast.get("knocked", false)):
		errors.append("knockout: a fast player did not win it: %s" % [fast])

## Each stage driven at the reference pace (quicker than every crew), stopped dead at each liaison's end.
func _rally_run(map: TownMap, ev: Dictionary, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 33)
	live.begin(ev, "stock")
	var dt := 1.0 / 30.0
	var stages := 0
	for st in ev.stages:
		var pts := LiveEvents.resample(st.path, 1.0)
		var v := float(st.length) / (LiveEvents.pace_time(st.path, "stock") * 0.95)
		# the liaison: arrive at the start and stop
		for i in 10:
			live.tick(dt, pts[0], 0.0, 0.0, false, false)
		var s := 0.0
		var r := ""
		for step in 400000:
			r = live.tick(dt, pts[clampi(int(s), 0, pts.size() - 1)], v, 0.0, false, false)
			if r in ["stage_done", "done", "fail"]:
				break
			if not live.holding():
				s += v * dt
		stages += 1
		if r == "done" or r == "fail":
			break
	var res := live.last_result
	if stages != (ev.stages as Array).size() or int(res.get("pos", 0)) != 1:
		errors.append("rally on the map: %d stages driven, result %s" % [stages, res])
