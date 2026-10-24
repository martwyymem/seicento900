## Shared look for the front end and HUD: a straight copy of Colin McRae Rally 2.0's interface recoloured
## in purples and oranges. Front-end pages are flat tints with thin upright type, pale flat fields and
## text tabs split by hairlines; the orange takes the place of CMR's yellow selection and pace-note
## colour, and violet the place of its cyan rev band. Everything is sized for the 1600×900 design canvas;
## the project's canvas_items stretch scales it to the window.
##
## Skins: the palette below is the CMR one; apply_skin() swaps it (plus face, corners, bevel, skew,
## outline) for an homage to the retro graphic style picked in Options / F1 (SKIN_FOR_MODE). The names
## keep their meaning in every skin: TEXT on the tints, INK on FIELD and ORANGE (the selection), FOCUS
## the focus ring, GREEN / RED good and bad. restyle() recolours a built tree live.
class_name CmrStyle
extends RefCounted

static var INK := Color("#2a2036") ## text on pale fields and bars
static var INK_SOFT := Color("#584a6e")
static var TEXT := Color("#f8f3fc") ## text on the purple tints
static var MUTED := Color("#d9cce9") ## secondary text on the tints
static var DIM := Color(0.97, 0.94, 1.0, 0.5) ## unselected menu words
static var ORANGE := Color("#ff8a1e") ## selection / pace note (CMR's yellow)
static var ORANGE_SOFT := Color("#ffc285")
static var ORANGE_DEEP := Color("#c75b08")
static var FOCUS := Color("#fff36b") ## the focus ring on the menus (the gamepad / keyboard cursor)
static var VIOLET := Color("#b98cff") ## rev band and accents (CMR's cyan)
static var PLUM := Color("#6c3fa8")
static var GREEN := Color("#9fe06a") ## kept only for good/bad readings
static var RED := Color("#ff4f5e")
static var AMBER := Color("#ffb020")
static var PURPLE := Color("#d0a2ff")
static var FIELD := Color("#ddd3ea") ## pale flat field, like CMR's light-grey boxes
static var FIELD_HOVER := Color("#ece6f4")
static var FIELD_EDGE := Color("#7c6c97")
static var FIELD_DIM := Color(0.87, 0.83, 0.92, 0.55)
static var PAPER := Color("#f6e3cf") ## the pale sketch panel on the repair page (CMR's cream)
static var PANEL := Color(0.2, 0.15, 0.29, 0.94) ## pause and results sheets
static var PANEL_EDGE := Color(0.85, 0.78, 0.95, 0.5)
static var POPUP := Color("#3a2e52")
## page tints: each front-end page is one flat colour, as in CMR
static var TINT_HOME := Color("#5d4d7c")
static var TINT_SETUP := Color("#5a5173")
static var TINT_INFO := Color("#524a6d")
static var TINT_REPAIR := Color("#5e5476")
static var TINT_OPTIONS := Color("#554c70")
## HUD: the dark plate under in-race panels, the faded end of the CMR gradient bars, the circuit map's field
static var PLATE := Color(0.13, 0.08, 0.2)
static var BAR_FADE := Color(0.55, 0.36, 0.85)
static var MAP := Color("#8a73b0")

const PIXEL_FACES := ["res://fonts/PixelifySans.ttf", "res://fonts/VT323.ttf"] ## the PS1 skin's faces, drawn without antialiasing
const SYMBOLS := [preload("res://fonts/NotoSansSymbols2.ttf"), preload("res://fonts/NotoSansSymbols.ttf")] ## ◂ ▸, arrows, Ⓐ Ⓑ

