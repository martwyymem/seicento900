## Headless layout checks for the HUDs and the menus. At every canvas the window can give the interface
## (16:9, 16:10, 4:3 and 21:9 windows, and the 1.15 / 1.3 interface sizes, which shrink the 1600×900 design
## canvas), nothing that can be on screen at the same time overlaps and everything stays on the canvas.
## Headless draws nothing, so these compute the controls' rects; containers settle at the end of a frame, so
## the suite awaits a few frames where they matter (run_tests awaits run()).
extends RefCounted

var completed := false

## canvas sizes: 16:9, 16:10, 4:3, 21:9, then 16:9 and 4:3 at the 1.15 and 1.3 interface sizes
const CANVASES: Array[Vector2] = [Vector2(1600, 900), Vector2(1600, 1000), Vector2(1600, 1200), Vector2(2133, 900),
	Vector2(1391, 783), Vector2(1231, 692), Vector2(1231, 923)]
const LONG_SMALL := "An out lap to warm the tyres, then 2 timed laps — the fastest sets your grid slot · Brzęczyszczykiewicz"

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	var tree := Engine.get_main_loop() as SceneTree
	_check_race_hud(errors, tree)
	_check_overtake_calls(errors, tree)
	_check_solo_huds(errors, tree)
	_check_skins(errors, tree)
	await _check_open_world_hud(errors, tree)
	await _check_menus(errors, tree)
	completed = true
	return errors

# ------------------------------------------------------------------------------------------ helpers

## Lets containers and wrapped labels settle (sorting and minimum sizes update at the end of a frame).
static func _settle(tree: SceneTree, frames := 3) -> void:
	for k in frames:
		await tree.process_frame

## Where a control's anchors and offsets put it in a parent of size p (its own size may lag a frame).
static func _intended(c: Control, p: Vector2) -> Rect2:
	var a := Vector2(c.anchor_left * p.x + c.offset_left, c.anchor_top * p.y + c.offset_top)
	var b := Vector2(c.anchor_right * p.x + c.offset_right, c.anchor_bottom * p.y + c.offset_bottom)
	return Rect2(a, b - a)

## Every pair of the named rects must not overlap (by more than a pixel) and each must be on the canvas.
static func _no_overlap(errors: Array[String], where: String, rects: Dictionary, canvas: Vector2) -> void:
	var names := rects.keys()
	var screen := Rect2(Vector2.ZERO, canvas).grow(1.0)
	for i in names.size():
		var a: Rect2 = rects[names[i]]
		if not screen.encloses(a):
			errors.append("%s %dx%d: %s %s runs off the canvas" % [where, canvas.x, canvas.y, names[i], a])
		for j in range(i + 1, names.size()):
			var b: Rect2 = rects[names[j]]
			var cut := a.intersection(b)
			if cut.size.x > 1.0 and cut.size.y > 1.0:
				errors.append("%s %dx%d: %s %s overlaps %s %s" % [where, canvas.x, canvas.y, names[i], a, names[j], b])

static func _host(tree: SceneTree, canvas: Vector2) -> Control:
	var host := Control.new()
	host.size = canvas
	tree.root.add_child(host)
	return host

# ------------------------------------------------------------------------------------------ race HUD

