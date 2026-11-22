## Headless: times each section of TownMap._from_raw on the brzeszcze bake (cold, no snapshot), and with OUT=<file>
## writes the MD5 of var_to_bytes of every snapshot member, one per line, to compare two versions of the loader.
## timeout 300 godot --headless --path godot -s tests/_map_profile_probe.gd
extends SceneTree

func _ms(t: int) -> String:
	return "%7.1f" % ((Time.get_ticks_usec() - t) / 1000.0)

func _initialize() -> void:
	var t0 := Time.get_ticks_usec()
	var m := TownMap.new()
	m.key = "brzeszcze"
	m.raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/brzeszcze.json"))
	print("read+parse          ", _ms(t0))
	var t := Time.get_ticks_usec()
	if OS.get_environment("INTASK") != "": # as the open world calls it: from a worker task
		WorkerThreadPool.wait_for_task_completion(WorkerThreadPool.add_task(m._from_raw, true))
		print("_from_raw           ", _ms(t))
	elif OS.get_environment("WHOLE") != "":
		m._from_raw()
		print("_from_raw           ", _ms(t))
	else:
		var steps := ["_load_roads", "_load_buildings", "_build_pavements", "_load_obstacles", "_load_rails",
			"_load_tunnels", "_load_rail_banks", "_add_tunnel_walls", "_build_bridge_solids"]
		# the head of _from_raw (bounds, terrain ...) runs with the first step via a copy of _from_raw minus the steps
		m.name = m.raw.get("name", m.key)
		var b: Array = m.raw.bounds
		m.bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
		var e: Array = m.raw.extent
		m.extent = Rect2(e[0], e[1], e[2] - e[0], e[3] - e[1])
		m.boundary = TownMap._flat(m.raw.get("boundary", []))
		m.play = TownMap._flat(m.raw.get("play", []))
		m.closures = m.raw.get("closures", [])
		var inset := Geometry2D.offset_polygon(m.play, -TownMap.EDGE_INSET)
		m.play_inset = inset[0] if not inset.is_empty() else m.play
		var tr: Dictionary = m.raw.terrain
		m.tx0 = tr.x0
		m.ty0 = tr.y0
		m.tstep = tr.step
		m.tnx = int(tr.nx)
		m.tny = int(tr.ny)
		m.th = PackedFloat32Array(tr.h)
		print("head                ", _ms(t))
		for s in steps:
			t = Time.get_ticks_usec()
			m.call(s)
			print("%-20s%s" % [s, _ms(t)])
		m.areas = m.raw.get("areas", [])
		m.places = m.raw.get("places", [])
		m.spots = m.raw.get("spots", {})
	print("TOTAL               ", _ms(t0))
	var out := OS.get_environment("OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		for n in m._snapshot_vars():
			f.store_line("%s %s" % [n, _md5(var_to_bytes(m.get(n)))])
		f.close()
	quit()

func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