## RetroPipeline mode -> skin: 0 Off, 1 PS1, 2 NFS Most Wanted, 3 GTA San Andreas, 4 NFS Carbon, 5 CMR 2.0, 6 Forza Horizon 1
const SKIN_FOR_MODE := ["cmr", "ps1", "mw", "sa", "carbon", "cmr", "fh1"]
const PALETTE_KEYS := ["INK", "INK_SOFT", "TEXT", "MUTED", "DIM", "ORANGE", "ORANGE_SOFT", "ORANGE_DEEP", "FOCUS",
	"VIOLET", "PLUM", "GREEN", "RED", "AMBER", "PURPLE", "FIELD", "FIELD_HOVER", "FIELD_EDGE", "FIELD_DIM", "PAPER",
	"PANEL", "PANEL_EDGE", "POPUP", "TINT_HOME", "TINT_SETUP", "TINT_INFO", "TINT_REPAIR", "TINT_OPTIONS",
	"PLATE", "BAR_FADE", "MAP"]
## Per skin: palette overrides (missing keys keep CMR's), the face and its axes, weight shift and clamp,
## the timer face, corner radius, focus-ring radius, horizontal skew, anti-aliased edges, a hard drop
## shadow (PS1 bevel), a neon glow on the focus ring (Carbon) and a text outline (San Andreas).
const SKINS := {
	"cmr": {"face": "res://fonts/NunitoSans.ttf", "axes": {}, "wadd": 0, "wmin": 200, "wmax": 1000, "digits": "",
		"radius": 0, "focus_radius": 4, "skew": 0.0, "aa": true, "drop": 0, "glow": 0, "outline": 0, "title": "", "colors": {}},
	"ps1": {"face": "res://fonts/PixelifySans.ttf", "axes": {}, "wadd": 0, "wmin": 400, "wmax": 700, "digits": "res://fonts/VT323.ttf",
		"radius": 0, "focus_radius": 0, "skew": 0.0, "aa": false, "drop": 3, "glow": 0, "outline": 0, "title": "", "colors": {
		"INK": "#101420", "INK_SOFT": "#4a5068", "TEXT": "#f2f2ee", "MUTED": "#b7c3e0", "DIM": Color(0.93, 0.94, 1.0, 0.5),
		"ORANGE": "#f5c400", "ORANGE_SOFT": "#ffe066", "ORANGE_DEEP": "#a88600", "FOCUS": "#ff4fc8",
		"VIOLET": "#6aa6ff", "PLUM": "#2c4ea6", "GREEN": "#6ee066", "RED": "#ff4848", "AMBER": "#ffa020", "PURPLE": "#c6a0ff",
		"FIELD": "#b5b9c6", "FIELD_HOVER": "#d3d6df", "FIELD_EDGE": "#eceef4", "FIELD_DIM": Color(0.71, 0.73, 0.78, 0.5),
		"PAPER": "#d9dae2", "PANEL": Color(0.09, 0.12, 0.28, 0.96), "PANEL_EDGE": Color(0.86, 0.88, 0.95, 0.75), "POPUP": "#27356c",
		"TINT_HOME": "#1d2b5e", "TINT_SETUP": "#1f2a58", "TINT_INFO": "#1b2854", "TINT_REPAIR": "#212d5c", "TINT_OPTIONS": "#1c2956",
		"PLATE": "#0b1030", "BAR_FADE": "#4f78d8", "MAP": "#34508f"}},
	"mw": {"face": "res://fonts/Oswald.ttf", "axes": {}, "wadd": 150, "wmin": 300, "wmax": 700, "digits": "res://fonts/Saira.ttf",
		"radius": 0, "focus_radius": 0, "skew": 0.2, "aa": true, "drop": 0, "glow": 0, "outline": 0, "title": "", "colors": {
		"INK": "#0e100c", "INK_SOFT": "#4b5045", "TEXT": "#f1f2ea", "MUTED": "#b8bdae", "DIM": Color(0.94, 0.95, 0.9, 0.45),
		"ORANGE": "#c3df1f", "ORANGE_SOFT": "#dcef7c", "ORANGE_DEEP": "#7d930f", "FOCUS": "#fbfbf2",
		"VIOLET": "#8fc4d8", "PLUM": "#355866", "GREEN": "#4ee08a", "RED": "#ff4040", "AMBER": "#ffae1f", "PURPLE": "#c890ff",
		"FIELD": "#c7cac0", "FIELD_HOVER": "#e0e2da", "FIELD_EDGE": "#5a5e54", "FIELD_DIM": Color(0.7, 0.72, 0.68, 0.5),
		"PAPER": "#e6e4da", "PANEL": Color(0.07, 0.075, 0.07, 0.95), "PANEL_EDGE": Color(0.76, 0.87, 0.12, 0.6), "POPUP": "#26282a",
		"TINT_HOME": "#18191a", "TINT_SETUP": "#1c1d1f", "TINT_INFO": "#1a1b1d", "TINT_REPAIR": "#1e1f20", "TINT_OPTIONS": "#191a1c",
		"PLATE": "#060706", "BAR_FADE": "#5b7d88", "MAP": "#3b4a50"}},
	"sa": {"face": "res://fonts/Archivo.ttf", "axes": {"wdth": 88}, "wadd": 300, "wmin": 400, "wmax": 900, "digits": "res://fonts/Archivo.ttf",
		"radius": 0, "focus_radius": 2, "skew": 0.0, "aa": true, "drop": 0, "glow": 0, "outline": 5, "title": "res://fonts/GrenzeGotisch.ttf", "colors": {
		"INK": "#0b0b0d", "INK_SOFT": "#3e4046", "TEXT": "#f3f3f1", "MUTED": "#a9c6e6", "DIM": Color(0.86, 0.9, 0.96, 0.5),
		"ORANGE": "#67b552", "ORANGE_SOFT": "#b6e2a3", "ORANGE_DEEP": "#2f6a28", "FOCUS": "#ffd23f",
		"VIOLET": "#5c90d8", "PLUM": "#23447f", "GREEN": "#c4f27a", "RED": "#e33b3b", "AMBER": "#ffb020", "PURPLE": "#c8a2ff",
		"FIELD": "#cfd9e6", "FIELD_HOVER": "#e6edf5", "FIELD_EDGE": "#23252b", "FIELD_DIM": Color(0.78, 0.82, 0.88, 0.5),
		"PAPER": "#efe8d6", "PANEL": Color(0.03, 0.03, 0.035, 0.93), "PANEL_EDGE": Color(0.95, 0.95, 0.95, 0.45), "POPUP": "#151517",
		"TINT_HOME": "#0d0d0f", "TINT_SETUP": "#111114", "TINT_INFO": "#0f1013", "TINT_REPAIR": "#121215", "TINT_OPTIONS": "#0e0f12",
		"PLATE": "#020203", "BAR_FADE": "#3d6fb8", "MAP": "#2c3f5c"}},
	"carbon": {"face": "res://fonts/Saira.ttf", "axes": {"wdth": 80}, "wadd": 50, "wmin": 250, "wmax": 800, "digits": "res://fonts/Saira.ttf",
		"radius": 2, "focus_radius": 3, "skew": 0.0, "aa": true, "drop": 0, "glow": 8, "outline": 0, "title": "", "colors": {
		"INK": "#05131d", "INK_SOFT": "#36576a", "TEXT": "#e9f7fe", "MUTED": "#9cc4d9", "DIM": Color(0.9, 0.97, 1.0, 0.45),
		"ORANGE": "#1fd6ef", "ORANGE_SOFT": "#8debf8", "ORANGE_DEEP": "#0a879c", "FOCUS": "#ff4fd6",
		"VIOLET": "#3fe0c2", "PLUM": "#176d86", "GREEN": "#86ec7a", "RED": "#ff4d5e", "AMBER": "#ffb020", "PURPLE": "#b98cff",
		"FIELD": "#b9d4e2", "FIELD_HOVER": "#d6e9f2", "FIELD_EDGE": "#2fc8de", "FIELD_DIM": Color(0.6, 0.72, 0.8, 0.45),
		"PAPER": "#dcebf3", "PANEL": Color(0.03, 0.07, 0.13, 0.95), "PANEL_EDGE": Color(0.13, 0.84, 0.94, 0.6), "POPUP": "#102339",
		"TINT_HOME": "#0b1628", "TINT_SETUP": "#0d182c", "TINT_INFO": "#0a1526", "TINT_REPAIR": "#0e1a2e", "TINT_OPTIONS": "#0c172a",
		"PLATE": "#020a14", "BAR_FADE": "#1b9fb8", "MAP": "#1a4560"}},
	"fh1": {"face": "res://fonts/Nunito.ttf", "axes": {}, "wadd": 300, "wmin": 300, "wmax": 1000, "digits": "res://fonts/Nunito.ttf",
		"radius": 10, "focus_radius": 13, "skew": 0.0, "aa": true, "drop": 0, "glow": 0, "outline": 0, "title": "", "colors": {
		"INK": "#2a1024", "INK_SOFT": "#6b4a63", "TEXT": "#fff6fa", "MUTED": "#ffd0e4", "DIM": Color(1.0, 0.93, 0.97, 0.5),
		"ORANGE": "#ffc81f", "ORANGE_SOFT": "#ffb36b", "ORANGE_DEEP": "#d68a00", "FOCUS": "#2ee6ff",
		"VIOLET": "#ff5aa5", "PLUM": "#a3206e", "GREEN": "#8ce65a", "RED": "#ff5252", "AMBER": "#ff9d1a", "PURPLE": "#d29bff",
		"FIELD": "#fff4ea", "FIELD_HOVER": "#fffcf7", "FIELD_EDGE": "#ff8a3d", "FIELD_DIM": Color(1.0, 0.95, 0.91, 0.5),
		"PAPER": "#fff0dc", "PANEL": Color(0.32, 0.07, 0.24, 0.95), "PANEL_EDGE": Color(1.0, 0.78, 0.3, 0.6), "POPUP": "#6e1550",
		"TINT_HOME": "#8f1d63", "TINT_SETUP": "#871b5e", "TINT_INFO": "#7f1a5a", "TINT_REPAIR": "#8b2262", "TINT_OPTIONS": "#841c5d",
		"PLATE": "#2a0a20", "BAR_FADE": "#e8559c", "MAP": "#9b3a78"}},
}

