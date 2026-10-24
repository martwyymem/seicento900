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
	"res://tests/test_ui_and_audio.gd",
	"res://tests/test_service_season.gd",
	"res://tests/test_qualifying.gd",
	"res://tests/test_lap_records.gd",
	"res://tests/test_rally.gd",
	"res://tests/test_time_trial.gd",
	"res://tests/test_pace_notes.gd",
	"res://tests/test_world_audio.gd",
	"res://tests/test_options.gd",
	"res://tests/test_retro_pipeline.gd",
	"res://tests/test_open_world.gd"
]

const SURROUNDINGS := preload("res://scripts/ui/surroundings.gd")
const FURNITURE := preload("res://scripts/ui/trackside_furniture.gd")
const CAR_VISUAL := preload("res://scripts/ui/race_car_visual.gd")
const WORLD := preload("res://scripts/ui/race_world.gd")

func _initialize() -> void:
	# the root joins the tree only after the first frame: until then a node a suite adds to it never gets _ready
	await process_frame
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
	await release(self)
	quit(1 if failed else 0)

## Frees what the suites leave behind (nodes, and the meshes, noise and fonts the game caches in static
## variables) so the run ends without leak warnings.
static func release(tree: SceneTree) -> void:
	for n in tree.root.get_children():
		n.free()
	SURROUNDINGS._tree_meshes.clear()
	SURROUNDINGS._landmark_meshes.clear()
	FURNITURE._meshes.clear()
	CAR_VISUAL._shared.clear()
	WORLD._noise.clear()
	WORLD._trackside.clear()
	CmrStyle._fonts.clear()
	Race._track_cache.clear()
	TownMap._cache.clear()
	Brain._store = null
	await tree.process_frame
	await tree.process_frame
