## Course dressing and animated MultiMesh spectators for street stages and rally stages.
## Placed strictly from PaceNotes (corner grades, caution flags, crests, chicanes) and Track/Surroundings
## geometry — never from corner names, never on circuits that already carry trackside furniture, and never
## on the open-world free-roam map.
##
## Pieces come from models/furniture.glb (StageArchStart, StageArchFinish, StageTapeBarrier, StageChevronLeft,
## StageChevronRight, StageWarningSign) and models/town.glb (SpectatorStand, SpectatorCheer, SpectatorWave
## driven by shaders/spectator.gdshader).
extends RefCounted

const FURNITURE := preload("res://scripts/ui/trackside_furniture.gd")
const WORLD_ASSETS := preload("res://scripts/ui/world_assets.gd")
const SPECTATOR_SHADER := preload("res://shaders/spectator.gdshader")
const TOWN_MODELS := "res://models/town.glb"

const ARCH_LEG_X := 5.6 ## half-span between arch leg centres in furniture.glb
const TAPE_LEN := 3.0 ## m: length of one StageTapeBarrier section
const TAPE_CHUNK := 320.0
const SPEC_CHUNK := 320.0
const SIGN_RANGE := 380.0
const TAPE_RANGE := 260.0
const SPEC_RANGE := 220.0
const ARCH_RANGE := 650.0
const MAX_TAPE_SECTIONS := 240 ## per-stage cap (720 m of tape) so 27 km Goliath stays lean
const SPEC_CAP_BY_QUALITY := [180, 320, 480, 600] ## sensible per-stage spectator cap by quality preset

## Natural spectator jacket/shirt colours (sRGB hex, matching festival_dressing.gd)
const SHIRT_COLORS := [
	"#e52521", "#ff6a1a", "#ffb703", "#00b4d8", "#7a3cff", "#e6197b", "#2a9d8f", "#f4f1ea",
	"#1d3557", "#2b2d42", "#e76f51", "#457b9d", "#52b788", "#d62828", "#f77f00", "#6c757d",
]

## Oświęcim memorial-side exclusion: keep race dressing & crowds clear of the southwest memorial approach
## (Auschwitz I lies ~(-1001, +902) in Oświęcim track coordinates; Rondo Solidarności is at ~1011 m from it).
const OSWIECIM_MEMORIAL := Vector2(-1001.0, 902.0)
const OSWIECIM_EXCLUDE_R := 1200.0

static var _spectator_meshes := {} ## pose name -> [Mesh, local Transform3D]

var world: Node3D
var track: Track
var root: Node3D
var spectator_mat: ShaderMaterial
var _lookup := {}
var _block_cells := {} ## Vector2i (32 m) -> Array[PackedVector2Array] (world XZ footprints of buildings/landmarks)
var _water_cells := {} ## Vector2i (64 m) -> Array[PackedVector2Array] (track XZ water polygons)
var _river_cells := {} ## Vector2i (64 m) -> Array[Array] ([a: Vector2, b: Vector2, half_w: float])

var _built_span := Vector3(-1.0, -1.0, -1.0) ## (from, to, is_partial 0/1) last built
var stats := {}
var placements := {} ## part name -> Array[Vector3] (world positions) for headless verification
var arch_legs: Array[Vector3] = [] ## world positions of arch leg bases for clearance verification
var spectator_positions := PackedVector3Array() ## world positions of every placed spectator


static func should_dress(tr: Track) -> bool:
	return tr != null and tr.cfg != null and tr.cfg.street_stage


static func spectator_meshes() -> Dictionary:
	if _spectator_meshes.is_empty():
		var scene: Node = WORLD_ASSETS._load_model(TOWN_MODELS)
		if scene:
			for nm in ["SpectatorStand", "SpectatorCheer", "SpectatorWave"]:
				for mi in scene.find_children(nm, "MeshInstance3D", true, false):
					var m := mi as MeshInstance3D
					if m.mesh:
						_spectator_meshes[nm] = [m.mesh, _local_of(m, scene)]
						break
			scene.free()
	return _spectator_meshes


static func _local_of(node: Node3D, stop_at: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != stop_at:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _h(x: float, y: float, salt: float) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
	return v - floorf(v)


static func _col_lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


static func _facing(dir: Vector3) -> Basis:
	var z := Vector3(dir.x, 0.0, dir.z)
	if z.length_squared() < 1e-6:
		return Basis.IDENTITY
	z = z.normalized()
	return Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)


