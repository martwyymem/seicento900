## Small outlined weather glyphs for the information page.
extends Control

var condition := "cloud":
	set(value):
		condition = value
		queue_redraw()

const INK := Color("#303332")
const CLOUD := Color("#f4f3ef")
const SUN := Color("#efd44f")

func _ready() -> void:
	custom_minimum_size = Vector2(48, 52)

func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.43)
	match condition:
		"sun":
			_draw_sun(center, 10.0)
		"partly":
			_draw_sun(center + Vector2(-7.0, -5.0), 8.0)
			_draw_cloud(Rect2(4.0, 16.0, size.x - 7.0, size.y * 0.55))
		"cloud":
			_draw_cloud(Rect2(3.0, 12.0, size.x - 6.0, size.y * 0.56))
		"drizzle":
			_draw_cloud(Rect2(3.0, 8.0, size.x - 6.0, size.y * 0.51))
			_draw_rain(false)
		"rain":
			_draw_cloud(Rect2(3.0, 5.0, size.x - 6.0, size.y * 0.50))
			_draw_rain(true)
		"storm":
			_draw_cloud(Rect2(3.0, 4.0, size.x - 6.0, size.y * 0.49), Color("#aab7c1"))
			var bolt := PackedVector2Array([Vector2(27, 29), Vector2(20, 39), Vector2(25, 39), Vector2(21, 49), Vector2(33, 35), Vector2(27, 35)])
			draw_colored_polygon(bolt, SUN)
			draw_polyline(bolt + PackedVector2Array([bolt[0]]), INK, 1.5, true)

func _draw_sun(center: Vector2, radius: float) -> void:
	for i in 8:
		var direction := Vector2.RIGHT.rotated(TAU * float(i) / 8.0)
		draw_line(center + direction * (radius + 3.0), center + direction * (radius + 8.0), INK, 2.0, true)
	draw_circle(center, radius, SUN)
	draw_arc(center, radius, 0.0, TAU, 32, INK, 2.0, true)

func _draw_cloud(rect: Rect2, fill: Color = CLOUD) -> void:
	var p := rect.position
	var s := rect.size
	var outline := PackedVector2Array([
		p + Vector2(s.x * 0.08, s.y * 0.75),
		p + Vector2(s.x * 0.05, s.y * 0.62),
		p + Vector2(s.x * 0.08, s.y * 0.49),
		p + Vector2(s.x * 0.16, s.y * 0.42),
		p + Vector2(s.x * 0.28, s.y * 0.42),
		p + Vector2(s.x * 0.31, s.y * 0.26),
		p + Vector2(s.x * 0.41, s.y * 0.15),
		p + Vector2(s.x * 0.54, s.y * 0.14),
		p + Vector2(s.x * 0.65, s.y * 0.22),
		p + Vector2(s.x * 0.71, s.y * 0.39),
		p + Vector2(s.x * 0.81, s.y * 0.36),
		p + Vector2(s.x * 0.92, s.y * 0.43),
		p + Vector2(s.x * 0.96, s.y * 0.58),
		p + Vector2(s.x * 0.93, s.y * 0.71),
		p + Vector2(s.x * 0.83, s.y * 0.77),
	])
	draw_colored_polygon(outline, fill)
	draw_polyline(outline + PackedVector2Array([outline[0]]), INK, 2.0, true)

func _draw_rain(long_drops: bool) -> void:
	for x in [12.0, 24.0, 36.0]:
		var y := 38.0 if long_drops else 35.0
		var length := 10.0 if long_drops else 5.0
		draw_line(Vector2(x + 2.0, y), Vector2(x - 2.0, y + length), Color("#628da8"), 2.0, true)