## The race HUD with everything that can be up at once: start lights, a flag board, a split, an overtake
## call, the big banner and its line under it, the co-driver's chip, the full key help, a full event feed.
func _check_race_hud(errors: Array[String], tree: SceneTree) -> void:
	var rs := RaceSettings.new()
	rs.track = "monza"
	rs.opponents = 15
	var race := Race.new(rs)
	for canvas in CANVASES:
		var host := _host(tree, canvas)
		var hud := RaceHud.new()
		host.add_child(hud)
		hud.start(race, null, null)
		race.phase = "racing"
		race.race_time = 0.5
		hud._refresh_t = 0.0
		hud.update(0.0)
		hud._flag = {"title": "DOUBLE YELLOW", "sub": "Slow down, be ready to stop · no overtaking · V limiter off", "color": Color("#ffd21a")}
		hud._overtake_timer = 2.0
		hud._split_show = {"k": 1, "t": 61.25, "delta": 0.42, "until": race.race_time + 4.0}
		hud.banner.text = "Simulating the rest of the race…"
		hud.banner_small.text = LONG_SMALL
		hud._status_text = "CO-DRIVER  ·  TIME ×60  ( , . )"
		hud._help_label.text = RaceHud.HELP_TEXT
		hud._help_full = true
		hud._feed_h = 400.0
		hud._layout()
		var W := canvas.x
		var rects := {
			"tower": Rect2(hud.tower.position, Vector2(RaceHud.TOWER_W, hud.tower.size.y)),
			"clock": Rect2(W - RaceHud.EDGE - RaceHud.CLOCK_W, RaceHud.EDGE, RaceHud.CLOCK_W, 208.0),
			"minimap": _intended(hud.minimap, canvas),
			"feed": _intended(hud.feed, canvas),
			"pit wall": Rect2(Vector2(RaceHud.EDGE, canvas.y - RaceHud.EDGE - hud._pitwall_height()), Vector2(RaceHud.PITWALL_W, hud._pitwall_height())),
			"dash": _intended(hud.dash, canvas),
			"pace notes": Rect2(W * 0.5 - RaceHud.PACENOTE_HALF, RaceHud.EDGE, RaceHud.PACENOTE_HALF * 2.0, 132.0),
			"key help": hud.help_rect(),
			"status chip": _intended(hud.statusbar, canvas),
		}
		var shown := 0
		for pair in [["start lights", hud.lights], ["flag board", hud.flagbar], ["overtake", hud._overtake_control],
				["banner", hud.banner], ["banner line", hud.banner_small]]:
			var c: Control = pair[1]
			if c.self_modulate.a > 0.0:
				shown += 1
				var r := _intended(c, canvas)
				if c is Label:
					var tw := minf(r.size.x, hud._label_width(c as Label))
					r = Rect2(r.get_center().x - tw * 0.5, r.position.y, tw, r.size.y)
				rects[pair[0]] = r
		if shown < 3:
			errors.append("race HUD %dx%d: the centre column dropped too much (%d of 5 left)" % [canvas.x, canvas.y, shown])
		if not hud._split_beside and hud.splitbox.self_modulate.a > 0.0:
			rects["split"] = _intended(hud.splitbox, canvas)
		elif hud._split_beside:
			rects["split"] = Rect2(W - RaceHud.EDGE - RaceHud.CLOCK_W - 20.0 - 250.0, 32.0, RaceHud.SPLIT_W, 44.0)
		_no_overlap(errors, "race HUD", rects, canvas)
		# the help fits the room between the pit wall and the dash
		var hr: Rect2 = rects["key help"]
		if hr.size.y > 160.0:
			errors.append("race HUD %dx%d: the key help wrapped to %d px" % [canvas.x, canvas.y, hr.size.y])
		host.free()
	race.dispose()

## Overtakes are only called under green; the autopilot note is a chip at the bottom, not the banner.
func _check_overtake_calls(errors: Array[String], tree: SceneTree) -> void:
	var rs := RaceSettings.new()
	rs.track = "monza"
	rs.opponents = 5
	var race := Race.new(rs)
	var host := _host(tree, Vector2(1600, 900))
	var hud := RaceHud.new()
	host.add_child(hud)
	hud.start(race, null, null)
	race.phase = "racing"
	race.race_time = 30.0
	race.clock = 30.0
	if race.rc == null:
		errors.append("the overtake check needs race control on")
	else:
		race.rc.green_t = -100.0
		race.player.pos = 3
		for f in ["sc", "sc_in", "red"]:
			race.rc.flag = f
			hud._overtake_timer = 0.0
			hud._prev_player_pos = 4
			hud.update(0.016)
			if hud._overtake_timer > 0.0:
				errors.append("an overtake was called under flag '%s'" % f)
		race.rc.flag = "sc"
		hud._overtake_timer = 2.0
		hud.update(0.016)
		if hud._overtake_timer > 0.0:
			errors.append("an overtake call already up should go when the safety car comes out")
		race.rc.flag = "green"
		hud._overtake_timer = 0.0
		hud._prev_player_pos = 4
		hud.update(0.016)
		if hud._overtake_timer <= 0.0:
			errors.append("a pass under green should still be called (flag board %s)" % [hud._flag])
	race.player.autopilot = true
	hud._refresh_t = 0.0
	hud.update(0.016)
	if "AUTOPILOT" in hud.banner_small.text or "AUTOPILOT" in hud.banner.text:
		errors.append("AUTOPILOT should not be in the banner (it covered the leader's name tag)")
	if not "AUTOPILOT" in hud._status_text:
		errors.append("AUTOPILOT should show in the status chip, got '%s'" % hud._status_text)
	var chip := _intended(hud.statusbar, Vector2(1600, 900))
	if chip.position.y < 700.0:
		errors.append("the status chip should sit at the bottom, above the key help: %s" % chip)
	host.free()
	race.dispose()