func build(w: Node3D) -> void:
	world = w
	track = w.track
	stats.clear()
	placements.clear()
	arch_legs.clear()
	spectator_positions.clear()
	_built_span = Vector3(-1.0, -1.0, -1.0)
	if not should_dress(track) or not world.track_root:
		return
	_lookup = world._track_lookup(24.0)
	_index_obstacles()
	var span := _default_span()
	_rebuild(span.x, span.y, span.z > 0.5)


## Rebuilds the dressing if a race specifies a rally stage span different from the default build
## (e.g. a split rally stage on Bielsko or Bór). No-op for circuits or unchanged spans.
func configure_race(race: Race) -> void:
	if not should_dress(track) or not world or not world.track_root:
		return
	var span := _span_for_race(race)
	if absf(span.x - _built_span.x) < 0.5 and absf(span.y - _built_span.y) < 0.5 and absf(span.z - _built_span.z) < 0.5:
		return
	_rebuild(span.x, span.y, span.z > 0.5)


## Drives the animated spectator shader each frame (3 uniform writes on one shared ShaderMaterial).
func update(car_pos: Vector3, car_vel: Vector3, night: float) -> void:
	if spectator_mat == null:
		return
	spectator_mat.set_shader_parameter("car_pos", car_pos)
	spectator_mat.set_shader_parameter("car_vel", car_vel)
	spectator_mat.set_shader_parameter("night", night)


func _default_span() -> Vector3:
	if track.cfg.point_to_point:
		var b: Array = Rally.baked_span(track.key)
		if b.size() == 2:
			return Vector3(track.wrap_s(float(b[0])), track.wrap_s(float(b[1])), 1.0)
	return Vector3(0.0, 0.0, 0.0)


func _span_for_race(race: Race) -> Vector3:
	if race != null and race.s != null and race.s.mode == "rally":
		var a := track.wrap_s(race.s.stage_from)
		var b := track.wrap_s(race.s.stage_to)
		var partial := absf(track.rel(b - a)) > 40.0
		return Vector3(a, b, 1.0 if partial else 0.0)
	return _default_span()


func _rebuild(span_from: float, span_to: float, is_partial: bool) -> void:
	if is_instance_valid(root):
		root.free()
	root = Node3D.new()
	root.name = "StageDressing"
	world.track_root.add_child(root)

	if spectator_mat == null:
		spectator_mat = ShaderMaterial.new()
		spectator_mat.shader = SPECTATOR_SHADER
		if world.get("_night_materials") is Array:
			world._night_materials.append(spectator_mat)

	stats = {"arches": 0, "chevrons": 0, "warnings": 0, "tape": 0, "spectators": 0, "pockets": 0}
	placements = {}
	arch_legs.clear()
	spectator_positions = PackedVector3Array()
	_built_span = Vector3(span_from, span_to, 1.0 if is_partial else 0.0)

	var span_len := track.L
	if is_partial:
		span_len = (span_to - span_from) if span_to > span_from else (span_to + track.L - span_from)

	var pn := PaceNotes.new(track)
	var arch_s: Array[float] = []
	_build_arches(span_from, span_to, is_partial, arch_s)
	var corner_pockets := _build_corner_dressing(pn, span_from, span_len, is_partial, arch_s)
	_build_spectators(span_from, span_to, span_len, is_partial, corner_pockets)


# --------------------------------------------------------------------------------------------- obstacle indexing

