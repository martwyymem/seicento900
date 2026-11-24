## Live events (scripts/world/live_events.gd) on the real Brzeszcze map, generated round the festival as missions of
## the campaign's kinds (sprint, drag, knockout, off-road, drift, rally): inside the playable area, clear of each other
## and the beacons; each in the shape MapMissions.event gives a campaign mission (field, grid, sectors, stages,
## target, difficulty) with lengths, surfaces and straightness as promised; the briefing card laid out as a mission's;
## targets like a mission's (eased after misses), fans by length and difficulty, never anything from the campaign; a
## quick scripted player wins each race kind and a crawling one loses it; the board expires, refills and drops far
## events; the WorldProgress save keeps the counts and the misses; the whole flow inside an OpenWorld node; every
## campaign mission on the map; the wrong-way / off-route notices and the checkpoint reset; the field through the
## Kolonia Stawowa hairpin stays on the road.
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
		var ev := {}
		for attempt in 3: # the ring is random: a few goes before calling it broken
			ev = live.generate(home, avoid, kind)
			if not ev.is_empty():
				break
		if ev.is_empty():
			errors.append("no %s could be generated round the festival" % kind)
			continue
		by_kind[kind] = ev
		live.board.append(ev)
		_shape(map, live, ev, home, errors)
		_brief(live, ev, errors)
	for i in live.board.size():
		for j in range(i + 1, live.board.size()):
			if (live.board[i].pos as Vector2).distance_to(live.board[j].pos) < LiveEvents.SPACING:
				errors.append("%s and %s stand %.0f m apart" % [live.board[i].id, live.board[j].id,
					(live.board[i].pos as Vector2).distance_to(live.board[j].pos)])
	for kind in ["sprint", "drag", "offroad"]:
		if by_kind.has(kind):
			_race_run(map, by_kind[kind], errors)
	if by_kind.has("knockout"):
		_knockout_run(map, by_kind.knockout, errors)
	if by_kind.has("rally"):
		_rally_run(map, by_kind.rally, errors)
	if by_kind.has("drift"):
		_run_drift(live, by_kind.drift, errors)
	if by_kind.has("sprint"):
		_settle(live, by_kind.sprint, errors)
		_notices(map, by_kind.sprint, errors)
	_weather_targets(map, by_kind, errors)
	_ease(map, home, errors)
	_board(map, home, errors)
	_save(errors)
	_standings(errors)
	await _world(map, home, errors)
	_missions_on_map(map, errors)
	_hairpin(map, errors)
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

