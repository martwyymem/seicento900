## The qualifying sheet and the championship standings tables (ResultTable): ordering with ties, points,
## gap and time formatting, penalties, long names, a long field that scrolls, and the layout through every
## skin (headless: containers settle at the end of a frame, so the layout part awaits frames).
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	_check_ranking(errors)
	_check_formatting(errors)
	_check_penalties(errors)
	await _check_layout(errors, Engine.get_main_loop() as SceneTree)
	await _check_game_tables(errors, Engine.get_main_loop() as SceneTree)
	completed = true
	return errors

static func _entry(id: int, name: String, points: int, wins: int) -> Dictionary:
	return {"id": id, "name": name, "points": points, "wins": wins, "number": id, "is_player": id == 1}

func _check_ranking(errors: Array[String]) -> void:
	var table := [_entry(5, "E", 10, 0), _entry(3, "C", 25, 1), _entry(4, "D", 25, 1), _entry(1, "A", 25, 2),
		_entry(2, "B", 10, 0), _entry(6, "F", 0, 0)]
	var r := ResultTable.rank_standings(table)
	var order := r.map(func(x: Dictionary) -> int: return x.entry.id)
	if order != [1, 3, 4, 2, 5, 6]:
		errors.append("standings order (points, wins, id): %s" % [order])
	var ranks := r.map(func(x: Dictionary) -> int: return x.rank)
	if ranks != [1, 2, 2, 4, 4, 6]:
		errors.append("tied cars share a rank (1, 2, 2, 4, 4, 6): %s" % [ranks])
	var tied := r.map(func(x: Dictionary) -> bool: return x.tied)
	if tied != [false, true, true, true, true, false]:
		errors.append("the tied flags mark both cars of a shared rank: %s" % [tied])
	if ResultTable.rank_text(2, true) != "2=" or ResultTable.rank_text(1, false) != "1":
		errors.append("rank text")
	if table[0].id != 5:
		errors.append("ranking should not reorder the caller's array")
	if not ResultTable.rank_standings([]).is_empty():
		errors.append("an empty table ranks to nothing")
	if ResultTable.points_gap(18, 25) != "−7" or ResultTable.points_gap(25, 25) != "":
		errors.append("points behind the leader: '%s'" % ResultTable.points_gap(18, 25))
	# the cells a standings row shows
	var cells := ResultTable.standings_cells(r[3], 25)
	if cells != ["4=", "B", "0", "10", "−15"]:
		errors.append("standings cells: %s" % [cells])

func _check_formatting(errors: Array[String]) -> void:
	var cases := [[null, ""], [0.0, ""], [0.2314, "+0.231"], [12.0, "+12.000"], [61.2, "+1:01.200"], [59.9996, "+1:00.000"], [125.5, "+2:05.500"]]
	for c in cases:
		var got := ResultTable.gap_text(c[0])
		if got != c[1]:
			errors.append("gap_text(%s) = '%s', expected '%s'" % [c[0], got, c[1]])
	if ResultTable.time_text(null) != "NO TIME":
		errors.append("no time reads NO TIME")
	if ResultTable.time_text(83.456) != "1:23.456":
		errors.append("time_text: %s" % ResultTable.time_text(83.456))
	if ResultTable.time_text(83.456, 5.0) != "1:23.456 +5s":
		errors.append("a penalty follows the time: %s" % ResultTable.time_text(83.456, 5.0))
	var pole := {"pos": 1, "name": "Pole Sitter", "time": 80.0, "gap": 0.0, "speed": 180.0}
	var last := {"pos": 12, "name": "Slow", "time": null, "gap": null, "speed": null}
	if ResultTable.quali_cells(pole) != ["1", "Pole Sitter", "1:20.000", "", "180.0"]:
		errors.append("pole's cells: %s" % [ResultTable.quali_cells(pole)])
	if ResultTable.quali_cells(last) != ["–", "Slow", "NO TIME", "", ""]:
		errors.append("a car with no time shows a dash for the position: %s" % [ResultTable.quali_cells(last)])

func _check_penalties(errors: Array[String]) -> void:
	var rows := [
		{"id": 1, "pos": 1, "name": "A", "time": 80.0, "penalty": 3.0},
		{"id": 2, "pos": 2, "name": "B", "time": 81.0},
		{"id": 3, "pos": 3, "name": "C", "time": null},
		{"id": 4, "pos": 4, "name": "D", "time": 82.0, "penalty": 0.0},
		{"id": 0, "pos": 5, "name": "E", "time": null}]
	var out := ResultTable.apply_penalties(rows)
	var names := out.map(func(r: Dictionary) -> String: return r.name)
	if names != ["B", "D", "A", "E", "C"]:
		errors.append("A's 3 s penalty (83 s) drops it behind B and D; no-time cars go last by id: %s" % [names])
	if absf(float(out[2].gap) - 2.0) > 0.0001 or out[0].gap != 0.0:
		errors.append("gaps follow the penalised times: %s %s" % [out[0].gap, out[2].gap])
	if out[3].gap != null or out[3].pos != 4:
		errors.append("a car with no time has no gap: %s" % [out[3]])
	var tied := ResultTable.apply_penalties([{"id": 9, "name": "X", "time": 80.0}, {"id": 4, "name": "Y", "time": 80.0}])
	if tied[0].name != "Y":
		errors.append("equal times fall back to the lower id")