func _index_obstacles() -> void:
	_block_cells.clear()
	_water_cells.clear()
	_river_cells.clear()
	var blocks: Array = world._block_occluders if world.get("_block_occluders") is Array else []
	for entry in blocks:
		if not (entry is Array) or entry.size() < 3:
			continue
		var bottom: float = float(entry[2])
		# Overhead bridge decks set bottom = top - 1.3 (well above ground); buildings, landmarks and abutments use -INF
		if bottom > 1.5:
			continue
		var poly: PackedVector2Array = entry[0]
		if poly.size() < 3:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		var x0 := floori((lo.x - 2.0) / 32.0)
		var x1 := floori((hi.x + 2.0) / 32.0)
		var z0 := floori((lo.y - 2.0) / 32.0)
		var z1 := floori((hi.y + 2.0) / 32.0)
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var ck := Vector2i(cx, cz)
				if not _block_cells.has(ck):
					_block_cells[ck] = []
				(_block_cells[ck] as Array).append(poly)
	if world.surroundings and world.surroundings.env is Dictionary:
		var env: Dictionary = world.surroundings.env
		for ring in env.get("water", []):
			var poly := PackedVector2Array()
			for k in range(0, ring.size() - 1, 2):
				poly.append(Vector2(float(ring[k]), float(ring[k + 1])))
			if poly.size() < 3:
				continue
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for p in poly:
				lo = lo.min(p)
				hi = hi.max(p)
			for cx in range(floori((lo.x - 2.0) / 64.0), floori((hi.x + 2.0) / 64.0) + 1):
				for cz in range(floori((lo.y - 2.0) / 64.0), floori((hi.y + 2.0) / 64.0) + 1):
					var ck := Vector2i(cx, cz)
					if not _water_cells.has(ck):
						_water_cells[ck] = []
					(_water_cells[ck] as Array).append(poly)
		for river in env.get("rivers", []):
			if not (river is Array) or river.size() < 5:
				continue
			var hw := float(river[0]) * 0.5 + 1.5
			for k in range(1, river.size() - 3, 2):
				var a := Vector2(float(river[k]), float(river[k + 1]))
				var b := Vector2(float(river[k + 2]), float(river[k + 3]))
				var lo := a.min(b) - Vector2(hw, hw)
				var hi := a.max(b) + Vector2(hw, hw)
				var seg := [a, b, hw]
				for cx in range(floori(lo.x / 64.0), floori(hi.x / 64.0) + 1):
					for cz in range(floori(lo.y / 64.0), floori(hi.y / 64.0) + 1):
						var ck := Vector2i(cx, cz)
						if not _river_cells.has(ck):
							_river_cells[ck] = []
						(_river_cells[ck] as Array).append(seg)


static func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside


static func _dist_sq_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-8:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


func _hits_building(world_xz: Vector2, margin: float) -> bool:
	var ck := Vector2i(floori(world_xz.x / 32.0), floori(world_xz.y / 32.0))
	var list: Array = _block_cells.get(ck, [])
	if list.is_empty():
		return false
	var m2 := margin * margin
	for poly: PackedVector2Array in list:
		if _point_in_poly(world_xz, poly):
			return true
		if margin > 0.0:
			var n := poly.size()
			for i in n:
				if _dist_sq_seg(world_xz, poly[i], poly[(i + 1) % n]) < m2:
					return true
	return false


func _in_water(track_xz: Vector2, margin: float) -> bool:
	var ck := Vector2i(floori(track_xz.x / 64.0), floori(track_xz.y / 64.0))
	var polys: Array = _water_cells.get(ck, [])
	var m2 := margin * margin
	for poly: PackedVector2Array in polys:
		if _point_in_poly(track_xz, poly):
			return true
		if margin > 0.0:
			var n := poly.size()
			for i in n:
				if _dist_sq_seg(track_xz, poly[i], poly[(i + 1) % n]) < m2:
					return true
	var segs: Array = _river_cells.get(ck, [])
	for seg in segs:
		var r := float(seg[2]) + margin
		if _dist_sq_seg(track_xz, seg[0] as Vector2, seg[1] as Vector2) < r * r:
			return true
	return false


func _excluded_zone(tx: float, tz: float) -> bool:
	if track.cfg.key == "oswiecim":
		return Vector2(tx, tz).distance_to(OSWIECIM_MEMORIAL) < OSWIECIM_EXCLUDE_R
	return false


# --------------------------------------------------------------------------------------------- track helpers

func _ground(tx: float, tz: float) -> float:
	if world.surroundings:
		return world.surroundings.ground_height(tx, tz)
	return world._ground_at(tx, tz)


func _road_surface_y(s: float, d: float) -> float:
	return world._road_y(s) - world.ROAD_REF + track.bank_rise(s, d)


func _tangent(s: float) -> Vector3:
	var h := track.heading(s)
	return Vector3(cos(h), 0.0, sin(h))


func _in_tunnel(s: float, margin: float) -> bool:
	for span in world._tunnel_spans():
		if world._in_span(s, span, margin):
			return true
	return false


func _in_active_span(s: float, span_from: float, span_len: float, is_partial: bool) -> bool:
	if not is_partial:
		return true
	return track.wrap_s(s - span_from) <= span_len + 25.0


func _on_cobbles(s: float) -> bool:
	var ws := track.wrap_s(s)
	for z in track.cfg.cobbles:
		if ws >= z.x and ws <= z.y:
			return true
	return false


