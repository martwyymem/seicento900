## Headless layout check of the race HUD through every retro skin and the race states that change what it
## shows (grid with start lights, a normal lap, the final lap, a damaged and penalised car, a stop in the
## pits, a long driver name). In each: no two panels overlap, every drawn string fits the panel it is drawn
## in (and its stated width), and no two strings in one panel run into each other. RaceHud.text_audit
## records every string the panels draw. The skins use different faces (PS1 is wider), so this is what
## catches text a skin pushes out of its box.
extends RefCounted

var completed := false

const SKINS := ["cmr", "ps1", "mw", "sa", "carbon", "fh1"]
const CANVAS_SET: Array[Vector2] = [Vector2(1600, 900), Vector2(1231, 692), Vector2(1600, 1200)]
const STATES := ["grid", "lap 1", "final lap", "damaged", "in the pits", "long name"]

func run() -> Array:
	var errors: Array[String] = []
	Brain.use_disk = false
	LapRecords.use_disk = false
	var tree := Engine.get_main_loop() as SceneTree
	for skin in SKINS:
		CmrStyle.apply_skin(skin)
		for state in STATES:
			var rs := RaceSettings.new()
			rs.track = "monza"
			rs.opponents = 15
			rs.laps = 3
			var race := Race.new(rs)
			_set_state(race, state)
			for canvas in CANVAS_SET:
				await _check(errors, tree, race, state, skin, canvas)
			race.dispose()
	CmrStyle.apply_skin("cmr")
	completed = true
	return errors

static func _set_state(race: Race, state: String) -> void:
	var p := race.player
	race.phase = "countdown"
	race.clock = 3.2
	if state != "grid":
		race.phase = "racing"
		race.race_time = 40.0
		race.clock = 40.0
	match state:
		"final lap":
			p.lap = 3
			p.pos = 12
		"damaged":
			p.damage = 0.42
			p.penalty = 10.0
			p.pos = 7
		"in the pits":
			p.mode = "pit"
			p.pit = {"phase": "service", "entered_at": 30.0, "hold": 0.0, "wait": 0.0, "total": 6.4, "left": 2.1}
		"long name":
			p.name = "Maximilian Brzęczyszczykiewicz-Wąchała"
			for c in race.cars:
				if c != p:
					c.name = "Konstantinos Papadopoulos-Whittington"
					break