## Rally stage and time trial: the stage panel (or sectors) top left, the delta bar in the centre column.
func _check_solo_huds(errors: Array[String], tree: SceneTree) -> void:
	var ev := RallyEvent.new("sprint", 1)
	var rally := Race.new(ev.settings_for_stage(), null, 2)
	ev.begin_stage(rally)
	var st := RaceSettings.new()
	st.track = "fiat"
	TimeTrial.configure(st, true)
	var tt := Race.new(st)
	for pair in [["rally", rally], ["time trial", tt]]:
		var race: Race = pair[1]
		for canvas in CANVASES:
			var host := _host(tree, canvas)
			var hud := RaceHud.new()
			host.add_child(hud)
			hud.start(race, null, null)
			race.phase = "racing"
			race.race_time = 5.0
			hud._refresh_t = 0.0
			hud.update(0.0)
			hud._mode_split = {"k": 1, "t": 62.4, "gap": 1.25, "pos": 4, "leader": "Colin McRae", "until": hud._clock + 5.0,
				"lap": {"n": 3, "time": 92.5, "valid": true}}
			hud.banner.text = "WRONG WAY"
			hud.banner_small.text = "Turn around! Or press Backspace / R to reset car"
			hud._status_text = "AUTOPILOT  ·  O"
			hud._layout()
			var rects := {
				"stage panel": Rect2(hud.modepanel.position, Vector2(RaceHud.MODE_W, hud.modepanel.size.y)),
				"clock": Rect2(canvas.x - RaceHud.EDGE - RaceHud.CLOCK_W, RaceHud.EDGE, RaceHud.CLOCK_W, 208.0),
				"minimap": _intended(hud.minimap, canvas),
				"dash": _intended(hud.dash, canvas),
				"key help": hud.help_rect(),
				"status chip": _intended(hud.statusbar, canvas),
				"delta bar": _intended(hud.deltabar, canvas),
				"pace notes": Rect2(canvas.x * 0.5 - RaceHud.PACENOTE_HALF, RaceHud.EDGE, RaceHud.PACENOTE_HALF * 2.0, 132.0),
			}
			if hud.deltabar.self_modulate.a <= 0.0 or not hud._delta_showing():
				errors.append("%s HUD %dx%d: the delta bar should be up" % [pair[0], canvas.x, canvas.y])
			_no_overlap(errors, "%s HUD" % pair[0], rects, canvas)
			host.free()
	rally.dispose()
	tt.dispose()

# ------------------------------------------------------------------------------------------ skins