func _near_any_s(s: float, list: Array[float], min_gap: float) -> bool:
	for q in list:
		if absf(track.rel(s - q)) < min_gap:
			return true
	return false


## Full spatial safety check for a roadside point at (tx, tz) beside track station s:
## clear of track surface + runoff, clear of buildings/landmarks, dry, outside tunnels and excluded zones,
## and ground close enough to road height (never floating off a viaduct or down in a deep ravine).
func _spot_ok(s: float, d: float, tx: float, tz: float, track_clear: float, bld_margin: float, max_dy: float) -> bool:
	if _excluded_zone(tx, tz):
		return false
	if _in_tunnel(s, 18.0):
		return false
	if not world._clear_of_track(_lookup, tx, tz, track_clear):
		return false
	var c: Vector2 = world.world_center
	var wx: float = tx - c.x
	var wz: float = tz - c.y
	if _hits_building(Vector2(wx, wz), bld_margin):
		return false
	if _in_water(Vector2(tx, tz), 0.6):
		return false
	var gy := _ground(tx, tz)
	var ry := _road_surface_y(s, d)
	if absf(gy - ry) > max_dy:
		return false
	return true


# --------------------------------------------------------------------------------------------- arches

func _build_arches(span_from: float, span_to: float, is_partial: bool, arch_s: Array[float]) -> void:
	var start_xfs: Array[Transform3D] = []
	var finish_xfs: Array[Transform3D] = []
	var xf_start := _place_arch(span_from)
	if not xf_start.is_empty():
		start_xfs.append(xf_start.xf)
		arch_s.append(float(xf_start.s))
		arch_legs.append(xf_start.leg_l)
		arch_legs.append(xf_start.leg_r)
	if is_partial:
		var xf_fin := _place_arch(span_to)
		if not xf_fin.is_empty():
			finish_xfs.append(xf_fin.xf)
			arch_s.append(float(xf_fin.s))
			arch_legs.append(xf_fin.leg_l)
			arch_legs.append(xf_fin.leg_r)
	_add_furniture("StageArchStart", start_xfs, ARCH_RANGE, true)
	_add_furniture("StageArchFinish", finish_xfs, ARCH_RANGE, true)
	stats["arches"] = start_xfs.size() + finish_xfs.size()


func _place_arch(target_s: float) -> Dictionary:
	var edge := track.half + track.cfg.runoff
	var wc: Vector2 = world.world_center
	# Try exact station first, then tiny shifts along the road and slight leg-margin tightening if a building sits tight
	for shift: float in [0.0, -3.0, 3.0, -6.0, 6.0]:
		var s := track.wrap_s(target_s + shift)
		if _in_tunnel(s, 18.0):
			continue
		var c := track.pos(s, 0.0)
		if _excluded_zone(c[0], c[1]):
			continue
		for extra: float in [1.15, 0.85, 0.65]:
			var leg_half: float = edge + extra
			var pl := track.pos(s, -leg_half)
			var pr := track.pos(s, leg_half)
			if not world._clear_of_track(_lookup, pl[0], pl[1], edge + 0.45):
				continue
			if not world._clear_of_track(_lookup, pr[0], pr[1], edge + 0.45):
				continue
			var wl := Vector2(pl[0] - wc.x, pl[1] - wc.y)
			var wr := Vector2(pr[0] - wc.x, pr[1] - wc.y)
			if _hits_building(wl, 0.55) or _hits_building(wr, 0.55):
				continue
			if _in_water(Vector2(pl[0], pl[1]), 0.3) or _in_water(Vector2(pr[0], pr[1]), 0.3):
				continue
			var ry := _road_surface_y(s, 0.0)
			var gl := _ground(pl[0], pl[1])
			var gr := _ground(pr[0], pr[1])
			var base_y := minf(gl, gr)
			if track.cfg.viaduct and ry - base_y > 1.2:
				base_y = ry - 0.15
			elif absf(gl - ry) > 2.6 or absf(gr - ry) > 2.6:
				continue
			else:
				base_y = maxf(base_y, ry - 0.45)
			var scale_x := clampf(leg_half / ARCH_LEG_X, 0.9, 1.8)
			var basis := _facing(-_tangent(s)).scaled_local(Vector3(scale_x, 1.0, 1.0))
			var origin := Vector3(c[0] - wc.x, base_y, c[1] - wc.y)
			return {
				"xf": Transform3D(basis, origin),
				"s": s,
				"leg_l": Vector3(wl.x, base_y, wl.y),
				"leg_r": Vector3(wr.x, base_y, wr.y),
			}
	return {}


