class_name ResultTable
extends VBoxContainer
## A data-first table for the qualifying sheet and the championship standings: a fixed header over rows
## of position, driver and numbers, the player's row picked out, long names cut with an ellipsis, and a
## scroll once the rows would be taller than max_body. Everything is drawn from CmrStyle, so every skin
## looks the way it should. The sorting and formatting are static so the tests can run them without a UI.

const ROW_H := 30.0
const HEADER_H := 24.0
const ROW_GAP := 2.0

## A column: {title, width, align ("l" or "r"), expand (the driver column takes the leftover width), muted}
var columns: Array = []
var max_body := 460.0 ## px of rows shown before the body scrolls
var body: VBoxContainer
var scroll: ScrollContainer
var rows_added := 0

func _init() -> void:
	add_theme_constant_override("separation", int(ROW_GAP))

## Builds the header and the empty body; add the rows with add_row().
func setup(cols: Array, max_body_px := 460.0) -> void:
	columns = cols
	max_body = max_body_px
	for c in get_children():
		c.queue_free()
	rows_added = 0
	add_child(_line(cols.map(func(c: Dictionary) -> String: return c.title), CmrStyle.box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 14, 3),
		CmrStyle.ORANGE_SOFT, 12, null, HEADER_H, true))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", int(ROW_GAP))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_fit_body()

## One row. highlight picks the player's row out; swatch (a Color) puts the car colour before the driver;
## muted greys the row (a car with no time).
func add_row(cells: Array, highlight := false, swatch = null, muted := false) -> void:
	var fill: Color = CmrStyle.ORANGE if highlight else (CmrStyle.FIELD if rows_added % 2 == 0 else CmrStyle.FIELD_DIM)
	var ink: Color = CmrStyle.INK if not muted or highlight else CmrStyle.INK_SOFT
	body.add_child(_line(cells, CmrStyle.box(fill, Color.TRANSPARENT, 14, 3), ink, 15, swatch, ROW_H, false))
	rows_added += 1
	_fit_body()

func _fit_body() -> void:
	var h := rows_added * (ROW_H + ROW_GAP)
	scroll.custom_minimum_size.y = minf(h, max_body)

func body_height() -> float:
	return minf(rows_added * (ROW_H + ROW_GAP), max_body)

func _line(cells: Array, style: StyleBox, ink: Color, font_size: int, swatch, height: float, header: bool) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", style)
	bar.custom_minimum_size.y = height
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	bar.add_child(line)
	for k in columns.size():
		var col: Dictionary = columns[k]
		var l := Label.new()
		l.text = str(cells[k]) if k < cells.size() else ""
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", CmrStyle.MUTED if (col.get("muted", false) and not header and ink == CmrStyle.INK) else ink)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # a cut name says so ("…")
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if col.get("align", "l") == "r" else HORIZONTAL_ALIGNMENT_LEFT
		if col.get("expand", false):
			l.custom_minimum_size.x = 60.0
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if swatch != null and not header:
				var name_row := HBoxContainer.new()
				name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var sw := ColorRect.new()
				sw.color = swatch
				sw.custom_minimum_size = Vector2(6, 16)
				sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				name_row.add_child(sw)
				name_row.add_child(l)
				line.add_child(name_row)
				continue
		else:
			l.custom_minimum_size.x = col.width
		line.add_child(l)
	return bar

# ------------------------------------------------------------------------------------------ data

## The championship order with shared ranks. Points, then wins, then the car's id (a stable tiebreak, as
## no countback is kept). Returns [{entry, rank, tied}]: cars level on points AND wins share a rank
## (1, 2, 2, 4) and are marked tied, because the id order between them says nothing about the racing.
static func rank_standings(table: Array) -> Array:
	var list := table.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.points) != int(b.points):
			return int(a.points) > int(b.points)
		if int(a.get("wins", 0)) != int(b.get("wins", 0)):
			return int(a.get("wins", 0)) > int(b.get("wins", 0))
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	var out := []
	for i in list.size():
		var e: Dictionary = list[i]
		var level := i > 0 and int(e.points) == int(list[i - 1].points) and int(e.get("wins", 0)) == int(list[i - 1].get("wins", 0))
		var rank: int = int(out[i - 1].rank) if level else i + 1
		out.append({"entry": e, "rank": rank, "tied": level})
		if level:
			out[i - 1].tied = true
	return out

