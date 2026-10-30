## Developer overlay toggled by tapping the ~ key (the key left of 1, whatever the layout prints on it): fps, frame
## times over the last few seconds with a frame-time graph, CPU process/physics time, render counters and
## memory. It sits above every page, menus and pause included, and costs nothing while hidden.
class_name DevHud
extends CanvasLayer

const HISTORY := 240 ## frames kept for the graph and the averages
const REFRESH := 0.25 ## seconds between text updates, so the numbers stay readable
const GRAPH_SIZE := Vector2(360, 60)
const GRAPH_MAX_MS := 50.0 ## graph ceiling; a frame above this pins to the top
const TARGET_MS := 1000.0 / 60.0 ## the 60 fps line
const PAD := 10.0
const LINE_HEIGHT := 17.0
const FONT_SIZE := 13

var _panel: Control
var _frames := PackedFloat32Array() ## ring buffer of frame times in ms
var _head := 0
var _filled := 0
var _refresh_left := 0.0
var _lines: PackedStringArray = []
var _adapter := ""

func _init() -> void:
	name = "DevHud"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_frames.resize(HISTORY)

func _ready() -> void:
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(12, 12)
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	_adapter = RenderingServer.get_video_adapter_name()
	set_process(false)

static func _is_toggle_key(key: InputEventKey) -> bool:
	return key.physical_keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_SECTION or key.keycode == KEY_SECTION

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo or not _is_toggle_key(key):
		return
	if key.pressed:
		DevMenu.chord_used = false # a new press: a chord with 1 (DevMenu) will set it again
		return
	if DevMenu.chord_used:
		return # § + 1 opened the dev menu, not this overlay
	visible = not visible
	set_process(visible)
	_filled = 0
	_head = 0
	_refresh_left = 0.0
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_frames[_head] = delta * 1000.0
	_head = (_head + 1) % HISTORY
	_filled = mini(_filled + 1, HISTORY)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		_lines = _build_lines()
	_panel.queue_redraw()

func _build_lines() -> PackedStringArray:
	var sorted := _frames.slice(0, _filled)
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += ms
	var avg := total / maxf(_filled, 1)
	var worst := sorted[_filled - 1]
	# 1% low: the average of the slowest percent of frames, the number that shows stutter
	var slow_count := maxi(1, int(_filled * 0.01))
	var slow_total := 0.0
	for i in slow_count:
		slow_total += sorted[_filled - 1 - i]
	var low_fps := 1000.0 / maxf(slow_total / slow_count, 0.001)
	var window := get_window()
	var lines := PackedStringArray()
	lines.append("%d FPS   %.2f ms" % [Engine.get_frames_per_second(), _frames[posmod(_head - 1, HISTORY)]])
	lines.append("avg %.2f ms (%.0f fps)   worst %.2f ms" % [avg, 1000.0 / maxf(avg, 0.001), worst])
	lines.append("1%% low %.0f fps" % low_fps)
	lines.append("CPU process %.2f ms  physics %.2f ms" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	lines.append("draw calls %d   objects %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	lines.append("primitives %s" % _thousands(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))))
	lines.append("video mem %.0f MB   ram %.0f MB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	lines.append("nodes %d   window %dx%d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), window.size.x, window.size.y])
	lines.append("vsync %s   time scale %.2f" % [_vsync_name(DisplayServer.window_get_vsync_mode()), Engine.time_scale])
	if _adapter != "":
		lines.append(_adapter)
	return lines

func _draw_panel() -> void:
	if _lines.is_empty():
		return
	var font := CmrStyle.digits()
	var size := Vector2(GRAPH_SIZE.x + PAD * 2.0, _lines.size() * LINE_HEIGHT + GRAPH_SIZE.y + PAD * 3.0 + 4.0)
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(CmrStyle.PLATE, 0.82))
	_panel.draw_rect(Rect2(Vector2.ZERO, size), CmrStyle.PANEL_EDGE, false, 1.0)
	for i in _lines.size():
		var color := CmrStyle.ORANGE_SOFT if i == 0 else CmrStyle.TEXT
		_panel.draw_string(font, Vector2(PAD, PAD + (i + 1) * LINE_HEIGHT - 4.0), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, color)
	_draw_graph(Vector2(PAD, PAD * 2.0 + _lines.size() * LINE_HEIGHT))

func _draw_graph(origin: Vector2) -> void:
	_panel.draw_rect(Rect2(origin, GRAPH_SIZE), Color(0, 0, 0, 0.35))
	var line_y := origin.y + GRAPH_SIZE.y * (1.0 - TARGET_MS / GRAPH_MAX_MS)
	_panel.draw_line(Vector2(origin.x, line_y), Vector2(origin.x + GRAPH_SIZE.x, line_y), Color(CmrStyle.GREEN, 0.5), 1.0)
	var bar := GRAPH_SIZE.x / HISTORY
	for i in _filled:
		var ms := _frames[posmod(_head - _filled + i, HISTORY)]
		var h := GRAPH_SIZE.y * minf(ms / GRAPH_MAX_MS, 1.0)
		var color := CmrStyle.GREEN if ms <= TARGET_MS else (CmrStyle.AMBER if ms <= TARGET_MS * 2.0 else CmrStyle.RED)
		_panel.draw_rect(Rect2(origin.x + (HISTORY - _filled + i) * bar, origin.y + GRAPH_SIZE.y - h, maxf(bar, 1.0), h), color)

static func _thousands(n: int) -> String:
	var s := str(n)
	for i in range(s.length() - 3, 0, -3):
		s = s.insert(i, ",")
	return s

static func _vsync_name(mode: DisplayServer.VSyncMode) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED: return "off"
		DisplayServer.VSYNC_ENABLED: return "on"
		DisplayServer.VSYNC_ADAPTIVE: return "adaptive"
		DisplayServer.VSYNC_MAILBOX: return "mailbox"
	return "?"