# --------------------------------------------------------------------------------------------- corners: tape, chevrons, warnings

## Places chevron boards, warning boards, and barrier tape purely from PaceNotes grades/caution/crests.
## Returns ranked spectator pocket candidates [{s, side, score, length}] for _build_spectators.
func _build_corner_dressing(pn: PaceNotes, span_from: float, span_len: float, is_partial: bool, arch_s: Array[float]) -> Array:
	var chev_l: Array[Transform3D] = []
	var chev_r: Array[Transform3D] = []
	var warnings: Array[Transform3D] = []
	var tapes: Array[Transform3D] = []
	var warned_s: Array[float] = []
	var chev_s: Array[float] = []
	var pockets: Array = []

	var edge := track.half + track.cfg.runoff

	# 1. Start and finish tape runs flanking the viewing zones
	var end_anchors: Array[float] = [span_from]
	if is_partial:
		end_anchors.append(track.wrap_s(span_from + span_len))
	for anchor_s in end_anchors:
		for side in [-1.0, 1.0]:
			for k in range(-2, 4):
				if tapes.size() >= MAX_TAPE_SECTIONS:
					break
				var st := track.wrap_s(anchor_s + (float(k) + 0.5) * TAPE_LEN)
				if absf(track.rel(st - anchor_s)) < 2.2:
					continue # leave breathing room right around the arch leg
				var xf := _try_tape(st, side, edge)
				if xf != Transform3D.IDENTITY:
					tapes.append(xf)

	# 2. PaceNotes-driven corner dressing (no corner-name matching anywhere!)
	for note in pn.notes:
		var apex: float = float(note.apex)
		if not _in_active_span(apex, span_from, span_len, is_partial):
			continue
		var grade: String = String(note.grade)
		var dir: int = int(note.dir) # +1 right, -1 left, 0 crest
		var caution: bool = bool(note.caution)
		var mods: Array = note.mods
		var link: String = String(note.link)
		var outside_side: float = -float(dir) if dir != 0 else 1.0
		var clen := clampf(track.wrap_s(float(note.e) - float(note.s)), 12.0, 160.0)

		# 2a. Warning boards before hazards: caution corners, crests, hairpins, or "into" chicanes
		var is_hazard := caution or dir == 0 or mods.has("over crest") or grade == "hairpin" or link == "into"
		if is_hazard:
			var s_warn := track.wrap_s(float(note.s) - 45.0)
			if _in_active_span(s_warn, span_from, span_len, is_partial) and not _near_any_s(s_warn, warned_s, 60.0) and not _near_any_s(s_warn, arch_s, 22.0):
				var wxf := _try_sign(s_warn, outside_side, edge, 0.0)
				if wxf == Transform3D.IDENTITY:
					wxf = _try_sign(s_warn, -outside_side, edge, 0.0)
				if wxf != Transform3D.IDENTITY:
					warned_s.append(s_warn)
					warnings.append(wxf)

		if dir == 0:
			continue

		# 2b. Chevron boards on the outside of tight corners (hairpin, square, tight, or sharp/caution medium)
		var wants_chevron := grade in ["hairpin", "square", "tight"] or (grade == "medium" and (caution or float(note.radius) <= 44.0))
		if wants_chevron:
			var offsets: Array = [-14.0, 0.0, 12.0] if grade in ["hairpin", "square"] else [-10.0, 4.0]
			for ds: float in offsets:
				var sc := track.wrap_s(apex + ds)
				if _near_any_s(sc, chev_s, 9.0) or _near_any_s(sc, arch_s, 18.0):
					continue
				# Angle slightly toward the road so headlights catch the chevron face cleanly
				var yaw_in := outside_side * 0.18
				var cxf := _try_sign(sc, outside_side, edge, yaw_in)
				if cxf != Transform3D.IDENTITY:
					chev_s.append(sc)
					if dir > 0:
						chev_r.append(cxf)
					else:
						chev_l.append(cxf)

		# 2c. Barrier tape along the outside of medium/tight/square/hairpin bends (and caution/chicane easy bends)
		var wants_tape := grade in ["hairpin", "square", "tight", "medium"] or (grade == "easy" and (caution or link == "into"))
		if wants_tape and tapes.size() < MAX_TAPE_SECTIONS:
			var run_len := minf(clen + 12.0, 54.0)
			var half_run := run_len * 0.5
			var n_segs := maxi(2, mini(18, int(roundf(run_len / TAPE_LEN))))
			for k in n_segs:
				if tapes.size() >= MAX_TAPE_SECTIONS:
					break
				var st := track.wrap_s(apex - half_run + (float(k) + 0.5) * TAPE_LEN)
				if _near_any_s(st, arch_s, 10.0):
					continue
				var txf := _try_tape(st, outside_side, edge)
				if txf != Transform3D.IDENTITY:
					tapes.append(txf)

		# 2d. Score this corner as a spectator viewing zone (purely from PaceNotes + cobbles track data)
		var score := 0.0
		match grade:
			"hairpin": score = 5.0
			"square": score = 4.0
			"tight": score = 3.5
			"medium": score = 2.0
			"easy": score = 1.0
		if score > 0.0:
			if link == "into":
				score += 1.2
			if caution:
				score += 0.8
			if _on_cobbles(apex):
				score += 2.0
			pockets.append({"s": apex, "side": outside_side, "score": score, "length": clampf(clen, 12.0, 26.0)})

	# 3. Cobblestone town squares (from track.cfg.cobbles, pure track data) get a dedicated viewing pocket
	for z in track.cfg.cobbles:
		var mid := track.wrap_s((z.x + z.y) * 0.5)
		if _in_active_span(mid, span_from, span_len, is_partial):
			pockets.append({"s": mid, "side": 1.0, "score": 5.5, "length": clampf(z.y - z.x, 14.0, 28.0)})

	_add_furniture("StageChevronLeft", chev_l, SIGN_RANGE, false)
	_add_furniture("StageChevronRight", chev_r, SIGN_RANGE, false)
	_add_furniture("StageWarningSign", warnings, SIGN_RANGE, false)
	_add_chunked_furniture("StageTapeBarrier", tapes, TAPE_CHUNK, TAPE_RANGE)

	stats["chevrons"] = chev_l.size() + chev_r.size()
	stats["warnings"] = warnings.size()
	stats["tape"] = tapes.size()
	return pockets


