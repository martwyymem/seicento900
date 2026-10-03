## Optional art assets for the race world: HDRI skies, PBR ground textures and tree models.
## Nothing here is required. The world looks for files under res://assets (in the project) and
## user://assets (next to the save data, so an exported build can be given assets too) and falls back
## to its procedural look for anything that is missing. See godot/ASSETS.md for what to put where.
extends RefCounted

const ROOTS := ["res://assets", "user://assets"]
const SKY_CACHE := "user://sky_cache.cfg"
const SKY_EXTS := ["hdr", "exr", "png", "jpg", "webp"]
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp"]
const MODEL_EXTS := ["glb", "gltf"]
const TEXTURE_CACHE_SIZE := 4

## Material folders under assets/textures/ and the file-name hints for each map.
const MAP_HINTS := {
	"albedo": ["_diff", "diffuse", "albedo", "basecolor", "base_color", "_color", "_col_", "_col."],
	"normal": ["nor_gl", "normalgl", "normal_gl", "_normal", "_nor"],
	"roughness": ["_rough", "roughness"],
}

## Every sky: {path, kind ("clear" | "overcast" | "night"), el, az (radians of its sun/moon), half ("am" | "pm" | ""), mean}
var skies: Array[Dictionary] = []
var _textures := {} ## path -> Texture2D (small LRU for sky panoramas)
var _texture_order: Array[String] = []
var _pending := {} ## path -> WorkerThreadPool task id
var _pending_images := {} ## path -> Image loaded by a worker
var _mutex := Mutex.new()
var _material_cache := {}

func _init() -> void:
	_scan_skies()

# ---------------- files ----------------

## Files in assets/<sub> with one of the extensions, across both roots (imported or raw).
static func list_files(sub: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for root in ROOTS:
		var dir: String = root.path_join(sub)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			# exported builds list imported files as name.ext.import / name.ext.remap
			var name := f.trim_suffix(".import").trim_suffix(".remap")
			var path: String = dir.path_join(name)
			if exts.has(name.get_extension().to_lower()) and not out.has(path):
				out.append(path)
	out.sort()
	return out

static func list_dirs(sub: String) -> PackedStringArray:
	var out := PackedStringArray()
	for root in ROOTS:
		var dir: String = root.path_join(sub)
		if DirAccess.dir_exists_absolute(dir):
			for d in DirAccess.get_directories_at(dir):
				if not out.has(d):
					out.append(d)
	return out

## An Image from an imported texture or straight from the file on disk.
static func load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			var img := tex.get_image()
			if img and img.is_compressed():
				img.decompress()
			return img
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var raw := Image.load_from_file(abs_path)
	return raw

static func load_texture(path: String, mipmaps := true) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex and not mipmaps:
			return tex
		if tex:
			# the ground shaders read the texture's average from its smallest mip, and distant ground shimmers
			# without them, so an import with mipmaps off is rebuilt with them
			var img := tex.get_image()
			if img == null or img.has_mipmaps():
				return tex
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	var img := load_image(path)
	if img == null or img.is_empty():
		return null
	if mipmaps and not img.has_mipmaps():
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ---------------- skies ----------------

## Finds each HDRI's sun (brightest pixel) and overall brightness once, then caches the result.
func _scan_skies() -> void:
	var files := list_files("sky", SKY_EXTS)
	if files.is_empty():
		return
	var cache := ConfigFile.new()
	cache.load(SKY_CACHE)
	var dirty := false
	for path in files:
		var stamp := FileAccess.get_modified_time(ProjectSettings.globalize_path(path))
		if stamp == 0:
			stamp = FileAccess.get_modified_time(path + ".import")
		var info: Dictionary = cache.get_value("skies", path, {})
		if info.get("stamp", -1) != stamp:
			info = _analyse_sky(path)
			if info.is_empty():
				continue
			info["stamp"] = stamp
			cache.set_value("skies", path, info)
			dirty = true
		info["path"] = path
		skies.append(info)
	if dirty:
		cache.save(SKY_CACHE)

static func _analyse_sky(path: String) -> Dictionary:
	var img := load_image(path)
	if img == null or img.is_empty():
		push_warning("Sky asset %s could not be read" % path)
		return {}
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBF)
	img.resize(256, 128, Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var peak := -1.0
	var peak_at := Vector2i.ZERO
	var lums := PackedFloat32Array()
	var rings := PackedFloat32Array()
	for y in h / 2:
		var ring := sin(PI * (float(y) + 0.5) / float(h)) # equal-area weighting towards the zenith
		for x in w:
			var lum := img.get_pixel(x, y).get_luminance()
			lums.append(lum)
			rings.append(ring)
			if lum > peak:
				peak = lum
				peak_at = Vector2i(x, y)
	# brightness of the sky itself: the sun is clipped so it does not decide the exposure
	var sorted := lums.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2]
	var total := 0.0
	var weight := 0.0
	for i in lums.size():
		total += minf(lums[i], median * 6.0) * rings[i]
		weight += rings[i]
	var mean := total / maxf(weight, 1e-6)
	var name := path.get_file().to_lower()
	var half := ""
	for hint in ["dawn", "sunrise", "morning"]:
		if name.contains(hint):
			half = "am"
	for hint in ["afternoon", "sunset", "dusk", "evening"]:
		if name.contains(hint):
			half = "pm"
	var u := (float(peak_at.x) + 0.5) / float(w)
	var v := (float(peak_at.y) + 0.5) / float(h)
	var el := rad_to_deg(PI * 0.5 - v * PI)
	var sun_visible := peak >= median * 25.0
	var kind := "clear"
	if name.contains("night") or name.contains("moon"):
		kind = "night"
	elif name.contains("overcast") or (not sun_visible and half == ""):
		kind = "overcast"
	elif not sun_visible:
		# twilight: the sun is below the horizon and only its glow shows (the glow still gives the azimuth)
		el = -6.0 if name.contains("dusk_2") or name.contains("twilight") else -3.0
	return {
		"kind": kind,
		"half": half,
		"el": el,
		"az": (u - 0.5) * TAU,
		"mean": mean,
	}