static var skin := "cmr"
static var _cmr_palette := {} ## the palette as declared above, captured before the first switch
static var _old_palette := {} ## the palette before the last switch (for recolor())
static var _theme: Theme
static var _faces := {}

static func skin_for_mode(mode: int) -> String:
	return SKIN_FOR_MODE[clampi(mode, 0, SKIN_FOR_MODE.size() - 1)]

static func palette() -> Dictionary:
	return {"INK": INK, "INK_SOFT": INK_SOFT, "TEXT": TEXT, "MUTED": MUTED, "DIM": DIM, "ORANGE": ORANGE,
		"ORANGE_SOFT": ORANGE_SOFT, "ORANGE_DEEP": ORANGE_DEEP, "FOCUS": FOCUS, "VIOLET": VIOLET, "PLUM": PLUM,
		"GREEN": GREEN, "RED": RED, "AMBER": AMBER, "PURPLE": PURPLE, "FIELD": FIELD, "FIELD_HOVER": FIELD_HOVER,
		"FIELD_EDGE": FIELD_EDGE, "FIELD_DIM": FIELD_DIM, "PAPER": PAPER, "PANEL": PANEL, "PANEL_EDGE": PANEL_EDGE,
		"POPUP": POPUP, "TINT_HOME": TINT_HOME, "TINT_SETUP": TINT_SETUP, "TINT_INFO": TINT_INFO,
		"TINT_REPAIR": TINT_REPAIR, "TINT_OPTIONS": TINT_OPTIONS, "PLATE": PLATE, "BAR_FADE": BAR_FADE, "MAP": MAP}

