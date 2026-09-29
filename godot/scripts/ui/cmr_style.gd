## Shared look for the front end and HUD: a straight copy of Colin McRae Rally 2.0's interface recoloured
## in purples and oranges. Front-end pages are flat tints with thin upright type, pale flat fields and
## text tabs split by hairlines; the orange takes the place of CMR's yellow selection and pace-note
## colour, and violet the place of its cyan rev band. Everything is sized for the 1600×900 design canvas;
## the project's canvas_items stretch scales it to the window.
class_name CmrStyle
extends RefCounted

const INK := Color("#2a2036") ## text on pale fields and bars
const INK_SOFT := Color("#584a6e")
const TEXT := Color("#f8f3fc") ## text on the purple tints
const MUTED := Color("#d9cce9") ## secondary text on the tints
const DIM := Color(0.97, 0.94, 1.0, 0.5) ## unselected menu words
const ORANGE := Color("#ff8a1e") ## selection / pace note (CMR's yellow)
const ORANGE_SOFT := Color("#ffc285")
const ORANGE_DEEP := Color("#c75b08")
const VIOLET := Color("#b98cff") ## rev band and accents (CMR's cyan)
const PLUM := Color("#6c3fa8")
const GREEN := Color("#9fe06a") ## kept only for good/bad readings
const RED := Color("#ff4f5e")
const AMBER := Color("#ffb020")
const PURPLE := Color("#d0a2ff")
const FIELD := Color("#ddd3ea") ## pale flat field, like CMR's light-grey boxes
const FIELD_HOVER := Color("#ece6f4")
const FIELD_EDGE := Color("#7c6c97")
const FIELD_DIM := Color(0.87, 0.83, 0.92, 0.55)
const PAPER := Color("#f6e3cf") ## the pale sketch panel on the repair page (CMR's cream)
const PANEL := Color(0.2, 0.15, 0.29, 0.94) ## pause and results sheets
const PANEL_EDGE := Color(0.85, 0.78, 0.95, 0.5)
## page tints: each front-end page is one flat colour, as in CMR
const TINT_HOME := Color("#5d4d7c")
const TINT_SETUP := Color("#5a5173")
const TINT_INFO := Color("#524a6d")
const TINT_REPAIR := Color("#5e5476")
const TINT_OPTIONS := Color("#554c70")

static var _fonts := {}

const FACE := preload("res://fonts/NunitoSans.ttf") ## variable humanist sans (OFL), close to CMR's thin type

## The thin upright sans CMR uses everywhere, at any weight from 200 (menu words) to 800.
static func font(weight := 400) -> Font:
	var key := "w%d" % weight
	if _fonts.has(key):
		return _fonts[key]
	var f := FontVariation.new()
	f.base_font = FACE
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	f.fallbacks = [ThemeDB.fallback_font]
	_fonts[key] = f
	return f

## Digits for timers: a monospaced face so the clock doesn't jitter.
static func digits() -> Font:
	if _fonts.has("digits"):
		return _fonts["digits"]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
	f.font_weight = 500
	f.fallbacks = [ThemeDB.fallback_font]
	_fonts["digits"] = f
	return f

## A flat box: the one building block of CMR's menus.
static func box(color := FIELD, edge := Color.TRANSPARENT, margin_h := 10.0, margin_v := 6.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	if edge.a > 0.0:
		s.border_color = edge
		s.set_border_width_all(1)
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s

static func panel(color := PANEL, edge := PANEL_EDGE, margin := 22.0) -> StyleBoxFlat:
	var s := box(color, edge, margin, margin)
	return s

## The theme for the whole front end.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17

	t.set_color("font_color", "Label", TEXT)

	var normal := box(FIELD, FIELD_EDGE)
	var hover := box(FIELD_HOVER, FIELD_EDGE)
	var lit := box(ORANGE, ORANGE_DEEP)
	var off := box(FIELD_DIM)
	for type in ["Button", "OptionButton", "ColorPickerButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, lit)
		t.set_stylebox("hover_pressed", type, lit)
		t.set_stylebox("focus", type, _focus_box())
		t.set_stylebox("disabled", type, off)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color",
				"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			t.set_color(c, type, INK)
		t.set_color("font_disabled_color", type, INK_SOFT)
	t.set_font_size("font_size", "Button", 16)
	t.set_font_size("font_size", "OptionButton", 17)
	t.set_icon("arrow", "OptionButton", _arrow_icon())
	t.set_constant("arrow_margin", "OptionButton", 10)

	# toggles read as plain text on the tint with a small orange switch
	for type in ["CheckButton", "CheckBox"]:
		var clear := StyleBoxEmpty.new()
		clear.set_content_margin_all(4)
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

	var field_focus := box(FIELD_HOVER, ORANGE)
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", normal)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_SOFT)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(ORANGE, 0.5))
	t.set_font_size("font_size", "LineEdit", 17)
	t.set_icon("updown", "SpinBox", _updown_icon())

	# pages sit straight on the tint; only pause and results get a sheet (see panel())
	var bare := StyleBoxEmpty.new()
	bare.set_content_margin_all(20)
	t.set_stylebox("panel", "PanelContainer", bare)
	t.set_stylebox("panel", "Panel", bare)

	var popup := panel(Color("#3a2e52"), FIELD_EDGE, 4)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(ORANGE, Color.TRANSPARENT, 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	t.set_font_size("font_size", "PopupMenu", 17)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "AcceptDialog", popup)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(TEXT, 0.7)
	var grabber_hi := StyleBoxFlat.new()
	grabber_hi.bg_color = ORANGE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.1)
	track.content_margin_left = 3
	track.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber_hi)
	return t

static func _focus_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = ORANGE
	s.set_border_width_all(2)
	s.set_expand_margin_all(2)
	return s

static func _image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

## A small down-pointing chevron for option buttons.
static func _arrow_icon() -> Texture2D:
	var img := _image(12, 8)
	for y in 6:
		for x in range(y, 12 - y):
			img.set_pixel(x, y + 1, INK_SOFT)
	return ImageTexture.create_from_image(img)

static func _updown_icon() -> Texture2D:
	var img := _image(14, 22)
	for y in 7:
		for x in range(6 - y, 8 + y):
			img.set_pixel(x, y + 2, ORANGE_SOFT)
			img.set_pixel(x, 19 - y, ORANGE_SOFT)
	return ImageTexture.create_from_image(img)

## Flat two-cell switch: orange cell on the right when on, pale cell on the left when off.
static func _switch_icon(on: bool) -> Texture2D:
	var w := 34
	var h := 14
	var img := _image(w, h)
	for y in h:
		for x in w:
			var right := x >= w / 2
			var c := Color(1, 1, 1, 0.2)
			if right and on:
				c = ORANGE
			elif not right and not on:
				c = FIELD
			if y == 0 or y == h - 1 or x == 0 or x == w - 1:
				c = Color(1, 1, 1, 0.55)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