func _try_sign(s: float, side: float, edge: float, yaw_bias: float) -> Transform3D:
	var wc: Vector2 = world.world_center
	for extra: float in [1.35, 1.0]:
		var d: float = side * (edge + extra)
		var p := track.pos(s, d)
		if not _spot_ok(s, d, p[0], p[1], edge + 0.85, 0.65, 2.2):
			continue
		var gy := _ground(p[0], p[1])
		var ry := _road_surface_y(s, d)
		var y := maxf(gy, ry - 0.30) - 0.04
		var pos := Vector3(p[0] - wc.x, y, p[1] - wc.y)
		var basis := _facing(-_tangent(s)) * Basis(Vector3.UP, yaw_bias)
		return Transform3D(basis, pos)
	return Transform3D.IDENTITY


func _try_tape(s: float, side: float, edge: float) -> Transform3D:
	var wc: Vector2 = world.world_center
	for extra: float in [1.75, 1.25]:
		var d: float = side * (edge + extra)
		var p := track.pos(s, d)
		if not _spot_ok(s, d, p[0], p[1], edge + 0.85, 0.55, 2.0):
			continue
		# Check both ends of the 3.0 m section stay clear of track & buildings
		var along := _tangent(s)
		var half_v := Vector2(along.x, along.z) * (TAPE_LEN * 0.48)
		var ea := Vector2(p[0], p[1]) - half_v
		var eb := Vector2(p[0], p[1]) + half_v
		if not world._clear_of_track(_lookup, ea.x, ea.y, edge + 0.75) or not world._clear_of_track(_lookup, eb.x, eb.y, edge + 0.75):
			continue
		if _hits_building(ea - wc, 0.35) or _hits_building(eb - wc, 0.35):
			continue
		var gy := _ground(p[0], p[1])
		var ry := _road_surface_y(s, d)
		var y := maxf(gy, ry - 0.25) - 0.03
		var pos := Vector3(p[0] - wc.x, y, p[1] - wc.y)
		var perp := along.cross(Vector3.UP).normalized()
		return Transform3D(Basis(along, Vector3.UP, perp), pos)
	return Transform3D.IDENTITY


# --------------------------------------------------------------------------------------------- spectators

