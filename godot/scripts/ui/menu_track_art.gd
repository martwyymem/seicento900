## Lightweight track outline used by the menu's carousel backdrop and information page.
## The outline is built and drawn only when the track or the size changes; the moving marker is a child
## node that is repositioned each frame, so an idle menu costs almost nothing.
extends Control

const MARKER_SPEED := 0.035 ## laps of the outline per second

var track: Track
var map_mode := false
var marker_phase := 0.0
var _path := PackedVector2Array()
var _marker: Control

## Every circuit's map surroundings (water, rivers, buildings from <key>_env.json) in track metres, prepared once
## (parsed, triangulated, outlines gathered) and shared by every map. Re-scaling them for a new circuit or size is
## then a transform, and the fills draw as two meshes instead of thousands of polygons. prepare_env() is pure, so
## the circuit prefetcher (game.gd) runs it on a worker thread and hands the result over with store_env().
static var _envs := {}

var _built := [] ## [track, map_mode, size, env ready] the outline was last built for: the same again rebuilds nothing
var rebuilds := 0 ## how many times the outline was built (tests)
## false: a circuit whose surroundings are not prepared yet is drawn without them for now (the owner prepares them
## off the main thread, then sets the track again); true prepares them here, on the main thread.
var env_on_demand := true

func _env_ready(value: Track) -> bool:
	return value != null and value.cfg != null and _envs.has(value.cfg.key)
var _map_env: Dictionary = {}
var _map_xf := Transform2D.IDENTITY ## track metres → this control, in map mode
var _map_shores := PackedVector2Array() ## segment pairs for draw_multiline
var _map_edges := PackedVector2Array()
var _map_rivers: Array[Dictionary] = []

static func has_env(key: String) -> bool:
	return _envs.has(key)

## Main thread only.
static func store_env(key: String, env: Dictionary) -> void:
	if not _envs.has(key):
		_envs[key] = env