func _shape(map: TownMap, live: LiveEvents, ev: Dictionary, home: Vector2, errors: Array[String]) -> void:
	var mk := String(ev.mkind)
	var p: Vector2 = ev.pos
	var d := p.distance_to(home)
	if d < LiveEvents.SPAWN_MIN - 130.0 or d > LiveEvents.SPAWN_MAX + 130.0:
		errors.append("%s starts %.0f m from the player" % [mk, d])
	if not map.in_play(p) or not map.in_play(ev.goal):
		errors.append("%s starts or ends outside the playable area" % mk)
	if map.nearest_road(p, 3.0).is_empty():
		errors.append("%s's beacon is not on a road" % mk)
	# the mission shape: what MapMissions.event gives a campaign mission
	for key in ["id", "kind", "mkind", "title", "pos", "heading", "path", "length", "cps", "goal", "rivals", "grid",
			"knockout", "lap_length", "laps", "target", "difficulty", "expires", "color"]:
		if not ev.has(key):
			errors.append("%s lacks the mission key '%s'" % [mk, key])
	if ev.has("mission"):
		errors.append("a live %s claims to be campaign mission %s" % [mk, ev.mission])
	var want_kind := {"drift": "drift_zone", "rally": "rally"}.get(mk, "race") as String
	if String(ev.kind) != want_kind:
		errors.append("live %s runs as '%s' (should be '%s')" % [mk, ev.kind, want_kind])
	var rv: Vector2i = LiveEvents.RIVALS[mk]
	var lo := 2 if mk == "drag" else rv.x # (a drag on a narrower street lines up three abreast: StreetRivals.drag_rivals_fit)
	if int(ev.rivals) < lo or int(ev.rivals) > rv.y:
		errors.append("live %s has %d rivals" % [mk, int(ev.rivals)])
	var cps: PackedVector2Array = ev.cps
	var length := float(ev.length)
	var loose := LiveEvents.unpaved_share(map, ev.path)
	match mk:
		"sprint", "knockout", "offroad":
			if length < 1200.0 or length > 5200.0:
				errors.append("%s is %.0f m long" % [mk, length])
			if cps.size() < 3:
				errors.append("%s has %d checkpoints" % [mk, cps.size()])
			for i in range(1, cps.size()):
				if cps[i].distance_to(cps[i - 1]) > LiveEvents.CP_SPACING * 1.4 + 5.0: # the last gap may take a short remainder
					errors.append("%s checkpoints %d-%d are %.0f m apart" % [mk, i - 1, i, cps[i].distance_to(cps[i - 1])])
			if (mk == "offroad") != (loose >= LiveEvents.UNPAVED_OFFROAD):
				errors.append("%s is %.0f%% gravel and dirt" % [mk, loose * 100.0])
			if mk == "knockout" and (not bool(ev.knockout) or not ev.get("sectors", false) or int(ev.laps) != int(ev.rivals) \
					or absf(float(ev.lap_length) * int(ev.laps) - length) > 1.0):
				errors.append("knockout sectors: %d of %.0f m for %d rivals over %.0f m" % [int(ev.laps), float(ev.lap_length), int(ev.rivals), length])
		"drag":
			if not float(length) in LiveEvents.DRAG_LENGTHS and absf(length - 402.0) > 2.0 and absf(length - 1000.0) > 2.0:
				errors.append("drag is %.0f m long" % length)
			var narrow := StreetRivals.drag_half(LiveEvents.route_profile(map, ev.path, 20.0).half, 1 << 20)
			if p.distance_to(ev.goal) < length * 0.97 or String(ev.grid) != "drag" or int(ev.rivals) != mini(3, StreetRivals.drag_rivals_fit(narrow)):
				errors.append("drag is not a straight four-abreast line (%.0f m chord of %.0f, grid '%s')" % [p.distance_to(ev.goal), length, ev.grid])
			for h in (LiveEvents.route_profile(map, ev.path, 20.0).half as PackedFloat32Array):
				if h < LiveEvents.DRAG_HALF:
					errors.append("drag road narrows to %.1f m either side" % h)
					break
		"drift":
			if LiveEvents.turning(ev.path) / (length / 1000.0) < 2.2:
				errors.append("drift is not twisty")
			if int(ev.rivals) != 0:
				errors.append("drift has a field")
		"rally":
			if length < 1500.0 or length > 4000.0 or (ev.get("stages", []) as Array).size() != 1:
				errors.append("rally stage %.0f m, %d stages" % [length, (ev.get("stages", []) as Array).size()])
			if loose < LiveEvents.UNPAVED_RALLY and LiveEvents.turning(ev.path) / (length / 1000.0) < LiveEvents.RALLY_TWIST:
				errors.append("rally stage is neither loose nor twisty")
	if String(ev.title) == "":
		errors.append("%s has no title" % mk)
	if not LiveEvents.on_roads(map, ev.path):
		errors.append("%s's route leaves the drawn roads" % mk)
	var nr := map.nearest_road(ev.pos, 8.0)
	if not nr.is_empty() and absf((nr.dir as Vector2).dot(Vector2.from_angle(float(ev.heading)))) < 0.7:
		errors.append("%s's start faces across its road" % mk)
	var past := live.beyond(ev)
	if past.size() >= 2 and (past[0].distance_to(ev.goal) > 1.0 or not LiveEvents.on_roads(map, past)):
		errors.append("%s's road past the finish does not start there or leaves the roads" % mk)

## The card as a campaign mission's (Missions.card): "LIVE <KIND> MISSION", the length, surface, field, target, the
## fans; the target as a mission words it; a drift's tiers in order.
func _brief(live: LiveEvents, ev: Dictionary, errors: Array[String]) -> void:
	var mk := String(ev.mkind)
	var c := live.card(ev, "stock", 3)
	if c.size() != 4 or String(c[0]) != "LIVE %s MISSION" % LiveEvents.KIND_NAMES[mk]:
		errors.append("%s card's subtitle reads '%s'" % [mk, c[0] if c.size() > 0 else ""])
		return
	var body := String(c[2])
	for part in ["Target: ", "fans on a first clear", live.surface_text(ev), LiveEvents.length_text(ev)]:
		if body.find(part) < 0:
			errors.append("%s card lacks '%s': %s" % [mk, part, body])
	if mk != "drift" and body.find("rivals" if mk != "rally" else "crews") < 0:
		errors.append("%s card does not give the field: %s" % [mk, body])
	if mk == "drift":
		var t := live.tiers_for(ev)
		if t.size() != 3 or not (float(t[0]) < float(t[1]) and float(t[1]) < float(t[2])):
			errors.append("drift targets out of order: %s" % [t])
	elif live.tiers_for(ev).size() != 0:
		errors.append("a %s has point tiers" % mk)
	if String(c[3]).find("START") < 0:
		errors.append("%s card hint reads '%s'" % [mk, c[3]])

