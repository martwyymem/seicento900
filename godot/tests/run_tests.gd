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
	"res://tests/test_surfaces.gd",
	"res://tests/test_surface_feedback.gd",
	"res://tests/test_time_trial.gd",
	"res://tests/test_pace_notes.gd",
	"res://tests/test_world_audio.gd",
	"res://tests/test_options.gd",
	"res://tests/test_retro_pipeline.gd",
	"res://tests/test_fx_particles.gd",
	"res://tests/test_open_world.gd",
	"res://tests/test_open_world_cache.gd",
	"res://tests/test_loading_screen.gd",
	"res://tests/test_open_world_terrain.gd",
	"res://tests/test_open_world_lakes.gd",
	"res://tests/test_invisible_walls.gd",
	"res://tests/test_open_world_ramps.gd",
	"res://tests/test_open_world_roads.gd",
	"res://tests/test_open_world_bridges.gd",
	"res://tests/test_free_car_collision.gd",
	"res://tests/test_train_collision.gd",
	"res://tests/test_open_world_layers.gd",
	"res://tests/test_traffic.gd",
	"res://tests/test_open_world_kerbs.gd",
	"res://tests/test_open_world_lamps.gd",
	"res://tests/test_open_world_spawn.gd",
	"res://tests/test_car_lamps.gd",
	"res://tests/test_free_car_rest.gd",
	"res://tests/test_vegetation.gd",
	"res://tests/test_roadside_props.gd",
	"res://tests/test_building_walls.gd",
	"res://tests/test_ui_layout.gd",
	"res://tests/test_hud_motion.gd",
	"res://tests/test_track_switch.gd",
	"res://tests/test_hud_skins.gd",
	"res://tests/test_result_table.gd",
	"res://tests/test_map_marker.gd",
	"res://tests/test_map_nav.gd",
	"res://tests/test_poi.gd",
	"res://tests/test_gamepad_menus.gd",
	"res://tests/test_name_field.gd",
	"res://tests/test_model_contract.gd",
	"res://tests/test_handbrake.gd",
	"res://tests/test_fan_levels.gd",
	"res://tests/test_hypercar.gd",
	"res://tests/test_car_catalog.gd",
	"res://tests/test_garage.gd",
	"res://tests/test_dev_menu.gd",
	"res://tests/test_car_mods.gd",
	"res://tests/test_goliath.gd",
	"res://tests/test_cobbles.gd",
	"res://tests/test_street_tracks.gd",
	"res://tests/test_chase_cam.gd",
	"res://tests/test_camera_look.gd",
	"res://tests/test_damage_policy.gd",
	"res://tests/test_routes.gd",
	"res://tests/test_missions.gd",
	"res://tests/test_story.gd",
	"res://tests/test_live_events.gd",
	"res://tests/test_mission_weather.gd",
	"res://tests/test_world_weather.gd",
	"res://tests/test_street_rivals.gd"
]

const SURROUNDINGS := preload("res://scripts/ui/surroundings.gd")
const FURNITURE := preload("res://scripts/ui/trackside_furniture.gd")
const CAR_VISUAL := preload("res://scripts/ui/race_car_visual.gd")
const WORLD := preload("res://scripts/ui/race_world.gd")

## Per-suite watchdog timeout in seconds (override with TEST_SUITE_TIMEOUT; 0 disables).
const DEFAULT_SUITE_TIMEOUT_SEC := 300
const HARD_WATCHDOG_GRACE_MSEC := 5000

var _wd_mutex: Mutex
var _wd_thread: Thread
var _wd_stop := false
var _wd_active := false
var _wd_suite := ""
var _wd_started_msec := 0
var _wd_hard_msec := 0

class _SuiteRun:
	var done := false
	var result: Variant = null

	func exec(suite: Object) -> void:
		result = await suite.run()
		done = true

func _suite_timeout_msec() -> int:
	var env := OS.get_environment("TEST_SUITE_TIMEOUT")
	var sec := DEFAULT_SUITE_TIMEOUT_SEC if env == "" else int(env)
	return maxi(0, sec) * 1000

