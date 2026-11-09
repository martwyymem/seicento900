## Fingerprints the GDScript a cached build step depends on, so editing unrelated code leaves its cache valid.
##
## A script is cut into its top-level members (functions, constants, variables, signals, enums). The fingerprint of a
## step is the MD5 of its root functions plus every member they name, transitively, in the same script, plus the
## members of the TownMap script they reach through `map.` or `TownMap.` (and that script's own references).
## Comments, blank lines and trailing blanks are ignored. Names are matched as whole words anywhere in a member's code,
## so a member is never missed because of how it is called, only ever over-included (a local that shares a member's name).
## Whatever a step uses that is not a member of those two scripts (another class, a data file) the caller adds itself.
## (No class_name: a new global class needs an editor --import before headless runs find it. Use preload.)
extends RefCounted

static var _parsed := {} ## path -> {name: code}
static var _nonword: RegEx
static var _maps: RegEx
static var _comments: RegEx
static var _decl: RegEx
static var _dotted: RegEx
static var _local: RegEx
static var _params: RegEx
static var _param_name: RegEx

static func _init_regex() -> void:
	if _nonword:
		return
	_nonword = RegEx.create_from_string("[^A-Za-z0-9_]+")
	_maps = RegEx.create_from_string("\\b(?:map|TownMap)\\.([A-Za-z_][A-Za-z0-9_]*)")
	# a string literal is kept (it may hold a '#'), a comment goes
	_comments = RegEx.create_from_string("(\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*')|#[^\\n]*")
	_dotted = RegEx.create_from_string("\\.\\s*[A-Za-z_][A-Za-z0-9_]*")
	_local = RegEx.create_from_string("\\b(?:var|for)\\s+([A-Za-z_][A-Za-z0-9_]*)")
	_params = RegEx.create_from_string("func\\s*[A-Za-z0-9_]*\\s*\\(([^)]*)\\)")
	_param_name = RegEx.create_from_string("(?:^|,)\\s*([A-Za-z_][A-Za-z0-9_]*)")
	_decl = RegEx.create_from_string("^(?:@\\w+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?(?:func|var|const|signal|enum|class)\\s+([A-Za-z_][A-Za-z0-9_]*)")

## The top-level members of the script at `path` as {name: code without comments or blank lines}; {} if its source is
## not there (an exported game).
static func members(path: String) -> Dictionary:
	if _parsed.has(path):
		return _parsed[path]
	_init_regex()
	var out := {}
	if FileAccess.file_exists(path):
		var text := _comments.sub(FileAccess.get_file_as_string(path), "$1", true)
		var name := ""
		var code := PackedStringArray()
		for line in text.split("\n"):
			var l := line.rstrip(" \t\r")
			if l == "":
				continue
			var m := _decl.search(l)
			if m:
				if name != "":
					out[name] = "\n".join(code)
				name = m.get_string(1)
				code = PackedStringArray()
			code.append(l)
		if name != "":
			out[name] = "\n".join(code)
	_parsed[path] = out
	return out

## The names a member's code uses as members of its own script: whole words, minus attribute names (`x.name`) and the
## member's own locals, parameters and loop variables, which hide a member of the same name.
static func names_in(code: String) -> PackedStringArray:
	var hidden := {}
	for m in _local.search_all(code):
		hidden[m.get_string(1)] = true
	for m in _params.search_all(code):
		for p in _param_name.search_all(m.get_string(1)):
			hidden[p.get_string(1)] = true
	var out := PackedStringArray()
	for tok in _nonword.sub(_dotted.sub(code, " ", true), " ", true).split(" ", false):
		if not hidden.has(tok):
			out.append(tok)
	return out

## The members `roots` reach, as {"own": [names in own_path], "map": [names in map_path]} (sorted): the code a fingerprint covers.
static func reached(own_path: String, roots: Array, map_path: String, map_roots: Array = []) -> Dictionary:
	_init_regex()
	var own := members(own_path)
	var map := members(map_path)
	var seen_own := {}
	var seen_map := {}
	var queue_own: Array = roots.duplicate()
	var queue_map: Array = map_roots.duplicate()
	while not queue_own.is_empty() or not queue_map.is_empty():
		while not queue_own.is_empty():
			var name: String = queue_own.pop_back()
			if seen_own.has(name) or not own.has(name):
				continue
			seen_own[name] = true
			var code: String = own[name]
			for tok in names_in(code):
				if own.has(tok) and not seen_own.has(tok):
					queue_own.append(tok)
			for m in _maps.search_all(code):
				queue_map.append(m.get_string(1))
		while not queue_map.is_empty():
			var name: String = queue_map.pop_back()
			if seen_map.has(name) or not map.has(name):
				continue
			seen_map[name] = true
			for tok in names_in(map[name]):
				if map.has(tok) and not seen_map.has(tok):
					queue_map.append(tok)
	var own_names: Array = seen_own.keys()
	own_names.sort()
	var map_names: Array = seen_map.keys()
	map_names.sort()
	return {"own": own_names, "map": map_names}

## The fingerprint of `roots` (member names of `own_path`) and everything they reach (see reached()), "" if the script
## sources are not there. `map_roots` are members of `map_path` that count as reached whatever the roots name (the
## map's loader).
static func closure(own_path: String, roots: Array, map_path: String, map_roots: Array = []) -> String:
	var own := members(own_path)
	if own.is_empty():
		return ""
	var map := members(map_path)
	var got := reached(own_path, roots, map_path, map_roots)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for pair in [[own, got.own], [map, got.map]]:
		for name in pair[1]:
			ctx.update((String(name) + "\n" + String(pair[0][name]) + "\n").to_utf8_buffer())
	return ctx.finish().hex_encode()