## Weather grip scaling: drag_time, rival/rally medal targets and time-outs slow down in wet weather by the pace_time
## model (not a flat multiplier), stay fixed to the start grip if weather changes mid-run, and the card says so.
func _weather_targets(map: TownMap, by_kind: Dictionary, errors: Array[String]) -> void:
	var wet_mu := float(MapMissions.weather_state("wet").mu)
	var snow_mu := float(MapMissions.weather_state("snow").mu)
	# 1. drag_time follows pace_time's grip ratio, not a flat multiplier
	var ratios_402 := {}
	for car in ["stock", "golf4", "logan", "v50", "i20", "sandero", "focus", "zafira", "hypercar"]:
		var d402 := LiveEvents.drag_time(car, 402.0)
		var d402_1 := LiveEvents.drag_time(car, 402.0, 1.0)
		var w402 := LiveEvents.drag_time(car, 402.0, wet_mu)
		var s402 := LiveEvents.drag_time(car, 402.0, snow_mu)
		if absf(d402 - d402_1) > 1e-6:
			errors.append("%s drag_time dry default %.4f != grip 1.0 %.4f" % [car, d402, d402_1])
		if not (s402 > w402 and w402 > d402):
			errors.append("%s drag_time not slower in wet/snow: dry %.2f wet %.2f snow %.2f" % [car, d402, w402, s402])
		var straight := PackedVector2Array([Vector2.ZERO, Vector2(402.0, 0.0)])
		var want := d402 * (LiveEvents.pace_time(straight, car, 0.0, wet_mu) / LiveEvents.pace_time(straight, car, 0.0, 1.0))
		if absf(w402 - want) > 1e-4:
			errors.append("%s wet drag_time %.4f does not match pace_time model %.4f" % [car, w402, want])
		ratios_402[car] = w402 / d402
	var r_402 := LiveEvents.drag_time("stock", 402.0, snow_mu) / LiveEvents.drag_time("stock", 402.0, 1.0)
	var r_1k := LiveEvents.drag_time("stock", 1000.0, snow_mu) / LiveEvents.drag_time("stock", 1000.0, 1.0)
	if absf(r_402 - r_1k) < 0.002:
		errors.append("drag_time grip scaling looks like a flat multiplier: 402 m %.4f vs 1000 m %.4f" % [r_402, r_1k])
	# 2. time-outs slower in wet for sprint, drift and rally, and fixed at start even if ev.mu changes mid-run
	for kind in ["sprint", "drift", "rally"]:
		if not by_kind.has(kind):
			continue
		var ev_dry: Dictionary = (by_kind[kind] as Dictionary).duplicate()
		var ev_wet: Dictionary = (by_kind[kind] as Dictionary).duplicate()
		ev_dry["mu"] = 1.0
		ev_wet["mu"] = wet_mu
		var l_dry := LiveEvents.new(map, 606)
		var l_wet := LiveEvents.new(map, 606)
		l_dry.begin(ev_dry, "stock")
		l_wet.begin(ev_wet, "stock")
		var lim_dry := l_dry._time_limit()
		var lim_wet := l_wet._time_limit()
		if not (lim_wet > lim_dry):
			errors.append("%s time-out not slower in wet: dry %.1f s, wet %.1f s" % [kind, lim_dry, lim_wet])
		# weather changes mid-run: ev.mu drops, but run.mu and time-out stay fixed to the start grip
		ev_dry["mu"] = snow_mu
		if absf(float(l_dry.run.get("mu", 0.0)) - 1.0) > 1e-6 or absf(l_dry._time_limit() - lim_dry) > 1e-6:
			errors.append("%s time-out or run.mu changed mid-run when ev.mu dropped" % kind)
		l_dry.abandon()
		l_wet.abandon()
	# 3. drag rival field is slower in wet than dry, and fixed at start if ev.mu changes mid-run
	if by_kind.has("drag"):
		var d_dry: Dictionary = (by_kind.drag as Dictionary).duplicate()
		var d_wet: Dictionary = (by_kind.drag as Dictionary).duplicate()
		d_dry["mu"] = 1.0
		d_wet["mu"] = wet_mu
		var l1 := LiveEvents.new(map, 707)
		var l2 := LiveEvents.new(map, 707)
		l1.begin(d_dry, "golf4")
		l2.begin(d_wet, "golf4")
		var rv1 = l1.rivals()
		var rv2 = l2.rivals()
		d_dry["mu"] = snow_mu # mid-run weather shift must not affect rv1
		for _i in 900:
			rv1.step(1.0 / 30.0, Vector2.ZERO, 0.0)
			rv2.step(1.0 / 30.0, Vector2.ZERO, 0.0)
		var t1: float = rv1.best_time()
		var t2: float = rv2.best_time()
		if t1 <= 0.0 or t2 <= 0.0 or not (t2 > t1):
			errors.append("wet drag rivals not slower than dry: dry %.2f s, wet %.2f s" % [t1, t2])
		l1.abandon()
		l2.abandon()
	# 4. event card documents that targets are fixed to the weather at the start
	if by_kind.has("sprint"):
		var live_c := LiveEvents.new(map, 808)
		var card_body := String(live_c.card(by_kind.sprint, "stock", 1)[2]).to_lower()
		if card_body.find("start weather") < 0:
			errors.append("live event card does not state targets are fixed to start weather: %s" % card_body)