## The palette a skin would use (CMR's for any key it leaves out).
static func skin_palette(name: String) -> Dictionary:
	if _cmr_palette.is_empty():
		_cmr_palette = palette()
	var out := _cmr_palette.duplicate()
	var colors: Dictionary = SKINS.get(name, SKINS.cmr).colors
	for k in colors:
		out[k] = Color(colors[k]) if colors[k] is String else colors[k]
	return out

static func _set_palette(p: Dictionary) -> void:
	INK = p.INK; INK_SOFT = p.INK_SOFT; TEXT = p.TEXT; MUTED = p.MUTED; DIM = p.DIM
	ORANGE = p.ORANGE; ORANGE_SOFT = p.ORANGE_SOFT; ORANGE_DEEP = p.ORANGE_DEEP; FOCUS = p.FOCUS
	VIOLET = p.VIOLET; PLUM = p.PLUM; GREEN = p.GREEN; RED = p.RED; AMBER = p.AMBER; PURPLE = p.PURPLE
	FIELD = p.FIELD; FIELD_HOVER = p.FIELD_HOVER; FIELD_EDGE = p.FIELD_EDGE; FIELD_DIM = p.FIELD_DIM
	PAPER = p.PAPER; PANEL = p.PANEL; PANEL_EDGE = p.PANEL_EDGE; POPUP = p.POPUP
	TINT_HOME = p.TINT_HOME; TINT_SETUP = p.TINT_SETUP; TINT_INFO = p.TINT_INFO
	TINT_REPAIR = p.TINT_REPAIR; TINT_OPTIONS = p.TINT_OPTIONS
	PLATE = p.PLATE; BAR_FADE = p.BAR_FADE; MAP = p.MAP