func has_skies() -> bool:
	return not skies.is_empty()

func skies_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in skies:
		if s.kind == kind:
			out.append(s)
	out.sort_custom(func(a, b): return a.el < b.el)
	return out

## The panorama for a sky, or null while it is still loading on a worker thread (wait=false).
func sky_texture(path: String, wait := false) -> Texture2D:
	if _textures.has(path):
		_texture_order.erase(path)
		_texture_order.append(path)
		return _textures[path]
	if not _pending.has(path):
		if wait:
			_store(path, load_texture(path, false))
			return _textures.get(path)
		_pending[path] = WorkerThreadPool.add_task(_load_async.bind(path), false, "sky " + path.get_file())
		return null
	if not WorkerThreadPool.is_task_completed(_pending[path]) and not wait:
		return null
	_wait_for(_pending[path])
	_pending.erase(path)
	_mutex.lock()
	var img: Image = _pending_images.get(path)
	_pending_images.erase(path)
	_mutex.unlock()
	_store(path, ImageTexture.create_from_image(img) if img and not img.is_empty() else null)
	return _textures.get(path)

func _load_async(path: String) -> void:
	var img := load_image(path)
	_mutex.lock()
	_pending_images[path] = img
	_mutex.unlock()

func _store(path: String, tex: Texture2D) -> void:
	_textures[path] = tex
	_texture_order.append(path)
	while _texture_order.size() > TEXTURE_CACHE_SIZE:
		_textures.erase(_texture_order.pop_front())

## Waits for any worker still reading a panorama (call before freeing).
func finish() -> void:
	for id in _pending.values():
		_wait_for(id)
	_pending.clear()

## Blocks until a panorama worker is done. Its get_image() is answered by the main thread's rendering
## queue, so that queue is flushed while waiting: a bare wait_for_task_completion() would deadlock.
static func _wait_for(id: int) -> void:
	while not WorkerThreadPool.is_task_completed(id):
		RenderingServer.force_sync()
		OS.delay_usec(500)
	WorkerThreadPool.wait_for_task_completion(id)

# ---------------- ground textures ----------------

## A PBR set from assets/textures/<name>/: {albedo, normal, roughness (Texture2D or null)}.
## Returns {} when the folder or its colour map is missing.
func material_set(folder: String) -> Dictionary:
	if _material_cache.has(folder):
		return _material_cache[folder]
	var files := list_files("textures".path_join(folder), IMAGE_EXTS)
	var found := {}
	for f in files:
		var lower := f.get_file().to_lower()
		for map in MAP_HINTS:
			if found.has(map):
				continue
			for hint in MAP_HINTS[map]:
				if lower.contains(hint) and not lower.contains("nor_dx") and not lower.contains("normaldx"):
					found[map] = f
					break
	var out := {}
	if found.has("albedo"):
		var albedo := load_texture(found.albedo)
		if albedo:
			out.albedo = albedo
			out.normal = load_texture(found.normal) if found.has("normal") else null
			out.roughness = load_texture(found.roughness) if found.has("roughness") else null
	_material_cache[folder] = out
	return out

# ---------------- tree models ----------------

## Tree variants from assets/models/trees/*.glb: each is [[Mesh, Transform3D], ...] scaled to 1 m tall,
## standing on its origin. A file whose root holds several separate trees gives one variant per tree.
func tree_variants() -> Array:
	var variants := []
	for path in list_files("models/trees", MODEL_EXTS):
		var scene := _load_model(path)
		if scene == null:
			continue
		var groups: Array[Node] = []
		var roots_with_mesh := scene.get_children().filter(func(c): return not _meshes_under(c, Transform3D.IDENTITY).is_empty())
		if roots_with_mesh.size() > 1:
			groups.assign(roots_with_mesh)
		else:
			groups.append(scene)
		for g in groups:
			var base: Transform3D = Transform3D.IDENTITY
			if g != scene and g is Node3D:
				base = Transform3D(g.transform.basis, Vector3.ZERO)
			var parts := _meshes_under(g, base)
			if parts.is_empty():
				continue
			var box := AABB()
			for i in parts.size():
				var b: AABB = parts[i][1] * parts[i][0].get_aabb()
				box = b if i == 0 else box.merge(b)
			if box.size.y < 0.01:
				continue
			# centre on the trunk, feet on y=0, 1 m tall
			var fit := Transform3D(Basis().scaled(Vector3.ONE / box.size.y), Vector3.ZERO) * Transform3D(Basis(), -Vector3(box.get_center().x, box.position.y, box.get_center().z))
			var variant := []
			for p in parts:
				variant.append([p[0], fit * p[1]])
			variants.append(variant)
		scene.free()
	return variants

static func _load_model(path: String) -> Node:
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			return packed.instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_warning("Tree model %s could not be read" % path)
		return null
	return doc.generate_scene(state)

static func _meshes_under(node: Node, xf: Transform3D) -> Array:
	var out := []
	var here := xf
	if node is MeshInstance3D and node.mesh:
		out.append([node.mesh, here])
	for c in node.get_children():
		var cx: Transform3D = here * (c.transform if c is Node3D else Transform3D.IDENTITY)
		out.append_array(_meshes_under(c, cx))
	return out