## Sideways at speed through the drift scores; the result is a tier against the bronze target.
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

## A finished live race settled: a win is gold and pays fans by length and difficulty (more for a harder field and
## a longer route, a quarter for a repeat, a share for a miss); nothing of the campaign's is in it.
func _settle(live: LiveEvents, ev: Dictionary, errors: Array[String]) -> void:
	var win := live.settle({"ev": ev, "pos": 1, "finished": true, "line": "P1"})
	if not bool(win.success) or int(win.tier) != 3 or int(win.fans) <= 0 or int(ev.get("best_tier", 0)) != 3:
		errors.append("a live win settled as %s" % [win])
	if win.has("trophy") or win.has("reward_car") or win.has("unlock"):
		errors.append("a live event handed out campaign rewards: %s" % [win])
	var again := live.settle({"ev": ev, "pos": 1, "finished": true, "line": "P1"})
	if int(again.fans) >= int(win.fans) or bool(again.first_clear):
		errors.append("a repeat win paid %d fans (the first %d)" % [int(again.fans), int(win.fans)])
	var miss := live.settle({"ev": ev, "pos": int(ev.rivals) + 1, "finished": true, "line": "last"})
	if bool(miss.success) or int(miss.tier) != 0 or int(miss.fans) >= int(win.fans):
		errors.append("a last place settled as %s" % [miss])
	var e2 := ev.duplicate()
	e2.erase("best_tier")
	e2["difficulty"] = "hard"
	var e3 := e2.duplicate()
	e3["difficulty"] = "easy"
	var e4 := e2.duplicate()
	e4["length"] = float(ev.length) * 2.0
	var hard := LiveEvents.reward(e2, 1, true, true)
	var easy := LiveEvents.reward(e3, 1, true, true)
	if not (hard > easy) or LiveEvents.reward(e4, 1, true, true) <= hard and float(ev.length) < 2500.0:
		errors.append("fans not scaled by difficulty and length: hard %d, easy %d, double length %d" % [hard, easy,
			LiveEvents.reward(e4, 1, true, true)])
	ev.erase("best_tier")
	ev.erase("best_pos")

## Missed tries of a kind ease its next field as a campaign mission's (Campaign.FAILS_PER_EASE); a drift's never.
func _ease(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 5150)
	var ev := live.generate(home, PackedVector2Array(), "sprint")
	if ev.is_empty():
		return
	ev["base_difficulty"] = "hard"
	live.stats = {"fails": {"sprint": Campaign.FAILS_PER_EASE}}
	live.ease_field(ev)
	if String(ev.difficulty) != "medium" or int(ev.eased) != 1:
		errors.append("a hard sprint after %d misses runs at '%s'" % [Campaign.FAILS_PER_EASE, ev.difficulty])
	live.stats = {"fails": {"sprint": 99}}
	live.ease_field(ev)
	if String(ev.difficulty) != "easy" or String(live.card(ev, "stock")[2]).find("eased") < 0:
		errors.append("a sprint missed many times is not eased to easy on its card ('%s')" % ev.difficulty)
	live.stats = {}
	live.ease_field(ev)
	if String(ev.difficulty) != "hard":
		errors.append("a sprint with no misses is not back at its own difficulty")