## A skin switch reaches the HUDs: the race HUD's plates and the open world's cards take the new palette
## (they stayed dark purple in every skin), the selectors draw their arrows, the PS1 faces are hard-edged.
func _check_skins(errors: Array[String], tree: SceneTree) -> void:
	var host := _host(tree, Vector2(1600, 900))
	var hud := RaceHud.new()
	host.add_child(hud)
	var ow := OpenWorldHud.new()
	host.add_child(ow)
	var sel := MenuSelector.new()
	sel.size = Vector2(300, 40)
	host.add_child(sel)
	sel.add_item("Kraków Royal Ring — the first ring round the Planty, under the Wawel walls")
	sel.add_item("Wet")
	for name in ["ps1", "mw", "sa", "carbon", "fh1", "cmr"]:
		CmrStyle.apply_skin(name, host)
		var plate: Color = CmrStyle.skin_palette(name).PLATE
		if not hud._panel_style.bg_color.is_equal_approx(Color(plate, 0.8)):
			errors.append("%s: the pit wall plate stays %s" % [name, hud._panel_style.bg_color])
		if not RaceHud._plate(1.0).is_equal_approx(plate):
			errors.append("%s: the HUD plate isn't the skin's" % name)
		var card := ow.card.get_theme_stylebox("panel") as StyleBoxFlat
		if not Color(card.bg_color, 1.0).is_equal_approx(plate):
			errors.append("%s: the open world's event card stays %s" % [name, card.bg_color])
		if not OpenWorldHud.ORANGE.is_equal_approx(CmrStyle.ORANGE):
			errors.append("%s: the open world's accent doesn't follow the skin" % name)
	for c in ["◂", "▸"]:
		if c in sel.text:
			errors.append("the selector should draw its arrows, not type them: '%s'" % sel.text)
	if not sel.text.ends_with("…"):
		errors.append("a value too long for the selector should end in '…' between the arrows: '%s'" % sel.text)
	var pixel := CmrStyle._face("res://fonts/PixelifySans.ttf") as FontFile
	if pixel == null or pixel.antialiasing != TextServer.FONT_ANTIALIASING_NONE:
		errors.append("the PS1 face should draw without antialiasing")
	if CmrStyle.skin != "cmr":
		CmrStyle.apply_skin("cmr")
	host.free()

# ------------------------------------------------------------------------------------------ open world

func _check_open_world_hud(errors: Array[String], tree: SceneTree) -> void:
	for canvas in CANVASES:
		var host := _host(tree, canvas)
		var hud := OpenWorldHud.new()
		host.add_child(hud)
		hud.set_stats(123456, 210, 1480, 18.5)
		hud.set_chain(4321, "DRIFT · NEAR MISS · AIR")
		for k in 4:
			hud.notify("DISCOVERED  ·  KOPALNIA WĘGLA KAMIENNEGO BRZESZCZE", "Szyb Andrzej — the old headframe over the Jawiszowice seam, still turning on the town's skyline %d" % k)
		hud.show_event("ACT II · REGIONAL CHAMPIONSHIP", "Stage 7: Kraków Royal Ring under the Wawel walls at night",
			"Eleven medium bots and a tight first ring round the Planty. Trams share the road on Basztowa, the cobbles under Wawel are slick in the wet, and the pit lane is short: plan one stop and look after the front tyres. " .repeat(2),
			"ENTER  ▸  START STAGE", CmrStyle.ORANGE)
		hud.show_area("Osiedle Paderewskiego · Brzeszcze-Jawiszowice")
		hud.set_street("Ulica Księdza Józefa Stanisława Kaczmarczyka")
		for k in 5:
			await tree.process_frame
			hud._layout()
		var banners := Rect2(hud.banners.position, hud.banners.size)
		var card := Rect2(hud.card.position, hud.card.size)
		var rects := {
			"stats": Rect2(hud.stats_box.position, hud.stats_box.size),
			"skill chain": Rect2(hud.chain_box.position, hud.chain_box.size),
			"banners": banners,
			"event card": card,
			"district": _text_rect(hud.area_label, canvas),
			"street": _text_rect(hud.street_label, canvas),
			"key help": _text_rect(hud.help_label, canvas),
			"satnav": _intended(hud.minimap, canvas),
			"speedometer": Rect2(canvas.x - 300, canvas.y - 230, 270, 200),
		}
		_no_overlap(errors, "open-world HUD", rects, canvas)
		host.free()

