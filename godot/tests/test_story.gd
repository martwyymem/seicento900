## The campaign's story (Story, StoryCard): every stage and mission has its beats, every speaker is in the cast,
## each line fits the dialogue card at 4:3 and the larger interface sizes (measured with the card's font), the seen
## beats save in campaign.json (on a file of this suite's own), load from a save made before the story and clear
## on RESET CAMPAIGN, each trigger fires once, and the card advances and skips on keys and pad buttons.
extends RefCounted

var completed := false

const TEST_SAVE := "test_story_campaign.json"
const CANVASES := [Vector2(1600, 900), Vector2(1600, 1200), Vector2(1231, 923), Vector2(1391, 783)] ## 16:9, 4:3, 4:3 at 1.3, 16:9 at 1.15
const MAX_CARD_LINES := 4 ## wrapped lines of one story line in the card at the narrowest canvas
const BANNED := ["auschwitz", "birkenau", "memorial", "museum", "camp"] ## the Oświęcim chapter is the old town and the river only

func run() -> Array:
	var errors: Array[String] = []
	_data(errors)
	_fits(errors)
	var saved_file := Campaign.save_file
	Campaign.save_file = TEST_SAVE
	_saves(errors)
	_triggers(errors)
	Campaign.reset_progress()
	Campaign.save_file = saved_file
	await _card(errors)
	completed = true
	return errors

func _data(errors: Array[String]) -> void:
	var ids: Array[String] = []
	for st: Dictionary in Campaign.STAGES:
		ids.append(String(st.id))
	for m: Dictionary in Missions.MISSIONS:
		ids.append(String(m.id))
		var car := String(m.get("reward_car", ""))
		if car != "" and not Story.BEATS.has("car_" + car):
			errors.append("story: no car_%s beat for %s's reward" % [car, m.id])
	for i in ids.size():
		var id := ids[i]
		for suffix: String in ["_brief", "_before", "_won", "_miss"]:
			if not Story.BEATS.has(id + suffix):
				errors.append("story: %s has no %s beat" % [id, suffix])
		if i > 0 and not Story.RADIO.has("open_" + id): # stage 1 is open from the start (the intro covers it)
			errors.append("story: %s has no open_ phone message" % id)
	for i in Campaign.STAGES.size():
		if Story.event_id(i) != ids[i]:
			errors.append("story: event_id(%d) is %s" % [i, Story.event_id(i)])
		if Story.brief_line(i).is_empty() or not Story.brief_text(i, "BODY").ends_with("BODY"):
			errors.append("story: stage %d's briefing has no story line" % i)
	for k in Missions.MISSIONS.size():
		if Story.event_id(Missions.BASE + k) != String(Missions.MISSIONS[k].id):
			errors.append("story: event_id of mission %d" % k)
	for key: String in ["intro", "festival", "act_2", "act_3", "epilogue"]:
		if not Story.BEATS.has(key):
			errors.append("story: no %s beat" % key)
	for c: String in Story.CHARACTERS:
		var who: Dictionary = Story.CHARACTERS[c]
		for f: String in ["name", "role", "color", "initial"]:
			if String(who.get(f, "")) == "":
				errors.append("story: character %s has no %s" % [c, f])
		if not Color.html_is_valid(String(who.color)):
			errors.append("story: character %s's colour" % c)
	var spoken := {}
	for key: String in Story.BEATS.keys() + Story.RADIO.keys():
		var ls := Story.lines(key)
		if ls.is_empty():
			errors.append("story: %s is empty" % key)
		var n_max := 1 if key.ends_with("_brief") else Story.MAX_LINES
		if ls.size() > n_max:
			errors.append("story: %s has %d lines (at most %d)" % [key, ls.size(), n_max])
		if not key.ends_with("_brief") and not Story.is_radio(key) and ls.size() < 1:
			errors.append("story: %s too short" % key)
		for ln in ls:
			if not ln is Array or (ln as Array).size() != 2:
				errors.append("story: %s has a malformed line" % key)
				continue
			var who := String(ln[0])
			spoken[who] = true
			if who != "" and not Story.CHARACTERS.has(who):
				errors.append("story: %s is spoken by %s, who is not in the cast" % [key, who])
			var text := String(ln[1])
			var cap := Story.BRIEF_CHARS if key.ends_with("_brief") else Story.MAX_CHARS
			if text.length() > cap:
				errors.append("story: %s line is %d chars (cap %d): %s" % [key, text.length(), cap, text.left(40)])
			for word: String in BANNED:
				if text.to_lower().contains(word):
					errors.append("story: %s mentions '%s'" % [key, word])
	for c: String in Story.CHARACTERS:
		if not spoken.has(c):
			errors.append("story: %s never speaks" % c)

func _fits(errors: Array[String]) -> void:
	for key: String in Story.BEATS.keys() + Story.RADIO.keys():
		for ln in Story.lines(key):
			for cv: Vector2 in CANVASES:
				var n := StoryCard.line_count(String(ln[1]), cv.x)
				var cap := 3 if cv.x >= 1600.0 else MAX_CARD_LINES
				if n > cap:
					errors.append("story: %s wraps to %d lines at %dx%d (cap %d): %s" % [key, n, cv.x, cv.y, cap, String(ln[1]).left(40)])