## The wrong way and off the route are told; R goes back to the last gate (the grid before the first).
func _notices(map: TownMap, ev: Dictionary, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 99)
	live.begin(ev, "stock")
	var tr: PackedVector2Array = live.run.track
	var dt := 1.0 / 30.0
	var said := ""
	for k in 240: # through the countdown, then 75 m on along the route
		live.tick(dt, tr[mini(int(maxf(float(live.run.t), 0.0) * 15.0 / LiveEvents.TRACK_STEP), tr.size() - 1)], 15.0, 0.0, false, false)
	var s := float(live.run.s)
	for k in 90:
		s = maxf(s - 15.0 * dt, 0.0)
		var i := clampi(int(s / LiveEvents.TRACK_STEP), 0, tr.size() - 2)
		var r := live.tick(dt, tr[i].lerp(tr[i + 1], s / LiveEvents.TRACK_STEP - i), 15.0, 0.0, false, false)
		if r == "warn":
			said = String(live.run.notice)
	if said != "wrong_way":
		errors.append("driving back along a sprint gave notice '%s'" % said)
	var far := tr[int(s / LiveEvents.TRACK_STEP)] + Vector2(0.0, 120.0)
	for k in 200:
		live.tick(dt, far, 0.0, 0.0, false, false)
	if String(live.run.notice) != "off_route":
		errors.append("120 m off the route for 6 s gave notice '%s'" % live.run.notice)
	var pose := live.reset_to_checkpoint()
	if pose.is_empty() or (pose[0] as Vector2).distance_to(live.grid_pose(ev)[0]) > 0.5 or String(live.run.notice) != "":
		errors.append("reset before the first gate did not go back to the grid: %s" % [pose])
	live.abandon()

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
	w.record_live("drift", 0)
	w.record_live("drag", 0)
	w.record_live("drag", 0)
	var back := WorldProgress.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	if int(back.live.get("done", 0)) != 2 or int(back.live.get("gold", 0)) != 1 or int(back.live.get("bronze", 0)) != 1 \
			or int(back.live.get("tries", 0)) != 5:
		errors.append("live-event stats did not survive a save: %s" % [back.live])
	if int((back.live.get("fails", {}) as Dictionary).get("drag", 0)) != 2:
		errors.append("missed tries per kind did not survive a save: %s" % [back.live])
	back.record_live("drag", 2)
	if (back.live.fails as Dictionary).has("drag"):
		errors.append("a cleared drag kept its misses")
	if WorldProgress.from_dict({}).live.size() != 0:
		errors.append("an old save without live stats does not start empty")
	# a save from before the missions (old kind names, no misses) still loads and counts on
	var old := WorldProgress.from_dict({"live": {"tries": 4, "done": 3, "gold": 1, "kinds": {"speed_zone": 2}}})
	old.record_live("sprint", 0)
	if int(old.live.get("tries", 0)) != 5 or int(old.live.get("done", 0)) != 3:
		errors.append("an old save's live stats did not carry on: %s" % [old.live])

## The field has names (Drivers.ROSTER, no two alike) and the timing list puts the player where position() says, the
## rest in running order; a knockout's cars out come last as OUT. RESET CAMPAIGN wipes the open-world progress.
func _standings(errors: Array[String]) -> void:
	var path := PackedVector2Array([Vector2.ZERO, Vector2(3000, 0)])
	var rv := EventField.new(path, "stock", 5, 77)
	var names := {}
	for r in rv.rivals:
		if String(r.get("name", "")) == "" or int(r.get("number", 0)) <= 0:
			errors.append("a street rival has no name or number: %s" % [r])
		names[String(r.get("name", ""))] = true
	if names.size() != rv.rivals.size():
		errors.append("street rivals share names: %s" % [names.keys()])
	for i in 300: # 10 s at a middling pace: some of the field ahead, some behind
		rv.step(1.0 / 30.0, Vector2(minf(float(i) * 0.6, 3000.0), 0.0), 18.0)
	var rows := rv.standings()
	if rows.size() != rv.field():
		errors.append("the timing list has %d rows for a field of %d" % [rows.size(), rv.field()])
	var mine := rows.find_custom(func(r): return bool(r.player))
	if mine != rv.position() - 1:
		errors.append("the timing list has the player P%d, position() says P%d" % [mine + 1, rv.position()])
	for i in range(1, rows.size()):
		if not bool(rows[i].player) and not bool(rows[i - 1].player) and float(rows[i].s) > float(rows[i - 1].s) + 0.01:
			errors.append("the timing list is out of order at row %d" % (i + 1))
		if not String(rows[i].gap).begins_with("+"):
			errors.append("row %d shows no interval: %s" % [i + 1, rows[i].gap])
	var ko := EventField.new(path, "stock", 3, 5, {"knockout": true, "lap_length": 750.0})
	for i in 4000:
		ko.step(1.0 / 30.0, Vector2(float(i) * 0.15, 0.0), 4.5) # a crawl: first out
		if ko.player_out:
			break
	var kr := ko.standings()
	if not ko.player_out or not bool(kr[kr.size() - 1].player) or String(kr[kr.size() - 1].gap) != "OUT":
		errors.append("a knocked-out player is not last and OUT on the timing list: %s" % [kr])
	var w := WorldProgress.new()
	w.fans = 5_000_000
	w.roads = {3: true}
	w.landmarks = {"Kościół": true}
	w.car_class = 2
	w.live = {"tries": 4}
	w.map_hidden = ["traps"]
	w.wipe_campaign()
	if w.fans != 0 or not w.roads.is_empty() or not w.landmarks.is_empty() or w.car_class != 0 or not w.live.is_empty():
		errors.append("RESET CAMPAIGN left open-world progress: %s" % [w.to_dict()])
	if w.map_hidden != ["traps"]:
		errors.append("RESET CAMPAIGN cleared the map's filters")

