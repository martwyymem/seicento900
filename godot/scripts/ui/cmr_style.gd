## Shared look for the front end and HUD, after Colin McRae Rally 2.0: deep rally-blue backdrops, slanted
## translucent white/ice-blue bars with dark ink, a lime-yellow highlight (the pace-note colour), cyan
## rev/progress accents and bold italic type. Everything is sized for the 1600×900 design canvas; the
## project's canvas_items stretch scales it to the window.
class_name CmrStyle
extends RefCounted

const INK := Color("#0c1a2c") ## text on light bars
const INK_SOFT := Color("#33506e")
const TEXT := Color("#ffffff") ## text on the blue backdrop
const MUTED := Color("#9cc0e4")
const LIME := Color("#d8f028") ## selection / pace-note yellow
const LIME_DARK := Color("#9fb80e")
const CYAN := Color("#3fe0ea")
const GREEN := Color("#6ee04a")
const RED := Color("#ff4a3a")
const AMBER := Color("#ffb020")
const PURPLE := Color("#c48bff")
const BAR := Color(0.88, 0.94, 1.0, 0.82) ## the translucent light bar
const BAR_HOVER := Color(0.97, 0.99, 1.0, 0.95)
const BAR_DIM := Color(0.72, 0.82, 0.93, 0.55)
const NAVY := Color(0.03, 0.08, 0.17, 0.78) ## dark panels over the backdrop
const NAVY_EDGE := Color(0.55, 0.78, 1.0, 0.35)
const BACK_TOP := Color("#06122a")
const BACK_MID := Color("#123a6b")
const BACK_LOW := Color("#2a6aa6")
const SKEW := 0.22 ## slant of bars, as StyleBoxFlat.skew.x

static var _fonts := {}

## Bold italic face used everywhere (system sans, falling back to the engine font).
static func font(bold := true, italic := true) -> Font:
	var key := "%s%s" % [bold, italic]
	if _fonts.has(key):
		return _fonts[key]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial", "Helvetica Neue", "Helvetica", "Liberation Sans", "DejaVu Sans", "sans-serif"])
	f.font_weight = 800 if bold else 500
	f.font_italic = italic
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.fallbacks = [ThemeDB.fallback_font]
	_fonts[key] = f
	return f

## Digits for timers: a monospaced face so the clock doesn't jitter.
static func digits() -> Font:
	if _fonts.has("digits"):
		return _fonts["digits"]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	f.font_weight = 700
	f.fallbacks = [ThemeDB.fallback_font]
	var v := FontVariation.new()
	v.base_font = f
	v.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO) # lean like the CMR clock
	_fonts["digits"] = v
	return v

static func bar(color := BAR, slant := true, margin_h := 16.0, margin_v := 6.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	if slant:
		s.skew = Vector2(SKEW, 0)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s

static func panel(color := NAVY, edge := NAVY_EDGE, margin := 20.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = edge
	s.border_width_top = 2
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.set_content_margin_all(margin)
	return s

## The theme for the whole front end: light slanted bars with dark ink for controls, white type on blue.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	var normal := bar()
	var hover := bar(BAR_HOVER)
	var lit := bar(LIME)
	var off := bar(BAR_DIM)
	for type in ["Button", "OptionButton", "ColorPickerButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, lit)
		t.set_stylebox("hover_pressed", type, lit)
		t.set_stylebox("focus", type, _focus_box())
		t.set_stylebox("disabled", type, off)
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_focus_color", type, INK)
		t.set_color("font_disabled_color", type, INK_SOFT)
		t.set_color("icon_normal_color", type, INK)
		t.set_color("icon_hover_color", type, INK)
		t.set_color("icon_pressed_color", type, INK)
		t.set_color("icon_focus_color", type, INK)
	t.set_font_size("font_size", "Button", 16)
	t.set_font_size("font_size", "OptionButton", 17)
	t.set_icon("arrow", "OptionButton", _arrow_icon())
	t.set_constant("arrow_margin", "OptionButton", 12)

	# toggles read as text on the backdrop with a lime switch
	for type in ["CheckButton", "CheckBox"]:
		var clear := StyleBoxEmpty.new()
		clear.content_margin_left = 4
		clear.content_margin_right = 4
		clear.content_margin_top = 4
		clear.content_margin_bottom = 4
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, type, clear)
		t.set_stylebox("focus", type, _focus_box())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(c, type, TEXT)
		t.set_font_size("font_size", type, 16)
	t.set_icon("checked", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false))

	var field := bar(BAR, false, 10, 6)
	var field_focus := bar(BAR_HOVER, false, 10, 6)
	field_focus.border_color = LIME_DARK
	field_focus.border_width_bottom = 3
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_SOFT)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(LIME, 0.6))
	t.set_font_size("font_size", "LineEdit", 17)
	t.set_icon("updown", "SpinBox", _updown_icon())

	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())

	var popup := panel(Color(0.04, 0.1, 0.2, 0.97), CYAN, 4)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", bar(LIME, false, 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	t.set_font_size("font_size", "PopupMenu", 17)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "AcceptDialog", popup)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(CYAN, 0.8)
	var grabber_hi := StyleBoxFlat.new()
	grabber_hi.bg_color = LIME
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.08)
	track.content_margin_left = 5
	track.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber_hi)
	return t

static func _focus_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.skew = Vector2(SKEW, 0)
	s.border_color = LIME
	s.set_border_width_all(2)
	s.expand_margin_left = 3
	s.expand_margin_right = 3
	s.expand_margin_top = 3
	s.expand_margin_bottom = 3
	return s

static func _image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

## A small solid down-pointing triangle for option buttons.
static func _arrow_icon() -> Texture2D:
	var img := _image(14, 10)
	for y in 8:
		for x in range(y, 14 - y):
			img.set_pixel(x, y + 1, INK)
	return ImageTexture.create_from_image(img)

static func _updown_icon() -> Texture2D:
	var img := _image(14, 22)
	for y in 7:
		for x in range(6 - y, 8 + y):
			img.set_pixel(x, y + 2, LIME)
			img.set_pixel(x, 19 - y, LIME)
	return ImageTexture.create_from_image(img)

## Slanted two-segment switch: lime block on the right when on, grey on the left when off.
static func _switch_icon(on: bool) -> Texture2D:
	var w := 40
	var h := 18
	var img := _image(w, h)
	for y in h:
		var shift := int((h - 1 - y) * 0.3)
		for x in range(shift, w - 5 + shift):
			var right := x - shift >= (w - 5) / 2
			var c := Color(1, 1, 1, 0.22)
			if right and on:
				c = LIME
			elif not right and not on:
				c = Color(0.75, 0.82, 0.9, 0.9)
			if y == 0 or y == h - 1:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
