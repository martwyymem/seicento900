## Headless: every retro mode applies its CmrStyle skin without errors and restyles a live game.tscn.
## godot --headless --path godot -s tests/_ui_skins.gd
extends SceneTree

var _fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	var game: Control = load("res://ui/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var chars := "ąćęłńóśźż◂▸←→↑↓Ⓐ Ⓑ"
	for mode in CmrStyle.SKIN_FOR_MODE.size():
		game._on_retro_selected(mode)
		await process_frame
		var name := CmrStyle.skin_for_mode(mode)
		_check(CmrStyle.skin == name, "mode %d skin %s" % [mode, CmrStyle.skin])
		var pal := CmrStyle.skin_palette(name)
		_check(game.menu_tint.color.is_equal_approx(CmrStyle.TINT_HOME), "%s: page tint %s" % [name, game.menu_tint.color])
		_check(game.menu_prompt.get_theme_color("font_color").is_equal_approx(CmrStyle.ORANGE_SOFT), "%s: prompt colour" % name)
		_check(game.theme.get_color("font_color", "Label").is_equal_approx(pal.TEXT), "%s: theme label colour" % name)
		var focus: StyleBoxFlat = game.theme.get_stylebox("focus", "Button")
		_check(focus.border_color.is_equal_approx(pal.FOCUS), "%s: focus ring" % name)
		# keys stay distinct, so the live recolour can tell them apart
		var keys := pal.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var a: Color = pal[keys[i]]
				var b: Color = pal[keys[j]]
				_check(absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.006, "%s: %s ~ %s" % [name, keys[i], keys[j]])
		for key in ["w250", "w400", "digits", "title"]:
			var f: Font = CmrStyle._cached(key)
			for c in chars:
				if c != " ":
					_check(f.has_char(c.unicode_at(0)), "%s: %s lacks %s" % [name, key, c])
		print("skin %d %s ok" % [mode, name])
	game._on_retro_selected(0)
	print("UI skins: %d failures" % _fails)
	quit(1 if _fails else 0)
