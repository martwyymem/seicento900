## Headless test runner: godot --headless --path godot -s tests/run_tests.gd
## Each suite's run() returns its error list and must set `completed = true` last: a script error aborts
## run() and still hands back an empty (typed) Array, so the flag is what tells a pass from a crash.
extends SceneTree

const SUITES := [
	"res://tests/test_car.gd",
	"res://tests/test_physics.gd",
	"res://tests/test_track.gd",
	"res://tests/test_strategy.gd",
	"res://tests/test_dynamics.gd",
	"res://tests/test_ui_and_audio.gd"
]

func _init() -> void:
	var failed := 0
	for path in SUITES:
		var script = load(path)
		var errors: Array = ["failed to load (compile error above)"]
		if script and script.can_instantiate():
			var suite = script.new()
			var result = suite.run()
			errors = result if result is Array else []
			if not suite.get("completed"):
				errors.append("run() aborted by a script error (see above)")
		print("%s %s" % ["FAIL" if errors else "ok  ", path])
		for e in errors.slice(0, 20):
			print("    ", e)
		failed += errors.size()
	print("%d failure(s)" % failed)
	quit(1 if failed else 0)