func _saves(errors: Array[String]) -> void:
	Campaign.reset_progress()
	if not Story.seen_keys(Campaign.load_progress()).is_empty():
		errors.append("story save: a fresh campaign has seen beats")
	Story.mark_seen(["intro", "stage_1_before"])
	Story.mark_seen(["stage_1_before", "festival"])
	var seen := Story.seen_keys(Campaign.load_progress())
	if seen != ["intro", "stage_1_before", "festival"]:
		errors.append("story save: seen is %s (want the order shown, once each)" % [seen])
	if not Story.is_seen("festival") or Story.is_seen("act_2"):
		errors.append("story save: is_seen")
	var j := Story.journal(Campaign.load_progress(), 0)
	if j.size() != 4 or String(j[1].title) != "PROLOGUE" or String(j[3].title) != "SEICENTO FEST":
		errors.append("story save: journal is %s" % [j.map(func(b): return b.title)])
	if not String(j[0].lines[1][1]).begins_with("Next:"):
		errors.append("story save: journal has no next step: %s" % [j[0].lines])
	Campaign.reset_progress() # RESET CAMPAIGN
	if not Story.seen_keys(Campaign.load_progress()).is_empty():
		errors.append("story save: RESET CAMPAIGN keeps the seen beats")
	# a save from before the story: no "story" key; and a broken one
	Campaign.save_progress({"unlocked": 3, "best_pos": {"0": 1}, "trophies": [String(Campaign.STAGES[0].trophy)]})
	var old := Campaign.load_progress()
	if not Story.seen_keys(old).is_empty() or not Story.needs_catch_up(old):
		errors.append("story save: an old save with progress is not caught up")
	if Story.needs_catch_up({"unlocked": 0, "best_pos": {}, "trophies": []}):
		errors.append("story save: a new campaign is caught up instead of shown the intro")
	Story.mark_seen(Story.pending(old, 0))
	var after := Campaign.load_progress()
	if Story.needs_catch_up(after) or not Story.pending(after, 0).is_empty() or int(after.get("unlocked", 0)) != 3:
		errors.append("story save: catching up an old save")
	if not Story.seen_keys({"story": "junk"}).is_empty() or not Story.seen_keys({"story": {"seen": 5}}).is_empty():
		errors.append("story save: a malformed story entry")

func _triggers(errors: Array[String]) -> void:
	Campaign.reset_progress()
	var p := Story.pending(Campaign.load_progress(), 0)
	if p.is_empty() or p[0] != "intro":
		errors.append("story triggers: a new campaign starts with %s" % [p])
	if "festival" in p or "stage_1_won" in p or "act_2" in p:
		errors.append("story triggers: a new campaign has %s" % [p])
	if not "festival" in Story.pending(Campaign.load_progress(), 0, true):
		errors.append("story triggers: no festival beat near the Fest")
	_see_all(0)
	if not Story.pending(Campaign.load_progress(), 0, true).is_empty():
		errors.append("story triggers: pending after everything was seen")
	# stage 1 won: its result and stage 2's phone message, once
	Campaign.record_result(0, 1)
	p = Story.pending(Campaign.load_progress(), 0)
	if not "stage_1_won" in p or not "open_stage_2" in p or "stage_1_miss" in p:
		errors.append("story triggers: after stage 1: %s" % [p])
	if p.find("stage_1_won") > p.find("open_stage_2"):
		errors.append("story triggers: phone before results: %s" % [p])
	_see_all(0)
	# stage 2 lost: the miss beat once, not again on the next loss; the win later still plays
	Campaign.record_result(1, 9)
	p = Story.pending(Campaign.load_progress(), 0)
	if p != ["stage_2_miss"]:
		errors.append("story triggers: after losing stage 2: %s" % [p])
	_see_all(0)
	Campaign.record_result(1, 9)
	if not Story.pending(Campaign.load_progress(), 0).is_empty():
		errors.append("story triggers: a second loss replays")
	Campaign.record_result(1, 1)
	if not "stage_2_won" in Story.pending(Campaign.load_progress(), 0):
		errors.append("story triggers: no won beat after a miss")
	_see_all(0)
	# the act changes with the unlocked stage
	Campaign.record_result(2, 1)
	Campaign.record_result(3, 1)
	p = Story.pending(Campaign.load_progress(), 0)
	if not "act_2" in p or "act_3" in p:
		errors.append("story triggers: act II: %s" % [p])
	_see_all(0)
	# a mission's reward car
	var ko := Missions.index_of("knockout_bor")
	Missions.record(ko, {"pos": 1, "success": true, "tier": 0, "score": 0})
	p = Story.pending(Campaign.load_progress(), 0)
	if not "knockout_bor_won" in p or not "car_golf4" in p:
		errors.append("story triggers: knockout won: %s" % [p])
	_see_all(0)
	# the before beat plays once
	if Story.before_key(0) != "stage_1_before":
		errors.append("story triggers: before_key")
	Story.mark_seen([Story.before_key(0)])
	if Story.before_key(0) != "":
		errors.append("story triggers: a before beat plays twice")
	# the Goliath opens on fans, the epilogue after it
	for i in range(4, Campaign.STAGES.size() - 1):
		Campaign.record_result(i, 1)
	var top := int(FanLevels.THRESHOLDS[FanLevels.THRESHOLDS.size() - 1])
	p = Story.pending(Campaign.load_progress(), 0)
	if "open_stage_10" in p or not "act_3" in p:
		errors.append("story triggers: before the fans: %s" % [p])
	p = Story.pending(Campaign.load_progress(), top)
	if not "open_stage_10" in p:
		errors.append("story triggers: the Goliath's message with the fans: %s" % [p])
	_see_all(top)
	if not Story.next_step(Campaign.load_progress(), top).contains("Goliath"):
		errors.append("story triggers: next step before the finale: %s" % Story.next_step(Campaign.load_progress(), top))
	var prog := Campaign.load_progress()
	(prog.trophies as Array).append(String(Campaign.STAGES[Campaign.STAGES.size() - 1].trophy))
	Campaign.save_progress(prog)
	p = Story.pending(Campaign.load_progress(), top)
	if not "stage_10_won" in p or not "epilogue" in p or p.find("epilogue") < p.find("stage_10_won"):
		errors.append("story triggers: the finale: %s" % [p])
	_see_all(top)
	if Story.act_name(Campaign.load_progress()) != "Epilogue":
		errors.append("story triggers: act after the finale is %s" % Story.act_name(Campaign.load_progress()))