func _build_spectators(span_from: float, span_to: float, span_len: float, is_partial: bool, corner_pockets: Array) -> void:
	var cap: int = SPEC_CAP_BY_QUALITY[clampi(world.quality, 0, SPEC_CAP_BY_QUALITY.size() - 1)]
	var xfs := [[], [], []] ## Stand, Cheer, Wave
	var custom := [[], [], []]
	var total := 0
	var pocket_count := 0
	var used_s: Array[float] = []

	# 1. Start-line crowd pockets (both sides behind the tape)
	for side in [-1.0, 1.0]:
		var added := _place_spectator_pocket(span_from + 6.0, side, 16.0, 2, cap - total, xfs, custom, 11.0 + side)
		if added > 0:
			total += added
			pocket_count += 1
	used_s.append(span_from)

	# 2. Finish-line crowd pockets for point-to-point / split rally stages
	if is_partial and total < cap:
		for side in [-1.0, 1.0]:
			var added := _place_spectator_pocket(span_to - 4.0, side, 14.0, 2, cap - total, xfs, custom, 23.0 + side)
			if added > 0:
				total += added
				pocket_count += 1
		used_s.append(span_to)

	# 3. Best corners & town squares, ranked by score (PaceNotes + cobbles), well-spaced
	corner_pockets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) > float(b.score)
		return float(a.s) < float(b.s))

	var min_pocket_gap := clampf(span_len / 18.0, 95.0, 220.0)
	for pk in corner_pockets:
		if total >= cap:
			break
		var s: float = float(pk.s)
		if _near_any_s(s, used_s, min_pocket_gap):
			continue
		var side: float = float(pk.side)
		var rows := 3 if float(pk.score) >= 4.5 else 2
		var want_len: float = float(pk.length)
		var added := _place_spectator_pocket(s, side, want_len, rows, mini(34, cap - total), xfs, custom, 41.0 + s * 0.01)
		if added == 0:
			# If the outside is a cliff, water or tight building wall, try the inside bank
			added = _place_spectator_pocket(s, -side, want_len, rows, mini(28, cap - total), xfs, custom, 73.0 + s * 0.01)
		if added > 0:
			total += added
			pocket_count += 1
			used_s.append(s)

	# 4. Fallback along the active span if a track is mostly fast/viaduct (so street stages never look totally empty)
	if total < mini(36, cap):
		var steps := 8
		for k in steps:
			if total >= cap:
				break
			var s := track.wrap_s(span_from + (float(k) + 0.5) * span_len / float(steps))
			if _near_any_s(s, used_s, 90.0):
				continue
			for side in [1.0, -1.0]:
				var added := _place_spectator_pocket(s, side, 12.0, 2, mini(20, cap - total), xfs, custom, 97.0 + float(k))
				if added > 0:
					total += added
					pocket_count += 1
					used_s.append(s)
					break

	_commit_spectators(xfs, custom)
	stats["spectators"] = total
	stats["pockets"] = pocket_count


func _place_spectator_pocket(center_s: float, side: float, length: float, rows: int, budget: int,
		xfs: Array, custom: Array, salt: float) -> int:
	if budget <= 0:
		return 0
	var edge := track.half + track.cfg.runoff
	# Spectators stand strictly behind the barrier/tape (>= edge + 2.35 m from centreline)
	var base_d := edge + 2.45
	var placed := 0
	var half_l := length * 0.5
	for r in rows:
		if placed >= budget:
			break
		var depth := base_d + float(r) * 0.72
		var along := -half_l + (0.38 if r % 2 == 1 else 0.0)
		while along <= half_l and placed < budget:
			var s := track.wrap_s(center_s + along)
			var js := (_h(s, float(r), 3.1 + salt) - 0.5) * 0.28
			var jd := (_h(s, float(r), 7.7 + salt) - 0.5) * 0.18
			var d := side * (depth + jd)
			var p := track.pos(track.wrap_s(s + js), d)
			if _spot_ok(s, d, p[0], p[1], edge + 1.65, 0.55, 1.8):
				var gy := _ground(p[0], p[1])
				var wc: Vector2 = world.world_center
				var wx: float = p[0] - wc.x
				var wz: float = p[1] - wc.y
				# Face the road centreline at s
				var road_p := track.pos(s, 0.0)
				var face := Vector2(road_p[0] - p[0], road_p[1] - p[1])
				var dir := face.normalized() if face.length_squared() > 1e-6 else Vector2(0.0, -1.0)
				var yaw := atan2(-dir.x, -dir.y) + (_h(p[0], p[1], 5.1 + salt) - 0.5) * 0.40
				var pr := _h(p[0], p[1], 1.7 + salt)
				var pose := 0 if pr < 0.28 else (1 if pr < 0.68 else 2)
				var col_idx := int(floorf(_h(p[0] * 1.37, p[1] * 1.91, 2.9 + salt) * float(SHIRT_COLORS.size()))) % SHIRT_COLORS.size()
				var col := _col_lin(SHIRT_COLORS[col_idx])
				var seed_v := clampf(_h(p[0] * 1.73, p[1] * 1.29, 8.3 + salt), 0.01, 0.99)
				var origin := Vector3(wx, gy, wz)
				(xfs[pose] as Array).append(Transform3D(Basis(Vector3.UP, yaw), origin))
				(custom[pose] as Array).append(Color(col.r, col.g, col.b, seed_v))
				spectator_positions.append(origin)
				placed += 1
			along += 0.78 + _h(s, float(r), 6.2 + salt) * 0.30
	return placed


