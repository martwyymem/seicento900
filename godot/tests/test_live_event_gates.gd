## Weather- and time-gated live events (LiveEvents.VARIANTS: night race, rain drift, fog sprint) on the real Brzeszcze
## map: each is made only while the world is in its state (night / wet roads / fog), is its base kind's event with the
## gate and its name on it, shows the gate on the card, the marker and the notices, pays a little more fans, is dropped
## when the gate closes (with hysteresis; an event being raced stays) and makes room on a full board. A dry noon makes
## none, so the board and the random stream of an ungated world are what they were.
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
	_spawn_gate(map, home, errors)
	_expiry(map, home, errors)
	_board_room(map, home, errors)
	_dry_world_unchanged(map, home, errors)
	_text_and_rewards(map, home, errors)
	_stats(map, home, errors)
	await _world(map, home, errors)
	completed = true
	return errors

const STATES := {"night_race": {"night": 1.0}, "rain_drift": {"wet": 1.0, "rain": 0.8}, "fog_sprint": {"fog": 0.8}}
const BASES := {"night_race": "sprint", "rain_drift": "drift", "fog_sprint": "sprint"}

func _make(live: LiveEvents, vk: String, home: Vector2) -> Dictionary:
	for attempt in 6:
		var ev := live.generate(home, PackedVector2Array(), vk)
		if not ev.is_empty():
			return ev
	return {}