func _start_watchdog(timeout_msec: int) -> void:
	if timeout_msec <= 0:
		return
	_wd_mutex = Mutex.new()
	_wd_stop = false
	_wd_active = false
	_wd_hard_msec = timeout_msec + HARD_WATCHDOG_GRACE_MSEC
	_wd_thread = Thread.new()
	_wd_thread.start(_watchdog_loop)

func _set_watchdog(path: String, active: bool) -> void:
	if _wd_mutex == null:
		return
	_wd_mutex.lock()
	_wd_suite = path
	_wd_started_msec = Time.get_ticks_msec()
	_wd_active = active
	_wd_mutex.unlock()

func _stop_watchdog() -> void:
	if _wd_mutex != null:
		_wd_mutex.lock()
		_wd_stop = true
		_wd_active = false
		_wd_mutex.unlock()
	if _wd_thread != null:
		_wd_thread.wait_to_finish()
		_wd_thread = null
	_wd_mutex = null

func _watchdog_loop() -> void:
	while true:
		OS.delay_msec(250)
		_wd_mutex.lock()
		var stop := _wd_stop
		var active := _wd_active
		var suite := _wd_suite
		var elapsed := Time.get_ticks_msec() - _wd_started_msec
		var limit := _wd_hard_msec
		_wd_mutex.unlock()
		if stop:
			return
		if active and elapsed >= limit:
			var msg := "FAIL %s\n    watchdog timeout after %.1f s (main thread blocked in synchronous loop or deadlock)" % [suite, elapsed / 1000.0]
			print(msg)
			printerr(msg)
			OS.kill(OS.get_process_id())
			return

func _initialize() -> void:
	# the root joins the tree only after the first frame: until then a node a suite adds to it never gets _ready
	await process_frame
	var timeout_msec := _suite_timeout_msec()
	_start_watchdog(timeout_msec)
	var failed := 0
	for path in SUITES:
		print("run  %s" % path)
		var script = load(path)
		var errors: Array = ["failed to load (compile error above)"]
		if script and script.can_instantiate():
			var suite = script.new()
			var started_msec := Time.get_ticks_msec()
			_set_watchdog(path, true)
			var runner := _SuiteRun.new()
			runner.exec(suite)
			var timed_out := false
			while not runner.done:
				if timeout_msec > 0 and Time.get_ticks_msec() - started_msec >= timeout_msec:
					timed_out = true
					errors = ["watchdog timeout after %.1f s (suite still awaiting frames)" % ((Time.get_ticks_msec() - started_msec) / 1000.0)]
					for n in root.get_children():
						n.free()
					break
				await process_frame
			_set_watchdog("", false)
			if not timed_out:
				errors = runner.result if runner.result is Array else []
				if not suite.get("completed"):
					errors.append("run() aborted by a script error (see above)")
		print("%s %s" % ["FAIL" if errors else "ok  ", path])
		for e in errors.slice(0, 20):
			print("    ", e)
		failed += errors.size()
	_stop_watchdog()
	print("%d failure(s)" % failed)
	await release(self)
	quit(1 if failed else 0)

## Frees what the suites leave behind (nodes, and the meshes, noise and fonts the game caches in static
## variables) so the run ends without leak warnings.
static func release(tree: SceneTree) -> void:
	for n in tree.root.get_children():
		n.free()
	SURROUNDINGS._tree_meshes.clear()
	SURROUNDINGS._tree_proxies.clear()
	SURROUNDINGS._tree_proxy_material = null
	SURROUNDINGS._landmark_meshes.clear()
	FURNITURE._meshes.clear()
	preload("res://scripts/ui/roadside_props.gd")._meshes.clear()
	CAR_VISUAL._shared.clear()
	WORLD._noise.clear()
	WORLD._trackside.clear()
	CmrStyle._fonts.clear()
	Race._track_cache.clear()
	TownMap._cache.clear()
	Brain._store = null
	await tree.process_frame
	await tree.process_frame