## The table through every skin with many rows and a very long name: rows stay inside the table, the
## name is cut (not the numbers), the body scrolls at max_body and the header stays above it.
func _check_layout(errors: Array[String], tree: SceneTree) -> void:
	for skin in ["cmr", "ps1", "mw", "sa", "carbon", "fh1"]:
		CmrStyle.apply_skin(skin)
		for width in [560.0, 1000.0]:
			var host := Control.new()
			host.size = Vector2(width, 900)
			tree.root.add_child(host)
			var table := ResultTable.new()
			table.custom_minimum_size.x = width
			host.add_child(table)
			table.setup(ResultTable.standings_columns(), 300.0)
			var entries := []
			for i in 40:
				entries.append(_entry(i + 1, "Driver %d" % i if i != 3 else "Maximilian Brzęczyszczykiewicz-Wąchała III", 100 - i / 2, i % 3 == 0))
			var ranked := ResultTable.rank_standings(entries)
			for r in ranked:
				table.add_row(ResultTable.standings_cells(r, 100), r.entry.is_player, null, false)
			for k in 3:
				await tree.process_frame
			var tag := "table %s/%d" % [skin, width]
			if table.scroll.size.y > 301.0:
				errors.append("%s: the body is %d px tall, it should scroll at 300" % [tag, table.scroll.size.y])
			if table.scroll.get_v_scroll_bar().max_value <= table.scroll.size.y:
				errors.append("%s: 40 rows should need scrolling (content %d, view %d)" % [tag, table.scroll.get_v_scroll_bar().max_value, table.scroll.size.y])
			if table.size.x > width + 1.0:
				errors.append("%s: the table grew to %d px, past the %d it was given" % [tag, table.size.x, width])
			var header := table.get_child(0) as Control
			if header.global_position.y >= table.scroll.global_position.y:
				errors.append("%s: the header should sit above the rows" % tag)
			# every row and every cell stays inside the table's width
			var table_rect := Rect2(table.global_position, table.size).grow(1.0)
			for row in [header] + table.body.get_children().slice(0, 6):
				var rr := Rect2((row as Control).global_position, (row as Control).size)
				if rr.end.x > table_rect.end.x + 1.0:
					errors.append("%s: a row runs %d px past the table" % [tag, rr.end.x - table_rect.end.x])
				for l in _labels(row):
					if l.size.x > 0.0 and not rr.grow(1.0).encloses(Rect2(l.global_position, l.size)):
						errors.append("%s: '%s' leaves its row" % [tag, l.text])
					# numbers are never cut; only the driver column may
					var full := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
					if l.size_flags_horizontal & Control.SIZE_EXPAND == 0 and full > l.size.x + 1.0:
						errors.append("%s: '%s' (%d px) is cut to %d px" % [tag, l.text, full, l.size.x])
			# the long name is cut with an ellipsis, not run on
			var long_row := table.body.get_child(ranked.map(func(r: Dictionary) -> int: return r.entry.id).find(4)) as Control
			var name_label: Label
			for l in _labels(long_row):
				if l.text.begins_with("Maximilian"):
					name_label = l
			if name_label == null or not name_label.clip_text or name_label.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
				errors.append("%s: a long name is trimmed with an ellipsis" % tag)
			host.free()
	CmrStyle.apply_skin("cmr")

static func _labels(n: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in n.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out

## The game's own standings and quali sheet use the table: points from the points tables, the DNF rule,
## and the standings built from champ_data.
func _check_game_tables(errors: Array[String], tree: SceneTree) -> void:
	var game = load("res://ui/game.tscn").instantiate()
	tree.root.add_child(game)
	await tree.process_frame
	var pts: Array = game._points_table()
	var car_ok := {"dnf": false}
	var car_dnf := {"dnf": true}
	if game._round_points({"car": car_ok, "pos": 1}) != pts[0] or game._round_points({"car": car_ok, "pos": pts.size()}) != pts[-1]:
		errors.append("round points follow the table")
	if game._round_points({"car": car_ok, "pos": pts.size() + 1}) != 0 or game._round_points({"car": car_dnf, "pos": 1}) != 0:
		errors.append("no points outside the table or for a DNF")
	game.champ_data = {"round": 2, "table": {}}
	for i in 24:
		game.champ_data.table[str(i)] = _entry(i + 1, "Racer %d" % i, 30 - i / 2, 0)
	var col := VBoxContainer.new()
	game.add_child(col)
	game._render_championship_standings(col)
	await tree.process_frame
	var table: ResultTable = null
	for c in col.get_children():
		if c is ResultTable:
			table = c
	if table == null:
		errors.append("the standings render a ResultTable")
	elif table.rows_added != 24:
		errors.append("every driver gets a row, got %d" % table.rows_added)
	var order: Array = game._sorted_standings()
	if order.size() != 24 or int(order[0].points) < int(order[-1].points):
		errors.append("_sorted_standings is best first")
	# the quali sheet: a 16-car field, the player without a time sitting last
	Brain.use_disk = false
	var st := RaceSettings.new()
	st.track = "gp"
	st.opponents = 15
	Qualifying.configure(st)
	var q := Race.new(st, null, 31)
	var sheet := Qualifying.sheet(q, null)
	game._show_quali_sheet(q, sheet, true)
	for k in 6:
		await tree.process_frame
	var quali_table: ResultTable = null
	for n in _all(game.result_scroll):
		if n is ResultTable:
			quali_table = n
	if quali_table == null:
		errors.append("the quali sheet renders a ResultTable")
	elif quali_table.rows_added != 16:
		errors.append("the quali sheet has a row for every car (16), got %d" % quali_table.rows_added)
	elif quali_table.body_height() > 560.0:
		errors.append("the quali table is capped at 560 px, it is %d" % quali_table.body_height())
	q.dispose()
	game.queue_free()
	await tree.process_frame

static func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out
