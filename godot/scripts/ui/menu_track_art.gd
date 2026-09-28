## Lightweight track outline used by the menu's carousel backdrop and information page.
extends Control

var track: Track
var map_mode := false
var marker_phase := 0.0

func set_track(value: Track, detailed := false) -> void:
	track = value
	map_mode = detailed
	queue_redraw()

func _process(delta: float) -> void:
	if not map_mode:
		marker_phase = fmod(marker_phase + delta * 0.035, 1.0)
		queue_redraw()

func _draw() -> void:
	if not track or track.n < 2 or size.x < 2.0 or size.y < 2.0:
		return

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
	var path := PackedVector2Array()
	for i in range(0, track.n, stride):
		path.append(origin + Vector2((track.X[i] - min_x) * scale_x, (track.Y[i] - min_y) * scale_y))
	path.append(path[0])

	if map_mode:
		draw_polyline(path, Color(CmrStyle.CYAN, 0.25), 14.0, true)
		draw_polyline(path, Color("#e8f2ff"), 5.0, true)
		draw_polyline(path, CmrStyle.CYAN, 1.8, true)
		var start := path[0]
		draw_circle(start, 8.0, CmrStyle.LIME)
	else:
		draw_polyline(path, Color(CmrStyle.CYAN, 0.10), 9.0, true)
		draw_polyline(path, Color(0.84, 0.92, 1.0, 0.30), 1.7, true)
		var marker_index := int(marker_phase * track.n) % track.n
		var marker := origin + Vector2((track.X[marker_index] - min_x) * scale_x, (track.Y[marker_index] - min_y) * scale_y)
		draw_circle(marker, 9.0, Color(CmrStyle.LIME, 0.25))
		draw_circle(marker, 4.2, CmrStyle.LIME)
