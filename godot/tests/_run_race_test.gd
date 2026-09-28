extends SceneTree
func _init():
	var suite = load("res://tests/test_race.gd").new()
	var errs = suite.run()
	print("completed=", suite.completed, " errors=", errs.size())
	for e in errs.slice(0, 20): print("  ", e)
	quit()