## A variant is made only while its state holds, and is its base kind's event with the variant's keys on it.
func _spawn_gate(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	for vk in LiveEvents.VARIANTS:
		var live := LiveEvents.new(map, 31)
		if not live.generate(home, PackedVector2Array(), vk).is_empty():
			errors.append("%s made in a dry noon" % vk)
		# the wrong state (another variant's) does not open it
		for other in LiveEvents.VARIANTS:
			if other != vk and String(LiveEvents.VARIANTS[other].gate) != String(LiveEvents.VARIANTS[vk].gate):
				live.set_world(STATES[other])
				if not live.generate(home, PackedVector2Array(), vk).is_empty():
					errors.append("%s made in the state of %s" % [vk, other])
		# just under the spawn level: still closed; at it: open
		var v: Dictionary = LiveEvents.VARIANTS[vk]
		live.set_world({String(v.gate): float(v.open) - 0.02})
		if live.variant_open(vk):
			errors.append("%s open just under its spawn level" % vk)
		live.set_world({String(v.gate): float(v.open)})
		if not live.variant_open(vk):
			errors.append("%s closed at its spawn level" % vk)
		live.set_world(STATES[vk])
		var ev := _make(live, vk, home)
		if ev.is_empty():
			errors.append("no %s could be made in its own state" % vk)
			continue
		if String(ev.variant) != vk or String(ev.mkind) != BASES[vk] or String(ev.gate) != String(v.gate):
			errors.append("%s event has variant %s mkind %s gate %s" % [vk, ev.variant, ev.mkind, ev.gate])
		if not ev.color.is_equal_approx(v.color) or LiveEvents.kind_name(ev) != String(v.name):
			errors.append("%s event shows as %s" % [vk, LiveEvents.kind_name(ev)])
		var expect_kind := "drift_zone" if BASES[vk] == "drift" else "race"
		if String(ev.kind) != expect_kind:
			errors.append("%s runs as kind %s, not its base's %s" % [vk, ev.kind, expect_kind])
		if not live.gate_holds(ev):
			errors.append("%s's gate does not hold in its own state" % vk)
	# an ungated event's gate always holds
	var plain := LiveEvents.new(map, 5).generate(home, PackedVector2Array(), "sprint")
	if not plain.is_empty() and (not LiveEvents.new(map, 5).gate_holds(plain) or LiveEvents.gate_tag(plain) != ""):
		errors.append("a plain sprint is gated")

## The gate closing drops the event (below `keep`, not before), an event being raced stays, and the timer's
## expiry still ends a gated event.
func _expiry(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	for vk in LiveEvents.VARIANTS:
		var v: Dictionary = LiveEvents.VARIANTS[vk]
		var live := LiveEvents.new(map, 77)
		live.set_world(STATES[vk])
		var ev := _make(live, vk, home)
		if ev.is_empty():
			errors.append("expiry: no %s" % vk)
			continue
		live.board.append(ev)
		live.update(0.1, 0.0, home, PackedVector2Array())
		if not live.board.has(ev):
			errors.append("%s dropped while its gate holds" % vk)
		# fading, but still above `keep`: stays (no flicker at dusk or on a drying road)
		live.set_world({String(v.gate): (float(v.keep) + float(v.open)) * 0.5})
		live.update(0.1, 0.0, home, PackedVector2Array())
		if not live.board.has(ev):
			errors.append("%s dropped between its keep and spawn levels" % vk)
		# below keep: gone
		live.set_world({String(v.gate): float(v.keep) - 0.02})
		live.update(0.1, 0.0, home, PackedVector2Array())
		if live.board.has(ev):
			errors.append("%s stayed up after its gate closed" % vk)
		# one being raced is never pulled out from under the player
		live.set_world(STATES[vk])
		var ev2 := _make(live, vk, home)
		live.board.clear()
		live.board.append(ev2)
		live.begin(ev2, "stock")
		live.set_world({})
		live.update(0.1, 0.0, home, PackedVector2Array())
		if not live.board.has(ev2) or not live.is_running():
			errors.append("%s pulled off the board while it was being raced" % vk)
		live.abandon()
		live.update(0.1, 0.0, home, PackedVector2Array())
		if live.board.has(ev2):
			errors.append("%s stayed up after the run, with its gate closed" % vk)
		# the timer expires a gated event in its state too
		live.set_world(STATES[vk])
		var ev3 := _make(live, vk, home)
		live.board.clear()
		live.board.append(ev3)
		live.update(0.1, LiveEvents.LIFE_H.y + 1.0, home, PackedVector2Array())
		if live.board.has(ev3):
			errors.append("%s outlived its game hours" % vk)

## A full board of plain events makes room for a variant when its gate opens (once per variant), and does not
## when the gate is shut.
func _board_room(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 909)
	live.update(0.1, 0.0, home, PackedVector2Array(), true)
	var full := live.board.size()
	if full < 2:
		errors.append("board room: only %d events to start with" % full)
		return
	# fill it to the brim with what there is, then open the night
	while live.board.size() < LiveEvents.MAX_LIVE:
		var more := live.generate(home, PackedVector2Array())
		if more.is_empty():
			break
		live.board.append(more)
	var before := live.board.size()
	live.update(LiveEvents.REFILL + 1.0, 0.0, home, PackedVector2Array())
	if live.board.size() != before:
		errors.append("a shut gate changed the board (%d -> %d)" % [before, live.board.size()])
	live.set_world({"night": 1.0})
	var got := false
	for i in 8: # each go picks the variant with VARIANT_PICK, and the ring is random
		live.update(LiveEvents.REFILL + 1.0, 0.0, home, PackedVector2Array())
		for ev in live.board:
			if String(ev.get("variant", "")) == "night_race":
				got = true
		if got:
			break
	if not got:
		errors.append("a night race never took a place on a full board once the night came")
	if live.board.size() > LiveEvents.MAX_LIVE:
		errors.append("the board holds %d events" % live.board.size())
	var n := 0
	for i in 6:
		live.update(LiveEvents.REFILL + 1.0, 0.0, home, PackedVector2Array())
	for ev in live.board:
		if String(ev.get("variant", "")) == "night_race":
			n += 1
	if n > 1:
		errors.append("%d night races stand at once" % n)
	# and the dawn takes it away again
	live.set_world({"night": 0.0})
	live.update(0.1, 0.0, home, PackedVector2Array())
	for ev in live.board:
		if ev.has("variant"):
			errors.append("a %s stayed up in daylight" % ev.variant)

## Without a gate open nothing new is picked and the random stream is what it was: two boards from one seed agree
## whether or not set_world was ever called with a dry noon.
func _dry_world_unchanged(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var a := LiveEvents.new(map, 2024)
	var b := LiveEvents.new(map, 2024)
	b.set_world({"night": 0.0, "wet": 0.2, "rain": 0.0, "fog": 0.05, "hail": 0.0}) # under every spawn level
	a.update(0.1, 0.0, home, PackedVector2Array(), true)
	b.update(0.1, 0.0, home, PackedVector2Array(), true)
	if a.board.size() != b.board.size():
		errors.append("a sub-threshold world changed the board size: %d vs %d" % [a.board.size(), b.board.size()])
		return
	for i in a.board.size():
		if String(a.board[i].mkind) != String(b.board[i].mkind) or (a.board[i].pos as Vector2).distance_to(b.board[i].pos) > 0.01 \
				or a.board[i].has("variant") or b.board[i].has("variant"):
			errors.append("a sub-threshold world changed event %d" % i)
	for k in LiveEvents.KINDS:
		if LiveEvents.VARIANTS.has(k):
			errors.append("%s is both a base kind and a variant" % k)
	for vk in LiveEvents.VARIANTS:
		if not LiveEvents.KINDS.has(String(LiveEvents.VARIANTS[vk].base)):
			errors.append("%s has an unknown base kind" % vk)

## The gate shows on the card and the tag; fans are a fifth over a plain event's, never cars; rain's drift tiers
## are a quarter higher per km.
func _text_and_rewards(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	for vk in LiveEvents.VARIANTS:
		var live := LiveEvents.new(map, 55)
		live.set_world(STATES[vk])
		var ev := _make(live, vk, home)
		if ev.is_empty():
			errors.append("text: no %s" % vk)
			continue
		live.board.append(ev)
		var c := live.card(ev, "stock", 1)
		var name := String(LiveEvents.VARIANTS[vk].name)
		if String(c[0]) != "LIVE %s MISSION" % name:
			errors.append("%s card subtitle is '%s'" % [vk, c[0]])
		var tag := String(LiveEvents.VARIANTS[vk].tag)
		if String(c[2]).find(tag) < 0 or String(c[2]).find("gone when") < 0:
			errors.append("%s card does not show its gate: %s" % [vk, c[2]])
		if LiveEvents.gate_tag(ev) != tag or LiveEvents.gate_line(ev).find(tag) < 0:
			errors.append("%s gate text is '%s' / '%s'" % [vk, LiveEvents.gate_tag(ev), LiveEvents.gate_line(ev)])
		if String(c[2]).find(String(LiveEvents.VARIANTS[vk].blurb).substr(0, 24)) < 0:
			errors.append("%s card does not use its own blurb" % vk)
		var plain := ev.duplicate()
		plain.erase("fan_k")
		var gated := LiveEvents.reward(ev, 1, true, true)
		var base := LiveEvents.reward(plain, 1, true, true)
		if gated <= base or float(gated) > float(base) * 1.4:
			errors.append("%s pays %d fans against a plain event's %d" % [vk, gated, base])
		if LiveEvents.reward(ev, 9, false, true) <= 0:
			errors.append("%s pays nothing for a miss" % vk)
		if ev.has("mission") or ev.has("car") or ev.has("unlock"):
			errors.append("%s event carries a mission, car or unlock" % vk)
	var live2 := LiveEvents.new(map, 56)
	live2.set_world({"wet": 1.0, "rain": 0.8})
	var d := _make(live2, "rain_drift", home)
	if not d.is_empty():
		var t: Array = live2.tiers_for(d, "stock")
		var km := float(d.length) / 1000.0
		if absf(float(t[0]) - LiveEvents.DRIFT_PER_KM[0] * km * 1.25) > 0.01 or not (t[0] < t[1] and t[1] < t[2]):
			errors.append("rain drift tiers %s for %.2f km" % [t, km])

## Tries and misses of a variant count under its own name (a failed night race eases night races, not every sprint).
func _stats(map: TownMap, home: Vector2, errors: Array[String]) -> void:
	var live := LiveEvents.new(map, 66)
	live.set_world({"night": 1.0})
	var ev := _make(live, "night_race", home)
	if ev.is_empty():
		errors.append("stats: no night race")
		return
	if LiveEvents.stat_kind(ev) != "night_race":
		errors.append("night race counted as %s" % LiveEvents.stat_kind(ev))
	var plain := _make(live, "sprint", home)
	if not plain.is_empty() and LiveEvents.stat_kind(plain) != "sprint":
		errors.append("sprint counted as %s" % LiveEvents.stat_kind(plain))
	ev["base_difficulty"] = "hard"
	live.stats = {"fails": {"sprint": 9}}
	live.ease_field(ev)
	if int(ev.eased) != 0:
		errors.append("sprint misses eased a night race (eased %d)" % int(ev.eased))
	live.stats = {"fails": {"night_race": Campaign.FAILS_PER_EASE * 2}}
	live.ease_field(ev)
	if int(ev.eased) != 2 or String(ev.difficulty) != "easy":
		errors.append("night race misses did not ease it: eased %d, %s" % [int(ev.eased), ev.difficulty])
	var wp := WorldProgress.new()
	wp.record_live("night_race", 0)
	wp.record_live("night_race", 1)
	if int(wp.live.get("kinds", {}).get("night_race", 0)) != 1 or int(wp.live.get("done", 0)) != 1:
		errors.append("the night race clear was not recorded under its name: %s" % [wp.live])
	if wp.live.has("fans") or wp.live.has("cars"):
		errors.append("live stats hold fans or cars: %s" % [wp.live])

## Inside the open world: the world's night / wetness / fog reach the board, the card and map marker show the gate,
## and the event goes when the weather clears.
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
	ow.live = LiveEvents.new(map, 4243)
	ow.night = 0.0
	ow.wet = 0.0
	ow.rain = 0.0
	ow.fog = 0.0
	ow.hail = 0.0
	ow._live_open()
	for lev in ow.live.board:
		if lev.has("variant"):
			errors.append("OpenWorld: a %s on the board in a dry, bright world" % lev.variant)
	ow.night = 1.0
	if float(ow.live_world().night) != 1.0:
		errors.append("OpenWorld.live_world does not carry the night: %s" % [ow.live_world()])
	ow.live.set_world(ow.live_world())
	var ev := _make(ow.live, "night_race", home)
	if ev.is_empty():
		errors.append("OpenWorld: no night race at night")
		ow.queue_free()
		return
	ow.live.board.clear()
	ow.live.board.append(ev)
	ow._live_sync()
	var found := false
	for e in ow.events:
		if String(e.get("live", "")) == String(ev.id):
			found = true
			if not String(e.title).to_lower().contains("night race"):
				errors.append("OpenWorld: the night race's entry is called '%s'" % e.title)
	if not found:
		errors.append("OpenWorld: the night race has no entry in events")
	var marked := false
	for m in ow.hud.markers:
		if m.get("kind", "") == "live" and String(m.get("label", "")) == "LIVE NIGHT RACE":
			marked = true
			if String(m.info).find("NIGHT ONLY") < 0:
				errors.append("OpenWorld: the map marker does not show the gate: %s" % m.info)
	if not marked:
		errors.append("OpenWorld: no LIVE NIGHT RACE marker on the map")
	# the night holds through _update_live, the dawn takes the event away and the board refills without it
	ow._update_live(0.1)
	if not ow.live.board.has(ev):
		errors.append("OpenWorld: the night race left while it was still night")
	ow.night = 0.0
	ow._update_live(0.1)
	if ow.live.board.has(ev):
		errors.append("OpenWorld: the night race stayed up in daylight")
	for e in ow.events:
		if String(e.get("live", "")) == String(ev.id):
			errors.append("OpenWorld: the night race's entry stayed in events in daylight")
	if ow.builder.beacon_nodes.has("live_%s" % ev.id):
		errors.append("OpenWorld: the night race's beacon stayed in daylight")
	ow.queue_free()