## The events inside a real OpenWorld node (no town meshes): the board is filled and put in `events` with a beacon
## each and a map marker; standing at one shows its mission card; starting it puts the car in its grid slot with the
## field drawn and the roads closed, holds it through the countdown, points the GPS at the checkpoint beacon and
## shows the clock; reaching every checkpoint ahead of the field ends it with a GOLD banner, the stats saved and the
## results card; RESTART and ABANDON as a mission's.
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
	# a sprint (it has the most checkpoints): one put on the board if none came up
	var e: Dictionary = {}
	for x in lives:
		if String(ow.live.find(String(x.live)).mkind) == "sprint":
			e = x
	if e.is_empty():
		var sp := ow.live.generate(home + Vector2(400.0, 0.0), ow._beacon_points(), "sprint")
		if sp.is_empty():
			errors.append("OpenWorld: no sprint for the flow checks")
			ow.queue_free()
			return
		ow.live.board.append(sp)
		ow._live_sync()
		for x in ow.events:
			if String(x.get("live", "")) == String(sp.id):
				e = x
	var lev := ow.live.find(String(e.live))
	ow.drive.place(e.pos, 0.0)
	ow._check_events()
	if not ow.hud.card.visible or ow.hud.card_title.text != String(lev.title) or not ow.hud.card_sub.text.begins_with("LIVE SPRINT MISSION"):
		errors.append("standing at a live event shows no mission card ('%s')" % ow.hud.card_title.text)
	ow._start_active_event()
	if not ow.live.holding():
		errors.append("starting a live event did not begin the countdown")
	if Vector2(ow.drive.car.x, ow.drive.car.y).distance_to(ow.live.grid_pose(lev)[0]) > 1.0:
		errors.append("the car was not put in its grid slot")
	var lrv = ow.live.rivals()
	if lrv == null or ow._rival_nodes.size() != int(lev.rivals) or lrv.rivals.size() != int(lev.rivals):
		errors.append("the live sprint's field is not drawn: %d nodes for %d rivals" % [ow._rival_nodes.size(), int(lev.rivals)])
	if not ow._roads_closed():
		errors.append("the roads stay open to traffic in a live mission")
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
	var quick := LiveEvents.pace_time(lev.path, "stock") * 0.7 # far ahead of the whole field
	for i in cps.size():
		ow.drive.place(cps[i], 0.0)
		ow._update_live(quick / cps.size())
	if ow.live.is_running():
		errors.append("driving through every checkpoint did not finish the event")
	if int(ow.progress.live.get("gold", 0)) != 1:
		errors.append("the gold run was not saved in the stats: %s" % [ow.progress.live])
	var gold_banner := false
	for b in ow.hud.banners.get_children():
		if ((b.get_child(0) as Control).get_child(0) as Label).text.begins_with("GOLD"):
			gold_banner = true
	if not gold_banner:
		errors.append("no GOLD banner after the run")
	if ow.builder.beacon_nodes.has("live_cp") or not ow._gate_nodes.is_empty():
		errors.append("the checkpoint beacon or gate posts stayed up")
	if not ow.builder.beacon_nodes.has("live_%s" % e.live):
		errors.append("the cleared event's beacon went (it stays up for another go)")
	elif not ((ow.builder.beacon_nodes["live_%s" % e.live] as Node3D).get_child(2) as Label3D).text.begins_with("★★★"):
		errors.append("the cleared event's beacon does not show its gold medal")
	if not ow.hud.card.visible or not ow.hud.card_hint.text.contains("RESTART"):
		errors.append("no results card with RESTART after the run ('%s')" % ow.hud.card_hint.text)
	# ENTER on the results card restarts it: on the line again, countdown
	ow._start_active_event()
	if not ow.live.holding() or String(ow.live.run.ev.id) != String(lev.id):
		errors.append("RESTART from the results card did not put the sprint back on the line")
	# the pause menu has RESTART EVENT and ABANDON EVENT while it runs
	var items: Array = ow._pause_items()
	if not items.any(func(it): return it[0] == "restart_live") or not items.any(func(it): return it[0] == "abandon_live"):
		errors.append("the pause menu lacks RESTART / ABANDON EVENT: %s" % [items])
	ow._update_live(3.5)
	# miss the first checkpoint: drive on past it beside the route
	var tr: PackedVector2Array = ow.live.run.track
	var cp_s: float = (ow.live.run.cp_s as PackedFloat32Array)[0]
	var miss_i := int((cp_s + 80.0) / LiveEvents.TRACK_STEP)
	if miss_i < tr.size() - 1:
		var step_i := int(cp_s / LiveEvents.TRACK_STEP) - 10
		while step_i <= miss_i:
			var d := (tr[step_i + 1] - tr[step_i]).normalized()
			ow.drive.place(tr[step_i] + Vector2(-d.y, d.x) * 40.0 if absf(step_i * LiveEvents.TRACK_STEP - cp_s) < 30.0 else tr[step_i], 0.0)
			ow._update_live(0.1)
			step_i += 3
		if String(ow.live.run.notice) != "missed" or not ow.hud.live_line.text.begins_with("MISSED"):
			errors.append("running past a checkpoint gave notice '%s' / HUD '%s'" % [ow.live.run.notice, ow.hud.live_line.text])
		if not ow._reset_in_event():
			errors.append("R during the event fell back to a plain respawn")
		var at := Vector2(ow.drive.car.x, ow.drive.car.y)
		var slot: Vector2 = ow.live.grid_pose(lev)[0]
		if at.distance_to(slot) > 1.0 or String(ow.live.run.notice) != "" or int(ow.live.run.cp) != 0:
			errors.append("R in the event did not reset to the grid: %.0f m off, notice '%s'" % [at.distance_to(slot), ow.live.run.notice])
	ow._pause_action("abandon_live")
	if ow.live.is_running() or ow.hud.live_title.visible or not ow._gate_nodes.is_empty() or not ow._rival_nodes.is_empty() or ow._roads_closed():
		errors.append("ABANDON EVENT left the run, the HUD, the gates, the field or the roads closed")
	if ow.hud.live_title.visible:
		errors.append("the event clock stayed on the HUD")
	if ow.progress.fans <= 0:
		errors.append("the gold run paid no fans")
	# a campaign mission started from its beacon runs on the map: on the grid, roads closed, the field drawn; the
	# pause menu's abandon clears them
	var di := Missions.index_of("drag_quarter")
	ow.hour = 9.25
	if ow._begin_mission(di):
		var rv = ow.live.rivals()
		if rv == null or ow._rival_nodes.size() != rv.rivals.size() or rv.rivals.size() != int(Missions.get_def(di).opponents):
			errors.append("the drag mission's field is not drawn: %d nodes" % ow._rival_nodes.size())
		var drag_keys: Array[String] = []
		var real_pool := CarCatalog.rival_keys()
		for rn in ow._rival_nodes:
			var rk := String(rn.get("car_key"))
			if not (rk in real_pool):
				errors.append("open-world rival has non-real car_key '%s'" % rk)
			drag_keys.append(rk)
		var uniq_drag := {}
		for rk in drag_keys:
			uniq_drag[rk] = true
		if drag_keys.size() >= 2 and uniq_drag.size() < drag_keys.size():
			errors.append("drag mission rivals repeated models unnecessarily: %s" % [drag_keys])
		if not ow._roads_closed():
			errors.append("the roads stay open to traffic in a mission")
		if absf(ow.hour - float(Missions.get_def(di).start_hour)) > 0.01:
			errors.append("the clock did not move to the mission's hour")
		ow._update_live(1.0)
		# the countdown: the count in the big line, the event's name under it
		if ow.hud.live_title.text != "2" or not ow.hud.live_line.text.begins_with("DRAG"):
			errors.append("the HUD reads '%s / %s' in a drag mission's countdown" % [ow.hud.live_title.text, ow.hud.live_line.text])
		ow._pause_action("restart_live")
		if not ow.live.holding() or ow._rival_nodes.size() != int(Missions.get_def(di).opponents):
			errors.append("RESTART EVENT did not put the drag back on the grid with its field")
		var drag_keys2: Array[String] = []
		for rn in ow._rival_nodes:
			drag_keys2.append(String(rn.get("car_key")))
		if drag_keys2 != drag_keys:
			errors.append("restarting a mission changed its rival models: %s -> %s" % [drag_keys, drag_keys2])
		ow._pause_action("abandon_live")
		if ow.live.is_running() or not ow._rival_nodes.is_empty() or ow._roads_closed():
			errors.append("abandoning the mission left the run, its field or the roads closed")
		if absf(ow.hour - 9.25) > 0.01:
			errors.append("the clock stayed at the mission's hour (%.2f) after it ended" % ow.hour)
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
				var on_map: int = (Missions.rally_def(idx).stages as Array).filter(func(sd): return not MapMissions.OFF_MAP.has(String(sd.track))).size()
				if (ev.stages as Array).size() != on_map or on_map < 2:
					errors.append("rally mission has %d stages" % (ev.stages as Array).size())
			"sprint":
				var want := MapMissions.lap_length(String(m.track)) * int(m.get("laps", 1))
				if absf(L - want) > 30.0 or (String(m.track) == "s1_sprint" and (L < 8000.0 or L > 11000.0)):
					errors.append("sprint %s on the map is %.0f m (its laps are %.0f m)" % [m.id, L, want])
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
	var ref := LiveEvents.pace_time(ev.path, "stock", 0.0, live.grip_of(ev))
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
	var ref := LiveEvents.pace_time(ev.path, "stock", 0.0, live.grip_of(ev))
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