## Switches the whole interface to a skin: palette, the cached fonts (changed in place, so every label
## using them follows), the shared theme (refilled in place) and, given a root, every colour already
## baked into that tree's nodes (restyle()).
static func apply_skin(name: String, root: Node = null) -> void:
	if not SKINS.has(name):
		name = "cmr"
	var old := palette()
	_old_palette = old
	skin = name
	_set_palette(skin_palette(name))
	for key in _fonts:
		_configure_font(_fonts[key], key)
	if _theme:
		var fresh := Theme.new()
		_fill_theme(fresh)
		_theme.clear()
		_theme.merge_with(fresh)
		_theme.default_font = font()
		_theme.default_font_size = 17
	if root:
		restyle(root, old)

static func _skin() -> Dictionary:
	return SKINS[skin]

static func _face(path: String) -> Font:
	if path == "res://fonts/NunitoSans.ttf":
		return FACE
	if not _faces.has(path):
		var f: Font = load(path)
		if path in PIXEL_FACES and f is FontFile:
			# PS1: the pixel faces draw hard-edged, blocky glyphs (no antialiasing, hinting or sub-pixel offsets)
			var ff := f as FontFile
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.multichannel_signed_distance_field = false
		_faces[path] = f
	return _faces[path]

static func _fallbacks() -> Array[Font]:
	var out: Array[Font] = []
	for f in SYMBOLS:
		out.append(f)
	out.append(ThemeDB.fallback_font)
	return out

static var _fonts := {}

const FACE := preload("res://fonts/NunitoSans.ttf") ## variable humanist sans (OFL), close to CMR's thin type

## The thin upright sans CMR uses everywhere, at any weight from 200 (menu words) to 800 (the skin's face
## and weight shift in other skins).
static func font(weight := 400) -> Font:
	return _cached("w%d" % weight)

## Digits for timers: a monospaced (or tabular) face so the clock doesn't jitter.
static func digits() -> Font:
	return _cached("digits")

