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

func _init() -> void:
	resized.connect(_rebuild_path)
	visibility_changed.connect(_update_processing)

func set_track(value: Track, detailed := false) -> void:
	track = value
	map_mode = detailed
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
		draw_polyline(_path, Color(CmrStyle.TEXT, 0.9), 3.0, true)
		draw_circle(_path[0], 7.0, CmrStyle.ORANGE)
	else:
		draw_polyline(_path, Color(CmrStyle.TEXT, 0.12), 7.0, true)
		draw_polyline(_path, Color(CmrStyle.TEXT, 0.7), 1.6, true)
