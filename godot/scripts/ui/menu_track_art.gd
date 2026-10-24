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

var _env_cache := {}
var _map_waters: Array[PackedVector2Array] = []
var _map_rivers: Array[Dictionary] = []
var _map_buildings: Array[PackedVector2Array] = []

func _init() -> void:
	resized.connect(_rebuild_path)
	visibility_changed.connect(_update_processing)

func set_track(value: Track, detailed := false) -> void:
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
	_map_waters.clear()
	_map_rivers.clear()
	_map_buildings.clear()
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
			var env_data: Dictionary = {}
			if _env_cache.has(key):
				env_data = _env_cache[key]
			else:
				var env_path := "res://data/tracks/%s_env.json" % key
				if FileAccess.file_exists(env_path):
					var parsed = JSON.parse_string(FileAccess.get_file_as_string(env_path))
					if typeof(parsed) == TYPE_DICTIONARY:
						env_data = parsed
				_env_cache[key] = env_data

			if not env_data.is_empty():
				var bounds_rect := Rect2(-margin.x * 2.0, -margin.y * 2.0, size.x + margin.x * 4.0, size.y + margin.y * 4.0)
				for w in env_data.get("water", []):
					var pts := PackedVector2Array()
					for k in range(0, w.size() - 1, 2):
						pts.append(origin + Vector2((w[k] - min_x) * scale_x, (w[k + 1] - min_y) * scale_y))
					if pts.size() >= 3:
						_map_waters.append(pts)

				for r in env_data.get("rivers", []):
					if r.size() >= 5:
						var r_width: float = maxf(float(r[0]) * scale_x, 2.0)
						var r_pts := PackedVector2Array()
						for k in range(1, r.size() - 1, 2):
							r_pts.append(origin + Vector2((r[k] - min_x) * scale_x, (r[k + 1] - min_y) * scale_y))
						if r_pts.size() >= 2:
							_map_rivers.append({"width": r_width, "pts": r_pts})

				for b in env_data.get("buildings", []):
					var b_pts := PackedVector2Array()
					var any_in := false
					for k in range(3, b.size() - 1, 2):
						var p := origin + Vector2((b[k] - min_x) * scale_x, (b[k + 1] - min_y) * scale_y)
						b_pts.append(p)
						if bounds_rect.has_point(p):
							any_in = true
					if b_pts.size() >= 3 and any_in:
						_map_buildings.append(b_pts)

	_ensure_marker()
	_marker.visible = not map_mode and _path.size() >= 2
	if _marker.visible:
		_marker.position = _path[int(marker_phase * (_path.size() - 1)) % (_path.size() - 1)]
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
		for w in _map_waters:
			if w.size() >= 3:
				draw_colored_polygon(w, water_color)
				var closed_w := w.duplicate()
				closed_w.append(closed_w[0])
				draw_polyline(closed_w, shore_color, 1.2, true)
		for r in _map_rivers:
			var pts: PackedVector2Array = r.pts
			if pts.size() >= 2:
				draw_polyline(pts, river_color, float(r.width), true)

		var b_fill := Color(0.60, 0.62, 0.68, 0.16)
		var b_stroke := Color(0.70, 0.72, 0.80, 0.30)
		for b in _map_buildings:
			if b.size() >= 3:
				draw_colored_polygon(b, b_fill)
				var closed_b := b.duplicate()
				closed_b.append(closed_b[0])
				draw_polyline(closed_b, b_stroke, 1.0, true)

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
