## Compact CMR-style condition marks for the repair parts list.
extends Control

var state := "none":
	set(value):
		state = value
		queue_redraw()

var INK: Color:
	get: return CmrStyle.MUTED
const PAPER := Color(0.87, 0.83, 0.92, 0.55)
var WARNING: Color:
	get: return CmrStyle.ORANGE

func _ready() -> void:
	custom_minimum_size = Vector2(38, 34)

func _draw() -> void:
	if state == "none":
		return
	if state == "warning":
		var triangle := PackedVector2Array([Vector2(2, 29), Vector2(16, 4), Vector2(30, 29)])
		draw_colored_polygon(triangle, WARNING)
		draw_polyline(triangle + PackedVector2Array([triangle[0]]), INK, 2.0, true)
		draw_line(Vector2(16, 11), Vector2(16, 20), INK, 2.0, true)
		draw_circle(Vector2(16, 24), 1.4, INK)
		draw_rect(Rect2(23, 7, 13, 22), PAPER, false, 2.0)
		draw_line(Vector2(26, 11), Vector2(33, 25), INK, 2.3, true)
		draw_line(Vector2(33, 11), Vector2(26, 25), INK, 2.3, true)
		return
	var box := Rect2(7, 3, 27, 27)
	draw_rect(box, PAPER, false, 2.0)
	if state == "ok":
		draw_polyline(PackedVector2Array([Vector2(11, 16), Vector2(17, 22), Vector2(30, 8)]), CmrStyle.ORANGE_SOFT, 3.0, true)
	elif state == "bad":
		draw_line(Vector2(13, 9), Vector2(29, 25), INK, 3.0, true)
		draw_line(Vector2(29, 9), Vector2(13, 25), INK, 3.0, true)
