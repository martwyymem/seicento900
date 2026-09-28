## Front-end backdrop in the CMR 2.0 manner: a deep blue gradient with slow diagonal light bands and a
## lime rule under the title strip.
extends Control

var phase := 0.0
## Height of the dark title band across the top (0 hides it).
var band := 104.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if is_visible_in_tree():
		phase = fmod(phase + delta * 0.02, 1.0)
		queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var colors := PackedColorArray([CmrStyle.BACK_TOP, CmrStyle.BACK_TOP, CmrStyle.BACK_MID, CmrStyle.BACK_LOW])
	var stops := [0.0, 0.12, 0.62, 1.0]
	for i in stops.size() - 1:
		var y0: float = stops[i] * h
		var y1: float = stops[i + 1] * h
		draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
			PackedColorArray([colors[i], colors[i], colors[i + 1], colors[i + 1]]))
	# diagonal light bands drifting across
	for k in 5:
		var x := fmod(phase + k * 0.23, 1.2) * (w + h) - h
		var bw := 60.0 + k * 34.0
		var a := 0.035 + 0.012 * (k % 3)
		draw_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + bw, h), Vector2(x + bw + h * 0.6, 0), Vector2(x + h * 0.6, 0)]),
			PackedColorArray([Color(1, 1, 1, a), Color(1, 1, 1, a), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	# fine horizontal scanlines, very faint
	var y := 0.0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.05), 1.0)
		y += 4.0
	if band > 0.0:
		draw_rect(Rect2(0, 0, w, band), Color(0.01, 0.04, 0.1, 0.72))
		draw_rect(Rect2(0, band, w, 3), CmrStyle.LIME)
		draw_rect(Rect2(0, band + 3, w, 1), Color(0, 0, 0, 0.5))
