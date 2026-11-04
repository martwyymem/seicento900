## Idle life for Pszczyna's wisent herd (surroundings.gd builds it where a track's env has a "herd": the
## enclosure outline from tools/build_street_tracks.py extra_landmarks). Each standing animal grazes on the
## spot for a while, then turns and ambles to a new patch within `roam` metres of where it was placed, never
## closer than EDGE_KEEP to the fence; a calf keeps near a cow; every animal breathes, the lying ones too.
## Each keeps the round footprint of its body clear of the others' and of the props in the enclosure (the hay
## rack): it only picks a patch it can stand on and walk to in a straight line, and stops to graze when a step
## would take it into another animal. Visual only: nothing in the race reads it.
extends Node3D

const WALK_SPEED := {"WisentBull": 0.45, "WisentCow": 0.38, "WisentCalf": 0.75} ## m/s, an amble
const TURN_RATE := 0.7 ## rad/s
const EDGE_KEEP := 3.0 ## m inside the fence
const GRAZE_TIME := Vector2(7.0, 26.0) ## seconds on one patch (random between)
const STRIDE := 1.6 ## m per step cycle: the body's rise and roll while walking
const BODY := {"WisentBull": 1.82, "WisentCow": 1.53, "WisentCowLying": 1.57, "WisentCalf": 0.91, "HayRack": 2.12} ## m: footprint radius (wisents.glb) when the node has no mesh to measure
const SPACE := 0.3 ## m two animals keep between their footprints
const CALF_ROOM := 1.2 ## m a calf may stray past that from its mother

var _ring := PackedVector2Array() ## the enclosure, track metres
var _roam := 10.0
var _ground: Callable ## (x, y) in track metres -> ground height
var _center := Vector2.ZERO ## the world's centre (track metres at world origin)
var _animals: Array[Dictionary] = []
var _blocks: Array[Vector3] = [] ## props the herd walks round: (x, y) in track metres, footprint radius
var _t := 0.0

## ring: the fence outline (track metres); animals: [{node: MeshInstance3D, part: String, at: Vector2 (track
## metres), rot: float (its Y rotation)}]; blocks: props inside the fence, (x, y, footprint radius) in track metres.
func setup(ring: PackedVector2Array, roam: float, ground: Callable, center: Vector2, animals: Array,
		blocks: Array[Vector3] = []) -> void:
	_ring = ring
	_roam = roam
	_ground = ground
	_center = center
	_blocks = blocks
	for k in animals.size():
		var a: Dictionary = animals[k]
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (k + 1) + int(a.at.x * 13.0) + int(a.at.y * 7.0)
		var part: String = a.part
		_animals.append({
			"node": a.node, "part": part, "home": a.at, "pos": a.at, "target": a.at, "rot": a.rot,
			"walking": false, "timer": rng.randf_range(0.0, GRAZE_TIME.y), "rng": rng, "stride": 0.0,
			"phase": rng.randf() * TAU, "lying": part == "WisentCowLying",
			"speed": float(WALK_SPEED.get(part, 0.4)) * rng.randf_range(0.85, 1.15),
			"r": footprint(a.node, part),
		})
	# each calf keeps near the nearest standing cow (its mother)
	for a in _animals:
		if a.part != "WisentCalf":
			continue
		var best := INF
		for b in _animals:
			if b.part == "WisentCow" and (b.home as Vector2).distance_to(a.home) < best:
				best = (b.home as Vector2).distance_to(a.home)
				a["mother"] = b
	set_process(not _animals.is_empty())

## Radius of the circle round a model's footprint, as surroundings.gd places it (unscaled).
static func footprint(node: MeshInstance3D, part: String) -> float:
	if node and node.mesh:
		var box := node.mesh.get_aabb()
		return 0.5 * Vector2(box.size.x, box.size.z).length()
	return float(BODY.get(part, 1.5))

## Whether track point p is inside the enclosure with EDGE_KEEP to spare.
func grazeable(p: Vector2) -> bool:
	if _ring.size() < 3 or not Geometry2D.is_point_in_polygon(p, _ring):
		return false
	for i in _ring.size():
		var q := Geometry2D.get_closest_point_to_segment(p, _ring[i], _ring[(i + 1) % _ring.size()])
		if q.distance_to(p) < EDGE_KEEP:
			return false
	return true