## The Kolonia Stawowa hairpin (the off-road mission's tightest bend): the field goes round it on the road, no
## quicker than its grip allows. Regression: the audit's driver once ran 4.4 m wide there and the rivals were blamed.
func _hairpin(map: TownMap, errors: Array[String]) -> void:
	var ev := MapMissions.event(Missions.index_of("offroad_kolonia"))
	if ev.is_empty():
		errors.append("no Kolonia Stawowa mission on the map")
		return
	var live := LiveEvents.new(map, 41)
	live.begin(ev, "stock")
	var rv := live.rivals() as EventField
	if rv == null:
		errors.append("the Kolonia Stawowa mission has no race field")
		return
	# the tightest bend: the sample with the most turning over 30 m
	var pts := LiveEvents.resample(ev.path, 10.0)
	var at := 0
	var most := 0.0
	for i in range(3, pts.size() - 3):
		var turn := absf(wrapf((pts[i + 3] - pts[i]).angle() - (pts[i] - pts[i - 3]).angle(), -PI, PI)) # over 30 m
		if turn > most:
			most = turn
			at = i
	var apex := pts[at]
	if most < 1.2:
		errors.append("Kolonia Stawowa's tightest bend turns only %.2f rad (no hairpin found)" % most)
	var radius := 30.0 / maxf(most, 0.01)
	var vmax := 0.0
	var worst := 0.0
	var dt := 1.0 / 30.0
	var t := 0.0
	var far := pts[0] + Vector2(600.0, 600.0) # the player out of everyone's way (no rubber band either way)
	while t < 900.0 and rv.finished_count() < rv.rivals.size():
		t += dt
		rv.step(dt, far, 0.0)
		for k in rv.count():
			var cp := rv.car_pose(k)
			var q: Vector2 = cp[0]
			if q.distance_to(apex) > 12.0 or bool(rv.rivals[k].done):
				continue
			vmax = maxf(vmax, float(cp[2]))
			for m in [0.0, 0.5, 1.0, 2.0, 4.0, 99.0]:
				if m >= 99.0 or not map.road_at(q.x, q.y, -INF, m).is_empty():
					worst = maxf(worst, m)
					break
	live.abandon()
	var grip: float = LiveEvents.PACE.stock[2]
	if OS.get_environment("HAIRPIN") != "":
		print("hairpin at %s: %.2f rad over 30 m (r %.0f m), rivals up to %.1f m/s, %.1f m beyond the road" % [pts[at], most, radius, vmax, worst])
	if vmax > sqrt(grip / 0.86 * radius) * 1.3: # (the race's bots corner at up to 1 g, PACE's grip is 0.86 g)
		errors.append("a rival rounds the Kolonia Stawowa hairpin (r %.0f m) at %.1f m/s" % [radius, vmax])
	if worst > 0.5:
		errors.append("a rival runs %.1f m beyond the road in the Kolonia Stawowa hairpin" % worst)
