## Where the game keeps its saves. Tests and dev tools (anything started with `godot -s script.gd`) save to
## user://dev_sandbox/ instead, so they never touch the player's championship, set-up, graphics settings or
## the AI's learned memory.
class_name SaveData
extends RefCounted

const SANDBOX := "user://dev_sandbox/"

static var _sandboxed = null

static func sandboxed() -> bool:
	if _sandboxed == null:
		# the command line, not the main loop: a tool's _init() runs before its SceneTree is the main loop
		var args := OS.get_cmdline_args()
		_sandboxed = args.has("-s") or args.has("--script")
		if _sandboxed:
			DirAccess.make_dir_recursive_absolute(SANDBOX)
	return _sandboxed

## Path of a save file, e.g. path("championship.json").
static func path(file: String) -> String:
	return SANDBOX + file if sandboxed() else "user://" + file

## Path to read settings from: in the sandbox, the player's own file until a tool saves its own copy.
static func read_path(file: String) -> String:
	var p := path(file)
	return p if FileAccess.file_exists(p) else "user://" + file

# ---------------- safe loading of files a player may have been handed ----------------
## ConfigFile.load parses values in Godot's text Variant format, which accepts `Resource("user://x.tres")` and
## `Object(Class, ...)`: a shared settings file could load a crafted resource whose embedded script then runs.
## Every ConfigFile read of a user:// file goes through load_cfg()/load_cfg_into() instead, which refuses a file
## that names such a constructor. The parser skips every character up to a space and `;` comments between a name
## and its parenthesis, so the pattern does too (a string that merely contains `Resource(` is refused as well:
## telling strings from comments reliably is not worth the risk).
const _CODE_PATTERN := "\\b(Resource|Object|ExtResource|SubResource)\\b([\\x01-\\x20]|;[^\\n\\r]*)*\\("
static var _code_rx: RegEx = null

## Whether settings text names an object constructor.
static func has_object_syntax(text: String) -> bool:
	if _code_rx == null:
		_code_rx = RegEx.new()
		_code_rx.compile(_CODE_PATTERN)
	return _code_rx.search(text) != null

## Loads `path` into `cfg` like ConfigFile.load (OK, or the error: ERR_FILE_NOT_FOUND, ERR_INVALID_DATA for a
## file naming Resource/Object syntax, which is refused with a warning and leaves `cfg` untouched).
static func load_cfg_into(cfg: ConfigFile, path: String) -> int:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	if has_object_syntax(text):
		push_warning("SaveData: refusing %s (it names an Object/Resource value)" % path)
		return ERR_INVALID_DATA
	return cfg.parse(text)

## A ConfigFile read from `path`; an empty one when the file is missing, unreadable or refused.
static func load_cfg(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	if load_cfg_into(cfg, path) != OK:
		return ConfigFile.new()
	return cfg

## The JSON in a string, or null when it does not parse (quietly: JSON.parse_string prints an engine error for bad text).
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data

## The JSON in a file, or null when there is none or it does not parse.
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return parse_json(FileAccess.get_file_as_string(path))

## Sets a save the game cannot read aside as `<file>.bad` (so the next save does not destroy it silently).
static func quarantine(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bad")

## Typed reads of a JSON value of unknown type: the value as a number/bool/string, or `fallback` when it is
## another kind of thing (int(Array) is a script error, so the loaders never call int() on raw JSON).
static func to_float(v: Variant, fallback := 0.0) -> float:
	if v is float or v is int:
		return float(v) if is_finite(float(v)) else fallback
	if v is String and (v as String).is_valid_float():
		return (v as String).to_float()
	return fallback

static func to_int(v: Variant, fallback := 0) -> int:
	if v is float or v is int:
		return int(v) if is_finite(float(v)) else fallback
	if v is String and (v as String).is_valid_int():
		return (v as String).to_int()
	return fallback

static func to_bool(v: Variant, fallback := false) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return fallback

static func to_str(v: Variant, fallback := "") -> String:
	if v is String or v is int or v is float or v is bool:
		return str(v)
	return fallback

## A saved championship (champ_data) cleaned up: {} when `parsed` is not usable, else a Dictionary whose
## round/scored are plain numbers/bools, whose table holds only well-formed entries, and whose config and car are
## Dictionaries (or absent). Entries are rebuilt with the fields the standings and the result tables read.
static func clean_championship(parsed: Variant) -> Dictionary:
	if not (parsed is Dictionary):
		return {}
	var src: Dictionary = parsed
	var table_in = src.get("table", {})
	if not (table_in is Dictionary):
		return {}
	var table := {}
	for k in (table_in as Dictionary):
		var e = table_in[k]
		if not (e is Dictionary):
			continue
		table[str(k)] = {"id": to_int(e.get("id", 0)), "name": to_str(e.get("name", "?"), "?"),
			"number": to_int(e.get("number", 0)), "color": to_str(e.get("color", "888888"), "888888"),
			"is_player": to_bool(e.get("is_player", false)), "points": to_int(e.get("points", 0)),
			"wins": to_int(e.get("wins", 0))}
	var out := {"round": to_int(src.get("round", -1), -1), "scored": to_bool(src.get("scored", false)), "table": table}
	if src.get("config") is Dictionary:
		out["config"] = src["config"]
	var car = src.get("car")
	if car is Dictionary:
		out["car"] = clean_carried_car(car)
	return out

## A carried car ({parts, pull, used, serviced}) with only well-typed fields; {} when it is not a Dictionary.
static func clean_carried_car(car: Variant) -> Dictionary:
	if not (car is Dictionary) or (car as Dictionary).is_empty():
		return {}
	var parts := {}
	var parts_in = car.get("parts", {})
	if parts_in is Dictionary:
		for p in parts_in:
			parts[str(p)] = clampf(to_float(parts_in[p]), 0.0, 1.0)
	return {"parts": parts, "pull": to_float(car.get("pull", 0.0)), "used": to_int(car.get("used", 0)),
		"serviced": to_bool(car.get("serviced", false))}