func _check(errors: Array[String], tree: SceneTree, race: Race, state: String, skin: String, canvas: Vector2) -> void:
	var tag := "HUD %s / %s / %dx%d" % [skin, state, canvas.x, canvas.y]
	var host := Control.new()
	host.size = canvas
	tree.root.add_child(host)
	var hud := RaceHud.new()
	host.add_child(hud)
	hud.text_audit = []
	hud.start(race, null, null)
	hud._flag = {}
	hud._refresh_t = 0.0
	hud.update(0.0)
	hud._help_full = false
	hud._layout()
	for k in 3:
		await tree.process_frame
	hud.update(0.0)
	hud._layout()
	await tree.process_frame
	# panels
	var rects := {}
	for pair in [["tower", hud.tower], ["clock", hud.clock], ["minimap", hud.minimap], ["feed", hud.feed], ["dash", hud.dash]]:
		rects[pair[0]] = _rect(pair[1], canvas)
	if hud.pitwall.visible:
		rects["pit wall"] = _rect(hud.pitwall, canvas)
	if hud.help.visible:
		rects["key help"] = hud.help_rect()
	for pair in [["start lights", hud.lights], ["banner", hud.banner], ["banner line", hud.banner_small]]:
		var c: Control = pair[1]
		if c.visible and c.self_modulate.a > 0.0 and (not c is Label or (c as Label).text != ""):
			var r := _rect(c, canvas)
			if c is Label:
				var tw := minf(r.size.x, hud._label_width(c as Label))
				r = Rect2(r.get_center().x - tw * 0.5, r.position.y, tw, r.size.y)
			rects[pair[0]] = r
	_overlaps(errors, tag, rects, canvas)
	# the state really showed what it is meant to (otherwise the checks below prove nothing)
	var drawn: Array = hud.text_audit.map(func(t: Array) -> String: return t[3])
	var wants := {"damaged": "DMG", "in the pits": "Crew working", "final lap": "P12", "grid": "P0"}
	if wants.has(state) and not drawn.any(func(x: String) -> bool: return x.begins_with(wants[state])):
		errors.append("%s: the HUD never drew '%s'" % [tag, wants[state]])
	# strings
	var seen := {}
	var by_canvas := {}
	for t in hud.text_audit:
		var c: Control = t[0]
		var key := [c.get_instance_id(), t[3], t[2]]
		if seen.has(key):
			continue
		seen[key] = true
		if not by_canvas.has(c):
			by_canvas[c] = []
		by_canvas[c].append(t)
	if hud.text_audit.is_empty():
		errors.append("%s: no text was drawn (the audit saw nothing)" % tag)
	for c in by_canvas:
		var boxes: Array[Rect2] = []
		var texts: Array[String] = []
		for t in by_canvas[c]:
			var f: Font = t[1]
			var s: String = t[3]
			var size: int = t[6]
			var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var limit: float = t[5]
			var shown_w := w
			if limit >= 0.0 and w > limit + 1.0:
				errors.append("%s: '%s' (%d px) is wider than the %d px it is drawn in" % [tag, s, w, limit])
				shown_w = limit
			var left: float = (t[2] as Vector2).x
			if limit >= 0.0:
				if t[4] == HORIZONTAL_ALIGNMENT_RIGHT:
					left += limit - shown_w
				elif t[4] == HORIZONTAL_ALIGNMENT_CENTER:
					left += (limit - shown_w) * 0.5
			# (ink band: capitals reach about 0.75 em above the baseline, descenders 0.2 below; the faces' own
			# ascent figures are too loose to compare)
			var top: float = (t[2] as Vector2).y - size * 0.75
			var box := Rect2(left, top, shown_w, size * 0.95)
			var panel := Rect2(Vector2.ZERO, (c as Control).size).grow(1.5)
			if (c as Control).size.x > 0.0 and not panel.encloses(box):
				errors.append("%s: '%s' %s leaves its %s panel %s" % [tag, s, box, c.get_class() if c == null else _name_of(hud, c), (c as Control).size])
			boxes.append(box)
			texts.append(s)
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				# glyph boxes of lines 1-2 px apart touch without colliding: shrink to the x-height band
				var a := boxes[i].grow_individual(0, -3, 0, -3)
				var b := boxes[j].grow_individual(0, -3, 0, -3)
				var cut := a.intersection(b)
				if cut.size.x > 2.0 and cut.size.y > 1.0:
					errors.append("%s: '%s' overlaps '%s' in %s" % [tag, texts[i], texts[j], _name_of(hud, c)])
	host.free()

static func _name_of(hud: RaceHud, c: Control) -> String:
	for pair in [["tower", hud.tower], ["clock", hud.clock], ["pit wall", hud.pitwall], ["feed", hud.feed], ["dash", hud.dash],
			["flag board", hud.flagbar], ["status chip", hud.statusbar], ["pace notes", hud.pacenote], ["split", hud.splitbox],
			["mode panel", hud.modepanel], ["delta bar", hud.deltabar], ["overtake", hud._overtake_control]]:
		if pair[1] == c:
			return pair[0]
	return str(c.name)

static func _rect(c: Control, p: Vector2) -> Rect2:
	var a := Vector2(c.anchor_left * p.x + c.offset_left, c.anchor_top * p.y + c.offset_top)
	var b := Vector2(c.anchor_right * p.x + c.offset_right, c.anchor_bottom * p.y + c.offset_bottom)
	if c == c.get_parent().get("tower"):
		return Rect2(c.position, c.size)
	return Rect2(a, b - a)

static func _overlaps(errors: Array[String], tag: String, rects: Dictionary, canvas: Vector2) -> void:
	var names := rects.keys()
	var screen := Rect2(Vector2.ZERO, canvas).grow(1.0)
	for i in names.size():
		var a: Rect2 = rects[names[i]]
		if not screen.encloses(a):
			errors.append("%s: %s %s runs off the canvas" % [tag, names[i], a])
		for j in range(i + 1, names.size()):
			var cut := a.intersection(rects[names[j]])
			if cut.size.x > 1.0 and cut.size.y > 1.0:
				errors.append("%s: %s %s overlaps %s %s" % [tag, names[i], a, names[j], rects[names[j]]])
