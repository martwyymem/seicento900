## Headless runner for the QA suites that are not (yet) listed in run_tests.gd:
##   godot --headless --path godot -s tests/run_qa.gd
## Same contract as run_tests.gd: a suite's run() returns its errors and sets `completed = true` last.
extends SceneTree

const SUITES := [
	"res://tests/test_open_world_borders.gd",
	"res://tests/test_car_visual_contract.gd",
]

func _initialize() -> void:
	await process_frame
	var failed := 0
	for path in SUITES:
		var script = load(path)
		var errors: Array = ["failed to load (compile error above)"]
		if script and script.can_instantiate():
			var suite = script.new()
			var result = await suite.run()
			errors = result if result is Array else []
			if not suite.get("completed"):
				errors.append("run() aborted by a script error (see above)")
		print("%s %s" % ["FAIL" if errors else "ok  ", path])
		for e in errors.slice(0, 30):
			print("    ", e)
		failed += errors.size()
	print("%d failure(s)" % failed)
	await load("res://tests/run_tests.gd").release(self)
	quit(1 if failed else 0)
