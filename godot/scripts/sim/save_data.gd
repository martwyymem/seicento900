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
