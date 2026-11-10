## Runs one test suite: godot --headless --path godot -s tests/_one_suite.gd -- res://tests/test_x.gd
extends SceneTree

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var suite = load(args[0] if args.size() else "res://tests/test_car_catalog.gd").new()
	var errors = await suite.run()
	print("completed=%s errors=%d" % [suite.get("completed"), errors.size()])
	for e in errors:
		print("    ", e)
	quit(0)
