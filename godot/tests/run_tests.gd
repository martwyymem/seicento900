## Headless test runner: godot --headless --path godot -s tests/run_tests.gd
extends SceneTree

const SUITES := ["res://tests/test_car.gd"]

func _init() -> void:
	var failed := 0
	for path in SUITES:
		var script = load(path)
		var errors: Array = ["failed to load (compile error above)"]
		if script and script.can_instantiate():
			var result = script.new().run()
			errors = result if result is Array else ["run() aborted by a script error (see above)"]
		print("%s %s" % ["FAIL" if errors else "ok  ", path])
		for e in errors.slice(0, 20):
			print("    ", e)
		failed += errors.size()
	print("%d failure(s)" % failed)
	quit(1 if failed else 0)
