## Headless: times each step of the open-world build (map read, every TownBuilder step, car/traffic/train).
## godot --headless --path godot -s tests/_load_time_probe.gd   (CACHE=1: use the user:// mesh cache, run twice for warm)
extends SceneTree

func _initialize() -> void:
	var j0 := Time.get_ticks_usec()
	var txt := FileAccess.get_file_as_string("res://data/world/brzeszcze.json")
	var j1 := Time.get_ticks_usec()
	var raw = JSON.parse_string(txt)
	var j2 := Time.get_ticks_usec()
	var bytes := var_to_bytes(raw)
	var j3 := Time.get_ticks_usec()
	var back = bytes_to_var(bytes)
	var j4 := Time.get_ticks_usec()
	print("read %.0f  parse %.0f  to_bytes %.0f  from_bytes %.0f ms (%d MB)" % [(j1-j0)/1000.0, (j2-j1)/1000.0, (j3-j2)/1000.0, (j4-j3)/1000.0, bytes.size()/1000000])
	var t0 := Time.get_ticks_usec()
	var map := TownMap.load_map("brzeszcze", TownBuilder.MESH_CACHE_DIR if OS.get_environment("CACHE") != "" else "")
	var t1 := Time.get_ticks_usec()
	print("load_map            %7.0f ms" % ((t1 - t0) / 1000.0))
	var world := Node3D.new()
	root.add_child(world)
	var builder := TownBuilder.new(map, world)
	if OS.get_environment("CACHE") != "":
		builder.mesh_cache_dir = TownBuilder.MESH_CACHE_DIR
	var t2 := Time.get_ticks_usec()
	print("TownBuilder.new     %7.0f ms" % ((t2 - t1) / 1000.0))
	for s in builder.steps():
		var a := Time.get_ticks_usec()
		await (s[1] as Callable).call()
		print("%-20s%7.0f ms" % [s[0], (Time.get_ticks_usec() - a) / 1000.0])
	var b := Time.get_ticks_usec()
	var traffic := Traffic.new(map, world, builder)
	print("Traffic             %7.0f ms" % ((Time.get_ticks_usec() - b) / 1000.0))
	b = Time.get_ticks_usec()
	var train := Train.new(map, world, builder)
	print("Train               %7.0f ms" % ((Time.get_ticks_usec() - b) / 1000.0))
	print("TOTAL               %7.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	print("cache: ", builder.cache_log)
	quit()
