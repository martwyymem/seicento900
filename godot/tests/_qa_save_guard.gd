## Dev helper for windowed QA probes: all worktrees share one user://dev_sandbox/, so a probe backs up the
## save files it may touch, and puts them back at the end (also deleting files that did not exist before).
## const Guard := preload("res://tests/_qa_save_guard.gd"); Guard.backup() ... Guard.restore()
extends RefCounted

const FILES := ["championship.json", "rally.json", "campaign.json", "open_world.json", "race_settings.cfg", "graphics.cfg"]
static var _saved := {}

static func backup() -> void:
	_saved.clear()
	for f in FILES:
		var p: String = SaveData.path(f)
		_saved[f] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null

static func clear(names: Array) -> void:
	for f in names:
		if FileAccess.file_exists(SaveData.path(f)):
			DirAccess.remove_absolute(SaveData.path(f))

static func restore() -> void:
	for f in FILES:
		var p: String = SaveData.path(f)
		var b = _saved.get(f)
		if b == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
		else:
			var h := FileAccess.open(p, FileAccess.WRITE)
			if h:
				h.store_buffer(b)