func _commit_spectators(xfs: Array, custom: Array) -> void:
	var smeshes := spectator_meshes()
	var pose_keys := ["SpectatorStand", "SpectatorCheer", "SpectatorWave"]
	var node_names := ["SpectatorsStand", "SpectatorsCheer", "SpectatorsWave"]
	for p_i in 3:
		var list: Array = xfs[p_i]
		if list.is_empty():
			continue
		var entry: Array = smeshes.get(pose_keys[p_i], [])
		var mesh: Mesh
		var local := Transform3D.IDENTITY
		if not entry.is_empty():
			mesh = entry[0]
			local = entry[1]
		else:
			var box := BoxMesh.new()
			box.size = Vector3(0.45, 1.72, 0.28)
			mesh = box
		var cust: Array = custom[p_i]
		var cells := {}
		for i in list.size():
			var xf: Transform3D = (list[i] as Transform3D) * local
			var ck := Vector2i(floori(xf.origin.x / SPEC_CHUNK), floori(xf.origin.z / SPEC_CHUNK))
			if not cells.has(ck):
				cells[ck] = [[], []]
			(cells[ck][0] as Array).append(xf)
			(cells[ck][1] as Array).append(cust[i])
		var ci := 0
		for ck in cells:
			var cxfs: Array = cells[ck][0]
			var ccust: Array = cells[ck][1]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = false
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = cxfs.size()
			for k in cxfs.size():
				mm.set_instance_transform(k, cxfs[k])
				mm.set_instance_custom_data(k, ccust[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = node_names[p_i] if ci == 0 else "%s_%d" % [node_names[p_i], ci]
			mmi.multimesh = mm
			mmi.material_override = spectator_mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.extra_cull_margin = 2.0
			mmi.visibility_range_end = SPEC_RANGE
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			root.add_child(mmi)
			ci += 1


# --------------------------------------------------------------------------------------------- furniture MultiMesh helpers

func _add_furniture(part: String, xfs: Array[Transform3D], range_end: float, shadows: bool) -> void:
	var m: Dictionary = FURNITURE.meshes()
	if xfs.is_empty() or not m.has(part):
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m[part]
	mm.instance_count = xfs.size()
	var origins: Array[Vector3] = []
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		origins.append(xfs[i].origin)
	placements[part] = origins
	var inst := MultiMeshInstance3D.new()
	inst.name = part
	inst.multimesh = mm
	inst.visibility_range_end = range_end
	inst.visibility_range_end_margin = 30.0
	inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)


func _add_chunked_furniture(part: String, xfs: Array[Transform3D], cell_size: float, range_end: float) -> void:
	var m: Dictionary = FURNITURE.meshes()
	if xfs.is_empty() or not m.has(part):
		return
	var origins: Array[Vector3] = []
	var cells := {}
	for xf in xfs:
		origins.append(xf.origin)
		var ck := Vector2i(floori(xf.origin.x / cell_size), floori(xf.origin.z / cell_size))
		if not cells.has(ck):
			cells[ck] = [] as Array[Transform3D]
		(cells[ck] as Array[Transform3D]).append(xf)
	placements[part] = origins
	var ci := 0
	for ck in cells:
		var cxfs: Array[Transform3D] = cells[ck]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m[part]
		mm.instance_count = cxfs.size()
		for i in cxfs.size():
			mm.set_instance_transform(i, cxfs[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = part if ci == 0 else "%s_%d" % [part, ci]
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.visibility_range_end = range_end
		inst.visibility_range_end_margin = 20.0
		inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(inst)
		ci += 1
