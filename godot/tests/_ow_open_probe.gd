## Headless: times OpenWorld.open() end to end as the campaign runs it (OW_BUILD_TIMES=1 for the per-step lines).
## godot --headless --path godot -s tests/_ow_open_probe.gd   (NOCACHE=1 builds without the user:// mesh cache)
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var ow := OpenWorld.new()
	root.add_child(ow)
	print("OpenWorld.new + _ready  %d ms" % (Time.get_ticks_msec() - t0))
	var t1 := Time.get_ticks_msec()
	await ow.open("")
	print("open() total            %d ms" % (Time.get_ticks_msec() - t1))
	var t2 := Time.get_ticks_msec()
	await process_frame
	print("first frame             %d ms" % (Time.get_ticks_msec() - t2))
	print("TOTAL                   %d ms" % (Time.get_ticks_msec() - t0))
	print("cache: ", ow.builder.cache_log)
	quit()
