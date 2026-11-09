extends SceneTree
func _initialize() -> void:
	var m := TownMap.new()
	var t := Time.get_ticks_usec()
	var lap := func(label: String):
		var n := Time.get_ticks_usec()
		print("%-14s %6.0f ms" % [label, (n - t) / 1000.0])
		t = n
	m.key = "brzeszcze"
	m.raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/brzeszcze.json"))
	lap.call("parse")
	var raw := m.raw
	var b: Array = raw.bounds
	m.bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	var e: Array = raw.extent
	m.extent = Rect2(e[0], e[1], e[2] - e[0], e[3] - e[1])
	m.boundary = TownMap._flat(raw.get("boundary", []))
	m.play = TownMap._flat(raw.get("play", []))
	m.closures = raw.get("closures", [])
	var inset := Geometry2D.offset_polygon(m.play, -TownMap.EDGE_INSET)
	m.play_inset = inset[0] if not inset.is_empty() else m.play
	var tt: Dictionary = raw.terrain
	m.tx0 = tt.x0; m.ty0 = tt.y0; m.tstep = tt.step; m.tnx = int(tt.nx); m.tny = int(tt.ny)
	m.th = PackedFloat32Array(tt.h)
	lap.call("head")
	m._load_roads(); lap.call("roads")
	m._load_buildings(); lap.call("buildings")
	m._build_pavements(); lap.call("pavements")
	m._load_obstacles(); lap.call("obstacles")
	m._load_rails(); lap.call("rails")
	m._load_tunnels(); lap.call("tunnels")
	m._load_rail_banks(); lap.call("rail banks")
	m._build_bridge_solids(); lap.call("bridge")
	quit()
