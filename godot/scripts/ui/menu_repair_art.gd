## Technical line drawing used for the selected repair component.
extends Control

const INK := CmrStyle.INK

func _draw() -> void:
	var center := Vector2(size.x * 0.39, size.y * 0.63)
	var radius := minf(size.x * 0.22, size.y * 0.36)
	var body := PackedVector2Array([
		Vector2(size.x * 0.23, size.y * 0.34),
		Vector2(size.x * 0.42, size.y * 0.10),
		Vector2(size.x * 0.57, size.y * 0.23),
		Vector2(size.x * 0.48, size.y * 0.39),
		Vector2(size.x * 0.62, size.y * 0.48),
		Vector2(size.x * 0.66, size.y * 0.71),
		Vector2(size.x * 0.56, size.y * 0.89),
		Vector2(size.x * 0.28, size.y * 0.91),
		Vector2(size.x * 0.13, size.y * 0.73),
	])
	draw_colored_polygon(body, Color("#ead3bf"))
	draw_polyline(body + PackedVector2Array([body[0]]), INK, 3.0, true)
	for i in 4:
		draw_arc(center, radius * (0.86 - float(i) * 0.16), 0.0, TAU, 48, INK, 2.2, true)
	draw_circle(center, radius * 0.18, Color("#dcc0aa"))
	draw_arc(center, radius * 0.18, 0.0, TAU, 36, INK, 2.0, true)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var start := center + Vector2.RIGHT.rotated(angle) * radius * 0.2
		var finish := center + Vector2.RIGHT.rotated(angle + 0.32) * radius * 0.64
		draw_line(start, finish, INK, 2.5, true)
	draw_rect(Rect2(size.x * 0.62, size.y * 0.67, size.x * 0.15, size.y * 0.2), Color("#ead3bf"))
	draw_rect(Rect2(size.x * 0.62, size.y * 0.67, size.x * 0.15, size.y * 0.2), INK, false, 3.0)
	draw_line(Vector2(size.x * 0.77, size.y * 0.75), Vector2(size.x * 0.88, size.y * 0.75), INK, 3.0, true)
