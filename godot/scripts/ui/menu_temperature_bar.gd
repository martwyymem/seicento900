## Compact temperature scale drawn in the original menu's flat graphic style.
extends Control

## cold to hot in neon street colours (cyan -> violet -> magenta -> laser yellow)
var STOPS: Array:
	get: return [HudLayout.neon_primary().darkened(0.25), HudLayout.neon_primary(), CmrStyle.VIOLET, HudLayout.neon_hot(), HudLayout.neon_boost()]

func _ready() -> void:
	custom_minimum_size.y = 22

func _draw() -> void:
	var segments := 32
	for i in segments:
		var t := (float(i) + 0.5) / float(segments)
		var scaled := t * float(STOPS.size() - 1)
		_draw_segment(i, scaled)
	draw_rect(Rect2(Vector2.ZERO, size), Color(HudLayout.neon_primary(), 0.72), false, 1.5)
	var font := HudLayout.italic_font(800)
	var text := "14°C"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var pos := Vector2((size.x - text_size.x) * 0.5, (size.y + font.get_ascent(16) - font.get_descent(16)) * 0.5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func _draw_segment(index: int, scaled: float) -> void:
	var stops := STOPS
	var stop := mini(int(floorf(scaled)), stops.size() - 2)
	var color: Color = (stops[stop] as Color).lerp(stops[stop + 1], scaled - float(stop))
	var left := size.x * float(index) / 32.0
	var right := size.x * float(index + 1) / 32.0
	draw_rect(Rect2(left, 0.0, right - left + 1.0, size.y), color)
