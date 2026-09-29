## Compact temperature scale drawn in the original menu's flat graphic style.
extends Control

const STOPS := [
	Color("#9d86d6"),
	Color("#c49ae6"),
	Color("#f2b98a"),
	Color("#ff9433"),
	Color("#e0620e")
]

func _ready() -> void:
	custom_minimum_size.y = 22

func _draw() -> void:
	var segments := 32
	for i in segments:
		var t := (float(i) + 0.5) / float(segments)
		var scaled := t * float(STOPS.size() - 1)
		_draw_segment(i, scaled)
	var font := ThemeDB.fallback_font
	var text := "14°C"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	draw_string(font, Vector2((size.x - text_size.x) * 0.5, 18.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, CmrStyle.INK)

func _draw_segment(index: int, scaled: float) -> void:
	var stop := mini(int(floorf(scaled)), STOPS.size() - 2)
	var color: Color = STOPS[stop].lerp(STOPS[stop + 1], scaled - float(stop))
	var left := size.x * float(index) / 32.0
	var right := size.x * float(index + 1) / 32.0
	draw_rect(Rect2(left, 0.0, right - left + 1.0, size.y), color)
