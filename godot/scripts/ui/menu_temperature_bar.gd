## Compact temperature scale drawn in the original menu's flat graphic style.
extends Control

## cold to hot in the skin's colours (violet to orange in CMR)
var STOPS: Array:
	get: return [CmrStyle.VIOLET.darkened(0.15), CmrStyle.PURPLE, CmrStyle.ORANGE_SOFT, CmrStyle.ORANGE, CmrStyle.ORANGE_DEEP]

func _ready() -> void:
	custom_minimum_size.y = 22

func _draw() -> void:
	var segments := 32
	for i in segments:
		var t := (float(i) + 0.5) / float(segments)
		var scaled := t * float(STOPS.size() - 1)
		_draw_segment(i, scaled)
	var font := CmrStyle.font(600) # the skin's face, not the engine's default
	var text := "14°C"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, (size.y + font.get_ascent(17) - font.get_descent(17)) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, CmrStyle.INK)

func _draw_segment(index: int, scaled: float) -> void:
	var stops := STOPS
	var stop := mini(int(floorf(scaled)), stops.size() - 2)
	var color: Color = (stops[stop] as Color).lerp(stops[stop + 1], scaled - float(stop))
	var left := size.x * float(index) / 32.0
	var right := size.x * float(index + 1) / 32.0
	draw_rect(Rect2(left, 0.0, right - left + 1.0, size.y), color)