## "1", or "2=" for a shared rank.
static func rank_text(rank: int, tied: bool) -> String:
	return "%d%s" % [rank, "=" if tied else ""]

## Points behind the leader: "" for the leader, "−12" otherwise.
static func points_gap(points: int, leader_points: int) -> String:
	return "" if points >= leader_points else "−%d" % (leader_points - points)

## A lap gap to pole: "" for pole and for no time, "+0.231", "+1:04.200" past a minute.
static func gap_text(gap) -> String:
	if gap == null or float(gap) <= 0.0:
		return ""
	var g := roundf(float(gap) * 1000.0) / 1000.0 # (59.9996 would print as +60.000 under a minute)
	if g >= 60.0:
		return "+%d:%06.3f" % [int(g) / 60, fmod(g, 60.0)]
	return "+%.3f" % g

## A lap time, "NO TIME" when there is none, with a stewards' penalty added after it ("1:23.456 +5s").
static func time_text(time, penalty := 0.0) -> String:
	if time == null:
		return "NO TIME"
	var s := Race.fmt_time(float(time))
	if penalty > 0.0:
		s += " +%ds" % roundi(penalty)
	return s

## The qualifying sheet as table cells: POS, DRIVER, TIME, GAP, km/h. Cars without a time share the last
## places and show a dash for the position.
static func quali_cells(r: Dictionary) -> Array:
	var penalty := float(r.get("penalty", 0.0))
	return [str(r.pos) if r.time != null else "–", str(r.name), time_text(r.time, penalty),
		gap_text(r.gap) if r.pos > 1 else "", ("%.1f" % float(r.speed)) if r.speed != null else ""]

## A qualifying row's time with its penalty added, for ordering a sheet that carries penalties.
static func effective_time(r: Dictionary):
	return null if r.time == null else float(r.time) + float(r.get("penalty", 0.0))

## Re-sorts a sheet whose rows carry penalties (time + penalty), renumbering the positions and gaps.
## Rows without a time go last in their original order. Leaves rows without penalties as they are.
static func apply_penalties(rows: Array) -> Array:
	var out := rows.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta = effective_time(a)
		var tb = effective_time(b)
		if (ta == null) != (tb == null):
			return tb == null
		if ta == null or ta == tb:
			return int(a.get("id", 0)) < int(b.get("id", 0))
		return ta < tb)
	var pole = effective_time(out[0]) if not out.is_empty() else null
	for i in out.size():
		var t = effective_time(out[i])
		out[i].pos = i + 1
		out[i].gap = t - pole if t != null and pole != null else null
	return out

static func quali_columns() -> Array:
	return [{"title": "POS", "width": 40, "align": "r"}, {"title": "DRIVER", "expand": true},
		{"title": "LAP TIME", "width": 150, "align": "r"}, {"title": "GAP", "width": 110, "align": "r"},
		{"title": "KM/H", "width": 70, "align": "r", "muted": true}]

static func standings_columns() -> Array:
	return [{"title": "POS", "width": 46, "align": "r"}, {"title": "DRIVER", "expand": true},
		{"title": "WINS", "width": 56, "align": "r", "muted": true}, {"title": "POINTS", "width": 80, "align": "r"},
		{"title": "BEHIND", "width": 80, "align": "r", "muted": true}]

static func standings_cells(ranked: Dictionary, leader_points: int) -> Array:
	var e: Dictionary = ranked.entry
	return [rank_text(ranked.rank, ranked.tied), str(e.name), str(int(e.get("wins", 0))), str(int(e.points)),
		points_gap(int(e.points), leader_points)]