## The part of a centred label its text covers (at the font size _layout picked).
static func _text_rect(l: Label, canvas: Vector2) -> Rect2:
	var r := _intended(l, canvas)
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var tw := minf(r.size.x, f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var th := f.get_height(fs)
	return Rect2(r.get_center().x - tw * 0.5, r.position.y, tw, th)

# ------------------------------------------------------------------------------------------ menus

func _check_menus(errors: Array[String], tree: SceneTree) -> void:
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	for canvas: Vector2 in [Vector2(1600, 900), Vector2(1600, 1200), Vector2(2133, 900), Vector2(1231, 692)]:
		game.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		game.size = canvas
		await _settle(tree)
		var tag := "menus %dx%d" % [canvas.x, canvas.y]
		# the header: tabs, PLAYER 1 │ YOU, MAIN MENU side by side, none squeezed under another
		game._show_home()
		game._home_select(1, false)
		game._activate_home_item()
		await _settle(tree)
		var header: HBoxContainer = game.menu_header
		if header.get_combined_minimum_size().x > header.size.x + 1.0:
			errors.append("%s: the header needs %d px, has %d" % [tag, header.get_combined_minimum_size().x, header.size.x])
		var parts := {}
		for c in header.get_children():
			if (c as Control).visible:
				parts["%s %s" % [c.get_class(), c.get_index()]] = Rect2((c as Control).global_position, (c as Control).size)
		_no_overlap(errors, tag + " header", parts, canvas)
		# the circuit info map stays inside its frame, the page inside its box
		game._show_information_page()
		await _settle(tree)
		var map: Control = game.information_map
		var frame := map.get_parent() as Control
		if not Rect2(frame.global_position, frame.size).grow(1.0).encloses(Rect2(map.global_position, map.size)):
			errors.append("%s: the circuit map leaves its frame" % tag)
		if not frame.clip_contents and not map.clip_contents:
			errors.append("%s: the circuit map's frame should clip it" % tag)
		var column := frame.get_parent() as Control
		var page: Control = game.information_panel
		if column.global_position.y + column.get_combined_minimum_size().y > page.global_position.y + page.size.y + 1.0:
			errors.append("%s: the circuit info column runs past its page into the key hints" % tag)
		# the service page's note stays above the key hints
		game._show_repair_page()
		await _settle(tree)
		var copy: Label = game.repair_copy
		copy.text = "Bent panels and a twisted shell: the car pushes more air and sits crooked. " .repeat(4)
		await _settle(tree)
		var lines := mini(copy.get_line_count(), copy.max_lines_visible if copy.max_lines_visible >= 0 else 999)
		var need := lines * copy.get_line_height() + (lines - 1) * copy.get_theme_constant("line_spacing")
		if need > copy.size.y + 2.0:
			errors.append("%s: the service note needs %d px, has %d (it runs into the key hints)" % [tag, need, copy.size.y])
		# the campaign briefing opens with the stage title in view (and ENTER STAGE too when both fit)
		game.is_time_trial_mode = false
		game.is_rally_mode = false
		game.is_championship_mode = false
		game.is_campaign_mode = true
		var longest := 0
		for i in CampaignData.STAGES.size():
			var stg := CampaignData.get_stage(i)
			if str(stg.get("desc", "")).length() + str(stg.get("tip", "")).length() > str(CampaignData.get_stage(longest).get("desc", "")).length() + str(CampaignData.get_stage(longest).get("tip", "")).length():
				longest = i
		game.campaign_stage_index = longest
		game._update_mode_view()
		game._show_setup_page()
		await _settle(tree, 4)
		var scroll: ScrollContainer = game.menu_scroll
		var at: float = game._briefing_scroll()
		var content := scroll.get_child(0) as Control
		var top := content.global_position.y
		var title_y: float = (game.campaign_title_label as Control).global_position.y - top - at
		var button: Control = game.campaign_start_button
		var button_bottom := button.global_position.y - top + button.size.y - at
		if title_y < 0.0 or title_y > scroll.size.y:
			errors.append("%s: the briefing should open with the stage title in view (at %d of %d)" % [tag, title_y, scroll.size.y])
		var room: float = (game.campaign_title_label as Control).global_position.y - top
		if button_bottom > scroll.size.y + 1.0 and button.global_position.y - top + button.size.y - room <= scroll.size.y:
			errors.append("%s: ENTER STAGE should be in view with the title when both fit" % tag)
		game.is_campaign_mode = false
	game.queue_free() # (free() fails here: the coroutine runs inside the frame signal)
	await tree.process_frame

const CampaignData := preload("res://scripts/sim/campaign.gd")
