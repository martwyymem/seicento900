extends SceneTree
func _initialize():
	var suite = load("res://tests/test_race.gd").new()
	var errs = suite.run()
	print("completed=", suite.completed, " errors=", errs.size())
	for e in errs.slice(0, 20): print("  ", e)
	await preload("res://tests/run_tests.gd").release(self)
	quit(0 if suite.completed and errs.is_empty() else 1)
