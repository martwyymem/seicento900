## OpenWorldHud.set_stats runs every frame but only updates texts / re-lays out when a shown figure changes.
## This checks the texts still follow fans, roads, the clock minute and the weather word.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	var hud := OpenWorldHud.new()
	host.add_child(hud)
	hud.set_stats(1200, 10, 100, 9.5, "")
	_expect(errors, hud.clock_label.text == "09:30", "clock 09:30, got '%s'" % hud.clock_label.text)
	_expect(errors, hud.roads_label.text.contains("10 / 100"), "roads text, got '%s'" % hud.roads_label.text)
	hud.set_stats(1200, 10, 100, 9.5, "RAIN")
	_expect(errors, hud.clock_label.text == "09:30  ·  RAIN", "weather appended once, got '%s'" % hud.clock_label.text)
	hud.set_stats(1200, 10, 100, 9.5, "RAIN")
	_expect(errors, hud.clock_label.text == "09:30  ·  RAIN", "steady call must not append again, got '%s'" % hud.clock_label.text)
	hud.set_stats(1200, 10, 100, 9.51, "RAIN")
	hud.set_stats(1200, 10, 100, 9.75, "")
	_expect(errors, hud.clock_label.text == "09:45", "clock minute + cleared weather, got '%s'" % hud.clock_label.text)
	hud.set_stats(1200, 11, 100, 9.75, "")
	_expect(errors, hud.roads_label.text.contains("11 / 100"), "roads change, got '%s'" % hud.roads_label.text)
	hud.set_stats(9000, 11, 100, 9.75, "")
	_expect(errors, hud.level_label.text == "LEVEL %d · %s%s" % [FanLevels.level(9000), FanLevels.title(FanLevels.level(9000)).to_upper(), "" if FanLevels.to_next(9000) < 0 else "  ·  %s TO NEXT" % OpenWorldHud._thousands(FanLevels.to_next(9000))], "level text after fans change, got '%s'" % hud.level_label.text)
	host.queue_free()
	completed = true
	return errors

func _expect(errors: Array[String], ok: bool, msg: String) -> void:
	if not ok:
		errors.append("hud stats cache: " + msg)
