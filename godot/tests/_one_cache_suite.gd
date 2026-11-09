extends SceneTree

const SUITE := "res://tests/test_open_world_cache.gd"

func _initialize() -> void:
	await process_frame
	var script = load(SUITE)
	var suite = script.new()
	var errors = await suite.run()
	print("completed=%s errors=%d" % [suite.get("completed"), errors.size()])
	for e in errors:
		print("    ", e)
	quit(0)