func _see_all(fans: int) -> void:
	Story.mark_seen(Story.pending(Campaign.load_progress(), fans, true))

func _card(errors: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new() # the canvas: the card fills it
	tree.root.add_child(host)
	var card := StoryCard.new()
	host.add_child(card)
	var done := [0, 0] # callbacks, skipped finishes
	card.finished.connect(func(skipped: bool): done[1] += int(skipped))
	card.play(Story.cards(["stage_1_before"]), func(): done[0] += 1)
	var n := Story.lines("stage_1_before").size()
	if not card.is_open() or card.line_total() != n or card.current_speaker() != "ola":
		errors.append("story card: play")
	card.handle(_key(KEY_ENTER))
	if card.line_index() != 1:
		errors.append("story card: Enter does not advance")
	card.handle(_pad(JOY_BUTTON_A))
	if card.line_index() != 2:
		errors.append("story card: pad A does not advance")
	if card.handle(_key(KEY_W)):
		errors.append("story card: it takes the driving keys")
	if not card.handle(_pad(JOY_BUTTON_START)):
		errors.append("story card: START reaches the pause menu under the card")
	card.handle(_pad(JOY_BUTTON_A))
	if card.is_open() or done[0] != 1 or done[1] != 0:
		errors.append("story card: finishing the beat %s" % [done])
	card.play(Story.cards(["intro"]), func(): done[0] += 1)
	card.handle(_key(KEY_ESCAPE))
	if card.is_open() or done != [2, 1]:
		errors.append("story card: Esc does not skip %s" % [done])
	card.play(Story.cards(["intro"]), func(): done[0] += 1)
	card.handle(_pad(JOY_BUTTON_B))
	if card.is_open() or done != [3, 2]:
		errors.append("story card: pad B does not skip %s" % [done])
	if card.handle(_key(KEY_ENTER)):
		errors.append("story card: a closed card takes Enter")
	# the journal: ◂ ▸ jump whole beats
	card.play(Story.cards(["intro", "festival"]), Callable(), true)
	card.handle(_key(KEY_RIGHT))
	if card.line_index() != Story.lines("intro").size():
		errors.append("story card: ▸ does not jump a beat")
	card.handle(_pad(JOY_BUTTON_DPAD_LEFT))
	if card.line_index() != 0:
		errors.append("story card: ◂ does not jump back")
	card.skip()
	# layout: the longest line fits on the canvas at every size, clear of the bottom strip
	var longest := ""
	var at := ""
	for key: String in Story.BEATS:
		for ln in Story.lines(key):
			if String(ln[1]).length() > longest.length():
				longest = String(ln[1])
				at = key
	for cv: Vector2 in CANVASES:
		host.size = cv
		card.play([{"title": "TEST", "lines": [["mirek", longest]]}])
		for _f in 3:
			await tree.process_frame
		var r := card.panel.get_rect()
		if r.position.x < 0.0 or r.end.x > cv.x or r.position.y < cv.y * 0.45 or r.end.y > cv.y - StoryCard.BOTTOM + 1.0:
			errors.append("story card: %s at %dx%d sits at %s" % [at, cv.x, cv.y, r])
		if not card.size.is_equal_approx(cv):
			errors.append("story card: does not fill a %dx%d canvas (%s)" % [cv.x, cv.y, card.size])
		card.skip()
	host.queue_free()
	await tree.process_frame

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e

func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e