## Whether animal a can walk straight to p and stand there: clear of the props and the lying animals all the
## way, and of where the others stand or are heading.
func _room(a: Dictionary, p: Vector2) -> bool:
	if not grazeable(p):
		return false
	var from: Vector2 = a.pos
	for b in _blocks:
		var o := Vector2(b.x, b.y)
		if Geometry2D.get_closest_point_to_segment(o, from, p).distance_to(o) < float(a.r) + b.z:
			return false
	for b in _animals:
		if is_same(b, a):
			continue
		var gap: float = a.r + b.r + SPACE
		if b.lying:
			if Geometry2D.get_closest_point_to_segment(b.pos, from, p).distance_to(b.pos) < gap:
				return false
		elif p.distance_to(b.pos) < gap or (b.walking and p.distance_to(b.target) < gap):
			return false
	return true

## Whether a step to nxt would take animal a into another animal or a prop (closer than they touch).
func _bumps(a: Dictionary, nxt: Vector2) -> bool:
	var at: Vector2 = a.pos
	for b in _blocks:
		var o := Vector2(b.x, b.y)
		var d := nxt.distance_to(o)
		if d < float(a.r) + b.z and d < at.distance_to(o):
			return true
	for b in _animals:
		if is_same(b, a):
			continue
		var d := nxt.distance_to(b.pos)
		if d < float(a.r) + float(b.r) + SPACE and d < at.distance_to(b.pos):
			return true
	return false

func _pick_target(a: Dictionary) -> Vector2:
	var rng: RandomNumberGenerator = a.rng
	var centre: Vector2 = a.home
	var reach := _roam
	if a.has("mother"):
		centre = a.mother.pos
		reach = float(a.mother.r) + float(a.r) + SPACE + CALF_ROOM
	for attempt in 12:
		var p := centre + Vector2.from_angle(rng.randf() * TAU) * reach * sqrt(rng.randf())
		if p.distance_to(a.pos) > 1.0 and _room(a, p):
			return p
	return a.pos

func _process(delta: float) -> void:
	_t += delta
	for a in _animals:
		var node: MeshInstance3D = a.node
		if not is_instance_valid(node):
			continue
		var bob := 0.0
		var roll := 0.0
		if not a.lying:
			a.timer -= delta
			if not a.walking and a.timer <= 0.0:
				a.target = _pick_target(a)
				a.walking = (a.target as Vector2).distance_to(a.pos) > 0.5
				a.timer = (a.rng as RandomNumberGenerator).randf_range(GRAZE_TIME.x, GRAZE_TIME.y)
			if a.walking:
				var to: Vector2 = a.target - a.pos
				var dist := to.length()
				if dist < 0.3:
					a.walking = false
				else:
					# the model faces +x: Basis(UP, rot) points it along (cos rot, -sin rot) in track x, y
					var want := atan2(-to.y, to.x)
					var diff := wrapf(want - a.rot, -PI, PI)
					a.rot += clampf(diff, -TURN_RATE * delta, TURN_RATE * delta)
					var go := float(a.speed) * maxf(0.0, cos(diff)) * minf(1.0, dist / 0.8) * delta
					var nxt: Vector2 = a.pos + Vector2(cos(a.rot), -sin(a.rot)) * go
					if _bumps(a, nxt):
						# someone is in the way: graze here a little, then find another patch
						a.walking = false
						a.timer = (a.rng as RandomNumberGenerator).randf_range(2.0, 6.0)
					else:
						a.pos = nxt
						a.stride += go / STRIDE * TAU
						bob = 0.025 * absf(sin(a.stride))
						roll = 0.02 * sin(a.stride)
		var p: Vector2 = a.pos
		var y: float = _ground.call(p.x, p.y)
		var breathe := 1.0 + 0.012 * sin(_t * (1.1 if a.lying else 1.5) + a.phase)
		var basis := Basis(Vector3.UP, a.rot) * Basis(Vector3.RIGHT, roll) * Basis.from_scale(Vector3(1.0, breathe, 1.0))
		node.transform = Transform3D(basis, Vector3(p.x - _center.x, y + bob, p.y - _center.y))