## Pure (reads one file, touches nothing shared): safe on a worker thread. {} when the circuit has no surroundings.
static func prepare_env(key: String) -> Dictionary:
	var env_path := "res://data/tracks/%s_env.json" % key
	if not FileAccess.file_exists(env_path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(env_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var water_v := PackedVector2Array()
	var water_i := PackedInt32Array()
	var shores := PackedVector2Array()
	for w in parsed.get("water", []):
		var pts := PackedVector2Array()
		for k in range(0, w.size() - 1, 2):
			pts.append(Vector2(w[k], w[k + 1]))
		if pts.size() >= 3:
			_append_outline(shores, pts)
			_append_fill(water_v, water_i, pts)
	var rivers: Array[Dictionary] = []
	for r in parsed.get("rivers", []):
		if r.size() >= 5:
			var r_pts := PackedVector2Array()
			for k in range(1, r.size() - 1, 2):
				r_pts.append(Vector2(r[k], r[k + 1]))
			if r_pts.size() >= 2:
				rivers.append({"width": float(r[0]), "pts": r_pts})
	var bld_v := PackedVector2Array()
	var bld_i := PackedInt32Array()
	var edges := PackedVector2Array()
	for b in parsed.get("buildings", []):
		var b_pts := PackedVector2Array()
		for k in range(3, b.size() - 1, 2):
			b_pts.append(Vector2(b[k], b[k + 1]))
		if b_pts.size() >= 3 and _append_fill(bld_v, bld_i, b_pts):
			_append_outline(edges, b_pts)
	return {"water_v": water_v, "water_i": water_i, "shores": shores, "rivers": rivers,
		"bld_v": bld_v, "bld_i": bld_i, "edges": edges}

## Triangulates a polygon onto a shared vertex/index list; false (and nothing added) if it does not triangulate.
static func _append_fill(verts: PackedVector2Array, indices: PackedInt32Array, pts: PackedVector2Array) -> bool:
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return false
	var base := verts.size()
	verts.append_array(pts)
	for t in tris:
		indices.append(base + t)
	return true

## A closed outline as segment pairs.
static func _append_outline(segments: PackedVector2Array, pts: PackedVector2Array) -> void:
	for k in pts.size():
		segments.append(pts[k])
		segments.append(pts[(k + 1) % pts.size()])

## The env's fill mesh ("water" or "bld"), made on first draw (main thread) and kept with the env.
static func _env_mesh(env: Dictionary, kind: String) -> ArrayMesh:
	var mesh_key := kind + "_mesh"
	if not env.has(mesh_key):
		var mesh: ArrayMesh = null
		var idx: PackedInt32Array = env[kind + "_i"]
		if not idx.is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = env[kind + "_v"]
			arrays[Mesh.ARRAY_INDEX] = idx
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		env[mesh_key] = mesh
	return env[mesh_key]

func _init() -> void:
	resized.connect(_rebuild_path)
	visibility_changed.connect(_update_processing)

func set_track(value: Track, detailed := false) -> void:
	if _built == [value, detailed, size, detailed and _env_ready(value)]:
		_update_processing()
		return # same circuit, mode, size and surroundings: the outline and map are already built
	track = value
	map_mode = detailed
	clip_contents = detailed # the map's water, rivers and buildings reach past the frame: keep them inside it
	_rebuild_path()
	_update_processing()

func _update_processing() -> void:
	# nothing moves in the map, or while the page is hidden
	set_process(not map_mode and is_visible_in_tree())

func _process(delta: float) -> void:
	if _path.size() < 2:
		return
	marker_phase = fmod(marker_phase + delta * MARKER_SPEED, 1.0)
	_marker.position = _path[int(marker_phase * (_path.size() - 1)) % (_path.size() - 1)]

func _rebuild_path() -> void:
	_path = PackedVector2Array()
	rebuilds += 1
	_map_env = {}
	_map_shores = PackedVector2Array()
	_map_edges = PackedVector2Array()
	_map_rivers.clear()
	if track and track.n >= 2 and size.x >= 2.0 and size.y >= 2.0:
		var min_x: float = track.bounds[0]
		var min_y: float = track.bounds[1]
		var span_x := maxf(track.bounds[2] - min_x, 1.0)
		var span_y := maxf(track.bounds[3] - min_y, 1.0)
		var margin := size * 0.09
		var available := size - margin * 2.0
		var scale_x: float
		var scale_y: float
		if map_mode:
			scale_x = minf(available.x / span_x, available.y / span_y)
			scale_y = scale_x
		else:
			# The CMR title screen stretches its route art across the centre of the screen.
			scale_x = available.x / span_x * 1.06
			scale_y = available.y / span_y * 0.9
		var rendered := Vector2(span_x * scale_x, span_y * scale_y)
		var origin := (size - rendered) * 0.5
		var stride := maxi(1, int(track.n / 650))
		for i in range(0, track.n, stride):
			_path.append(origin + Vector2((track.X[i] - min_x) * scale_x, (track.Y[i] - min_y) * scale_y))
		_path.append(_path[0])

		if map_mode and track.cfg:
			var key: String = track.cfg.key
			if not _envs.has(key) and env_on_demand:
				store_env(key, prepare_env(key)) # not prefetched yet: prepare it here, once
			_map_env = _envs.get(key, {})
			if not _map_env.is_empty():
				# map mode scales both axes alike, so one transform takes the prepared metres onto the frame
				_map_xf = Transform2D(0.0, Vector2(scale_x, scale_y), 0.0, origin - Vector2(min_x * scale_x, min_y * scale_y))
				_map_shores = _map_xf * (_map_env.shores as PackedVector2Array)
				_map_edges = _map_xf * (_map_env.edges as PackedVector2Array)
				for r in _map_env.rivers:
					_map_rivers.append({"width": maxf(float(r.width) * scale_x, 2.0), "pts": _map_xf * (r.pts as PackedVector2Array)})

	_ensure_marker()
	_marker.visible = not map_mode and _path.size() >= 2
	if _marker.visible:
		_marker.position = _path[int(marker_phase * (_path.size() - 1)) % (_path.size() - 1)]
	_built = [track, map_mode, size, map_mode and _env_ready(track)]
	queue_redraw()

func _ensure_marker() -> void:
	if _marker:
		return
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(func() -> void:
		_marker.draw_circle(Vector2.ZERO, 9.0, Color(CmrStyle.ORANGE, 0.3))
		_marker.draw_circle(Vector2.ZERO, 4.2, CmrStyle.ORANGE))
	add_child(_marker)

func _draw() -> void:
	if _path.size() < 2:
		return
	if map_mode:
		var water_color := Color(0.20, 0.40, 0.65, 0.42)
		var shore_color := Color(0.32, 0.58, 0.85, 0.70)
		var river_color := Color(0.24, 0.45, 0.70, 0.55)
		var b_fill := Color(0.60, 0.62, 0.68, 0.16)
		var b_stroke := Color(0.70, 0.72, 0.80, 0.30)
		if not _map_env.is_empty():
			var water_mesh := _env_mesh(_map_env, "water")
			if water_mesh:
				draw_mesh(water_mesh, null, _map_xf, water_color)
			if _map_shores.size() >= 2:
				draw_multiline(_map_shores, shore_color, 1.2, true)
			for r in _map_rivers:
				draw_polyline(r.pts, river_color, float(r.width), true)
			var bld_mesh := _env_mesh(_map_env, "bld")
			if bld_mesh:
				draw_mesh(bld_mesh, null, _map_xf, b_fill)
			if _map_edges.size() >= 2:
				draw_multiline(_map_edges, b_stroke, 1.0, true)

		# Road outline with shadow and crisp boundary
		draw_polyline(_path, Color(0.0, 0.0, 0.0, 0.45), 6.5, true)
		draw_polyline(_path, Color(0.12, 0.14, 0.18, 0.85), 4.2, true)
		draw_polyline(_path, Color(CmrStyle.TEXT, 0.95), 2.2, true)

		# Distinct start / finish marker
		draw_circle(_path[0], 7.5, Color(CmrStyle.ORANGE, 0.35))
		draw_circle(_path[0], 4.5, CmrStyle.ORANGE)
		draw_circle(_path[0], 2.0, Color.WHITE)
	else:
		draw_polyline(_path, Color(CmrStyle.TEXT, 0.12), 7.0, true)
		draw_polyline(_path, Color(CmrStyle.TEXT, 0.7), 1.6, true)