## Page titles (Grenze Gotisch in the San Andreas skin, the body face elsewhere).
static func title_font() -> Font:
	return _cached("title")

static func _cached(key: String) -> Font:
	if not _fonts.has(key):
		var f := FontVariation.new()
		_configure_font(f, key)
		_fonts[key] = f
	return _fonts[key]

static func _configure_font(f: FontVariation, key: String) -> void:
	var sk := _skin()
	var ts := TextServerManager.get_primary_interface()
	var axes := {}
	var features := {}
	if key == "digits":
		if sk.digits == "":
			var mono := SystemFont.new()
			mono.font_names = PackedStringArray(["Menlo", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
			mono.font_weight = 500
			mono.fallbacks = _fallbacks()
			f.base_font = mono
		else:
			f.base_font = _face(sk.digits)
			axes[ts.name_to_tag("wght")] = 600
			if sk.digits == "res://fonts/Saira.ttf":
				axes[ts.name_to_tag("wdth")] = 80
			features[ts.name_to_tag("tnum")] = 1
	elif key == "title" and sk.title != "":
		f.base_font = _face(sk.title)
		axes[ts.name_to_tag("wght")] = 700
	else:
		var weight := 400 if key == "title" else int(key.substr(1))
		f.base_font = _face(sk.face)
		axes[ts.name_to_tag("wght")] = clampi(weight + int(sk.wadd), int(sk.wmin), int(sk.wmax))
		for a in sk.axes:
			axes[ts.name_to_tag(a)] = sk.axes[a]
	f.variation_opentype = axes
	f.opentype_features = features
	f.fallbacks = _fallbacks()

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
	s.set_meta("cmr_box", true)
	_shape(s)
	return s

## The skin's edges on a CmrStyle box: corners, skew (Most Wanted), hard edges and drop shadow (PS1).
static func _shape(s: StyleBoxFlat) -> void:
	var sk := _skin()
	s.set_corner_radius_all(int(sk.radius))
	s.corner_detail = 6
	s.skew = Vector2(sk.skew, 0.0)
	s.anti_aliasing = sk.aa
	var drop := int(sk.drop)
	s.shadow_size = 1 if drop > 0 and s.draw_center and s.bg_color.a > 0.5 else 0
	s.shadow_offset = Vector2(drop, drop)
	s.shadow_color = Color(0, 0, 0, 0.65)

static func panel(color := PANEL, edge := PANEL_EDGE, margin := 22.0) -> StyleBoxFlat:
	var s := box(color, edge, margin, margin)
	return s

## The theme for the whole front end: one shared instance that apply_skin() refills in place.
static func build_theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_fill_theme(_theme)
		_theme.default_font = font()
		_theme.default_font_size = 17
	return _theme

static func _fill_theme(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	var outline := int(_skin().outline) # San Andreas: heavy black outline on text over the tints
	for type in ["Label", "CheckButton", "CheckBox"]:
		t.set_constant("outline_size", type, outline)
		t.set_color("font_outline_color", type, Color(0.0, 0.0, 0.0, 0.92))

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
		# disabled reads through the dim field, which is translucent over the page tint (INK_SOFT vanished
		# into it in the dark skins); the paler field and the faded ink still say "off"
		t.set_color("font_disabled_color", type, Color(INK, 0.78))
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

	var field_focus := box(FIELD_HOVER, FOCUS)
	field_focus.set_border_width_all(4)
	field_focus.set_expand_margin_all(3)
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

	var popup := panel(POPUP, FIELD_EDGE, 4)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(ORANGE, Color.TRANSPARENT, 8, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	t.set_font_size("font_size", "PopupMenu", 17)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "AcceptDialog", popup)

	# scroll bars: a hairline track like the page rules, with a slim rounded handle that lights orange
	for vertical in [true, false]:
		var type := "VScrollBar" if vertical else "HScrollBar"
		var track := StyleBoxLine.new()
		track.vertical = vertical
		track.thickness = 2
		track.color = Color(TEXT, 0.22)
		for side in [SIDE_LEFT, SIDE_RIGHT] if vertical else [SIDE_TOP, SIDE_BOTTOM]:
			track.set_content_margin(side, 3) # 6 px across, the handle's width
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, _grabber(Color(TEXT, 0.6)))
		t.set_stylebox("grabber_highlight", type, _grabber(ORANGE_SOFT))
		t.set_stylebox("grabber_pressed", type, _grabber(ORANGE))

static func _grabber(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	s.corner_detail = 4
	return s

static func _focus_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = FOCUS
	s.set_border_width_all(4) # thick and bright: it has to read from the sofa, on orange buttons too
	s.set_expand_margin_all(5)
	s.set_corner_radius_all(int(_skin().focus_radius))
	s.skew = Vector2(_skin().skew, 0.0)
	s.anti_aliasing = _skin().aa
	var glow := int(_skin().glow) # Carbon: the ring glows like neon
	if glow > 0:
		s.shadow_color = Color(FOCUS, 0.45)
		s.shadow_size = glow
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

## A colour from the palette before the last apply_skin(), carried to the same role in the current one
## (alpha variants, and the darkened(0.3) / lightened(0.2) of the buttons, included). Others are kept.
static func recolor(c: Color, old: Dictionary = _old_palette) -> Color:
	if old.is_empty():
		return c
	var now := palette()
	for k in old:
		var o: Color = old[k]
		var n: Color = now[k]
		for v in [["", o], ["d", o.darkened(0.3)], ["l", o.lightened(0.2)]]:
			var ref: Color = v[1]
			if absf(c.r - ref.r) < 0.003 and absf(c.g - ref.g) < 0.003 and absf(c.b - ref.b) < 0.003:
				var target := n if v[0] == "" else (n.darkened(0.3) if v[0] == "d" else n.lightened(0.2))
				return Color(target, c.a * (n.a / o.a if o.a > 0.0 else 1.0))
	return c

## Recolours every node already built under root from the old palette to the current one: theme
## overrides (colours and the colours of StyleBox overrides, CmrStyle boxes also reshaped), ColorRects,
## modulates; then redraws the custom-drawn controls and calls _skin_changed() where a node has it.
## 3D subviewports are skipped.
static func restyle(root: Node, old: Dictionary = _old_palette) -> void:
	_restyle_node(root, old, {})

static func _restyle_node(node: Node, old: Dictionary, seen: Dictionary) -> void:
	if node is SubViewport or node is Node3D:
		return
	if node is Control:
		for prop in node.get_property_list():
			var pname: String = prop.name
			if pname.begins_with("theme_override_colors/"):
				var c = node.get(pname)
				if c is Color:
					node.set(pname, recolor(c, old))
			elif pname.begins_with("theme_override_styles/"):
				var sb = node.get(pname)
				if sb is StyleBox and not seen.has(sb.get_instance_id()):
					seen[sb.get_instance_id()] = true
					_restyle_box(sb, old)
		if node is ColorRect:
			node.color = recolor(node.color, old)
	if node is CanvasItem:
		node.modulate = recolor(node.modulate, old)
		node.self_modulate = recolor(node.self_modulate, old)
		node.queue_redraw()
	if node.has_method("_skin_changed"):
		node.call("_skin_changed")
	for child in node.get_children(true):
		_restyle_node(child, old, seen)

static func _restyle_box(sb: StyleBox, old: Dictionary) -> void:
	if sb is StyleBoxFlat:
		var s := sb as StyleBoxFlat
		s.bg_color = recolor(s.bg_color, old)
		s.border_color = recolor(s.border_color, old)
		if s.has_meta("cmr_box"):
			_shape(s)
	elif sb is StyleBoxLine:
		(sb as StyleBoxLine).color = recolor((sb as StyleBoxLine).color, old)
