## Ambient traffic for the open world: cars that drive the town's real road graph in their lane and get shoved when
## the player hits them. They live only round the player: spawned out of sight ahead, dropped when far behind. Near
## misses are reported for the skill score.
##
## Each car has a driver of its own (pace, how hard it pulls away and brakes, how close it follows, how slow it takes
## corners, how quickly it reacts). Speed comes from the Intelligent Driver Model: it eases up behind the car ahead
## (or the player), slows in time for the bends and the turn it has already picked, and gives way at junctions (to the
## bigger road, to the right on equal roads, to oncoming cars when turning left, to anything already in the junction).
## The drawn car steers towards a point ahead on its lane instead of being pinned to the polyline, so it takes corners
## in arcs and slides between lanes at a junction; it pitches under braking, leans in bends, lights its brake lamps
## and signals its turns.
class_name Traffic
extends RefCounted

const MAX_CARS := 34
const SPAWN_MIN := 140.0
const SPAWN_MAX := 420.0
const DESPAWN := 560.0
const CAR_MASS := 1150.0
const RADIUS := 0.95 ## each car is two circles this big, 1.1 m either side of its middle
const RAIL_LOOK := 70.0 ## m: how far ahead a driver watches for a closed crossing or the train
const RAIL_BRAKE := 4.5 ## m/s²: how hard they brake for one
const KINDS := ["CarHatch", "CarSedan", "CarVan", "Maluch"]
const KIND_WEIGHTS := [0.45, 0.32, 0.14, 0.09] ## hatches and saloons mostly, the odd van, a Maluch now and then
## Vans are mostly fleet white and silver; a Maluch wears the colours they were sold in (cream, mustard, sky blue,
## olive, the red and white); the rest draw from TownBuilder.CAR_PAINTS.
const VAN_PAINTS := ["#f5f5f5", "#f5f5f5", "#eceff1", "#b0bec5", "#9e9e9e", "#1e3a5f", "#c62828"]
const MALUCH_PAINTS := ["#e8dcb5", "#d4a017", "#87a9c9", "#6b7d3a", "#b71c1c", "#f2f2ee", "#c9773c", "#3f5e8c"]
const CAR_LEN := 4.2 ## m, centre-to-centre gap that means bumpers touch
const SENSE_DT := 0.12 ## s between a driver's looks round (the steps between are dead reckoning)
const LOOK_AHEAD := [4.0, 9.0, 16.0, 26.0, 38.0, 52.0] ## m: where the driver checks the road's curvature
const JUNCTION_LOOK := 45.0 ## m before the junction a driver starts to think about giving way
const ROLL_SPEED := 3.5 ## m/s: a give-way approach with nothing coming still slows to this
const STOP_LIGHT := 0.4 ## m/s: below this the brake lamps stay on (held on the foot brake)

var map: TownMap
var root: Node3D
var builder: TownBuilder
var cars: Array = [] ## dictionaries, see _spawn
var near_misses: Array = [] ## [relative speed m/s] since the reader last emptied it
var hits: Array = [] ## [[x, y, speed]]
var _rng := RandomNumberGenerator.new()
var _paint_cache := {}
var _spawn_t := 0.0
var _t := 0.0
var _edges := [] ## [from node, edge] usable by traffic
var monster := false ## CarMods' Monster Truck: every traffic car stands on giant wheels
static var _tyre_mesh: CylinderMesh
static var _brake_mat: StandardMaterial3D
static var _blink_mesh: BoxMesh

func _init(town: TownMap, parent: Node3D, b: TownBuilder) -> void:
	map = town
	root = parent
	builder = b
	_rng.seed = 2026
	for nid in map.node_edges:
		for e in map.node_edges[nid]:
			if e[5] and map.road_rank[e[1]] >= 3 and float(e[4]) > 20.0:
				_edges.append([nid, e])

## Advances every car by dt and handles their contact with the player's car.
func step(dt: float, player: FreeCar) -> void:
	_t += dt
	map.signal_t += dt
	var pp := Vector2(player.car.x, player.car.y)
	_spawn_t -= dt
	if _spawn_t <= 0.0 and cars.size() < MAX_CARS:
		_spawn_t = 0.25
		_try_spawn(pp, player)
	var i := cars.size() - 1
	while i >= 0:
		var c: Dictionary = cars[i]
		if (c.pos as Vector2).distance_to(pp) > DESPAWN:
			c.gone = true
			(c.node as Node3D).queue_free()
			cars.remove_at(i)
		i -= 1
	for c in cars:
		_drive(c, dt, player)
		if not map.trains.is_empty():
			_train_contact(c)
	_contact(player)

func clear() -> void:
	for c in cars:
		c.gone = true
		(c.node as Node3D).queue_free()
	cars.clear()

func _try_spawn(pp: Vector2, player: FreeCar) -> void:
	if _edges.is_empty():
		return
	# a random edge with a point at a spawnable distance (a few tries)
	for attempt in 12:
		var pick: Array = _edges[_rng.randi() % _edges.size()]
		var e: Array = pick[1]
		var pts := _edge_points(e)
		var s := _rng.randf() * _poly_len(pts)
		var at := _point_on(pts, s)
		var d := (at[0] as Vector2).distance_to(pp)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		var clear_ok := true
		for c in cars:
			if (c.pos as Vector2).distance_to(at[0]) < 25.0:
				clear_ok = false
				break
		if not clear_ok:
			continue
		_spawn(pick[0], e, pts, s)
		return

func _edge_points(e: Array) -> PackedVector2Array:
	var pts := map.road_pts[e[1]]
	var out := PackedVector2Array()
	var i0: int = e[2]
	var i1: int = e[3]
	var step_i := 1 if i1 >= i0 else -1
	var i := i0
	while true:
		out.append(pts[i])
		if i == i1:
			break
		i += step_i
	return out

static func _poly_len(pts: PackedVector2Array) -> float:
	var l := 0.0
	for k in pts.size() - 1:
		l += pts[k].distance_to(pts[k + 1])
	return l

## [position, direction, point index, fraction] at arc length s along a polyline.
static func _point_on(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for k in pts.size() - 1:
		var l := pts[k].distance_to(pts[k + 1])
		if acc + l >= s or k == pts.size() - 2:
			var t := clampf((s - acc) / maxf(l, 1e-4), 0.0, 1.0)
			return [pts[k].lerp(pts[k + 1], t), (pts[k + 1] - pts[k]).normalized(), k, t]
		acc += l
	return [pts[0], Vector2.RIGHT, 0, 0.0]

## A driver: pace against the limit, pull-away and comfortable braking (m/s²), time gap (s), standstill gap (m),
## the sideways acceleration they take bends at (m/s²) and how long they take to move off once the way is clear (s).
## Maluch drivers are old and gentle, vans heavy, the odd hatch in a hurry.
func _driver(kind: String) -> Dictionary:
	var r := _rng
	var d := {"f": r.randf_range(0.82, 1.08), "a": r.randf_range(1.3, 2.4), "b": r.randf_range(2.0, 3.2),
		"T": r.randf_range(0.9, 1.8), "s0": r.randf_range(1.8, 3.2), "lat": r.randf_range(2.2, 3.6),
		"react": r.randf_range(0.35, 1.1), "cap": 40.0, "wob": r.randf() * TAU, "wob_f": r.randf_range(0.05, 0.12)}
	match kind:
		"Maluch":
			d.f = r.randf_range(0.7, 0.92)
			d.a = r.randf_range(0.8, 1.3)
			d.T = r.randf_range(1.4, 2.2)
			d.lat = r.randf_range(1.8, 2.6)
			d.cap = 27.0 # ~100 km/h flat out
		"CarVan":
			d.f = r.randf_range(0.78, 1.0)
			d.a = r.randf_range(1.0, 1.7)
			d.b = r.randf_range(1.8, 2.7) # heavy: brakes earlier and gentler
			d.T = r.randf_range(1.2, 2.0)
			d.lat = r.randf_range(1.9, 2.8)
			d.cap = 31.0 # ~110 km/h loaded
	if r.randf() < (0.12 if kind != "Maluch" else 0.03): # in a hurry
		d.f = r.randf_range(1.08, 1.22)
		d.a = r.randf_range(2.2, 3.0) if kind != "Maluch" else d.a * 1.15 # a Maluch has no more to give
		d.T = r.randf_range(0.6, 1.0)
		d.react = r.randf_range(0.2, 0.45)
	return d

func _spawn(from_node: String, e: Array, pts: PackedVector2Array, s: float) -> void:
	var kind: String = KINDS[TownBuilder._pick_index(KIND_WEIGHTS, _rng.randf())]
	var node := _car_node(kind, _paint_for(kind))
	root.add_child(node)
	var drv := _driver(kind)
	var c := {"node": node, "from": from_node, "edge": e, "pts": pts, "len": _poly_len(pts), "s": s, "i0": int(e[2]),
		"istep": 1 if int(e[3]) >= int(e[2]) else -1, "v": 0.0, "want": 0.0, "pos": Vector2.ZERO,
		"dir": Vector2.RIGHT, "heading": 0.0, "knock": 0.0, "push": Vector2.ZERO, "spin": 0.0, "near": false,
		"kind": kind, "y": 0.0, "drv": drv}
	_bind_parts(c)
	c.want = _want_on(c, int(e[1]))
	c.v = c.want * 0.8
	_choose_next(c)
	c.sense_t = _rng.randf() * SENSE_DT
	_sense(c, null)
	# start no faster than the bend or the car ahead allows
	c.v = minf(float(c.v), _safe_speed(c))
	_place(c)
	cars.append(c)

## A paint colour for a car of this kind (see VAN_PAINTS, MALUCH_PAINTS).
func _paint_for(kind: String) -> Color:
	var pal: Array = VAN_PAINTS if kind == "CarVan" else (MALUCH_PAINTS if kind == "Maluch" else TownBuilder.CAR_PAINTS)
	return Color(pal[_rng.randi() % pal.size()])

## Dev menu: a parked car `gap` metres ahead of the player, along the way the player faces (it stays until it is knocked off).
func spawn_ahead(player: FreeCar, kind: String, gap := 22.0) -> void:
	var dir := Vector2(cos(player.car.heading), sin(player.car.heading))
	var start := Vector2(player.car.x, player.car.y) + dir * gap
	var pts := PackedVector2Array([start, start + dir * 60.0])
	var ri: int = int(player.road.road) if not player.road.is_empty() else 0
	var node := _car_node(kind, _paint_for(kind))
	root.add_child(node)
	var c := {"node": node, "from": "", "edge": ["", ri], "pts": pts, "len": 60.0, "s": 0.0,
		"v": 0.0, "want": 0.0, "pos": Vector2.ZERO, "dir": dir, "heading": 0.0, "knock": 0.0, "push": Vector2.ZERO,
		"spin": 0.0, "near": false, "kind": kind, "y": player.z, "parked": true}
	_bind_parts(c)
	_place(c)
	cars.append(c)

## Cruising speed on a road for this driver (m/s).
func _want_on(c: Dictionary, ri: int) -> float:
	var drv: Dictionary = c.get("drv", {})
	var f: float = drv.get("f", 0.75 + _rng.randf() * 0.25)
	return minf(map.road_limit[ri] / 3.6 * f, float(drv.get("cap", 40.0)))

func _car_node(kind: String, paint: Color) -> Node3D:
	var node := Node3D.new()
	var mesh_xf := builder._model(kind, TownBuilder._fallback_car.bind(kind))
	var inst := MeshInstance3D.new()
	inst.name = "Body"
	inst.mesh = mesh_xf[0]
	inst.transform = mesh_xf[1]
	var mesh: Mesh = mesh_xf[0]
	var key := paint.to_html()
	if not _paint_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = paint
		m.metallic = 0.4
		m.roughness = 0.3
		m.clearcoat_enabled = true
		_paint_cache[key] = m
	var painted := false
	for i in mesh.get_surface_count():
		var sm := mesh.surface_get_material(i)
		if sm and sm.resource_name == "Paint":
			inst.set_surface_override_material(i, _paint_cache[key])
			painted = true
	if not painted:
		inst.material_override = _paint_cache[key]
	node.add_child(inst)
	_add_blinkers(node, inst)
	if monster:
		_add_monster_wheels(node, inst)
	return node

## Finds the drawn parts a car animates: its tail lamps (brake lights) and its two sets of indicators.
func _bind_parts(c: Dictionary) -> void:
	var node: Node3D = c.node
	var inst := node.get_node_or_null("Body") as MeshInstance3D
	var tails := PackedInt32Array()
	if inst and inst.mesh and inst.material_override == null:
		for i in inst.mesh.get_surface_count():
			var sm := inst.mesh.surface_get_material(i)
			if sm and sm.resource_name == "Taillight":
				tails.append(i)
	c.body = inst
	c.tails = tails
	c.blink_l = node.get_node_or_null("BlinkL")
	c.blink_r = node.get_node_or_null("BlinkR")

## Amber lamps at the four corners, hidden until the car signals (local -z is the front, +x the right).
func _add_blinkers(node: Node3D, inst: MeshInstance3D) -> void:
	if _blink_mesh == null:
		_blink_mesh = BoxMesh.new()
		_blink_mesh.size = Vector3(0.13, 0.08, 0.06)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.55, 0.05)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.05)
		m.emission_energy_multiplier = 4.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blink_mesh.material = m
	var box := inst.transform * inst.mesh.get_aabb()
	var cx := box.get_center().x
	var hx := box.size.x * 0.5 - 0.08
	var y := box.position.y + box.size.y * 0.36
	for side: float in [-1.0, 1.0]:
		var g := Node3D.new()
		g.name = "BlinkR" if side > 0.0 else "BlinkL"
		g.visible = false
		for z: float in [box.position.z + 0.02, box.end.z - 0.02]:
			var b := MeshInstance3D.new()
			b.mesh = _blink_mesh
			b.position = Vector3(cx + side * hx, y, z)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.add_child(b)
		node.add_child(g)

## Switches the giant wheels on or off; the cars on the road go and new ones spawn in the new style.
func set_monster(on: bool) -> void:
	if on != monster:
		monster = on
		clear()

## Four big tyres at the corners of the car's mesh, the body lifted over them.
func _add_monster_wheels(node: Node3D, inst: MeshInstance3D) -> void:
	if _tyre_mesh == null:
		_tyre_mesh = CylinderMesh.new()
		_tyre_mesh.top_radius = 0.62
		_tyre_mesh.bottom_radius = 0.62
		_tyre_mesh.height = 0.5
		_tyre_mesh.radial_segments = 16
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.06, 0.06, 0.065)
		m.roughness = 0.9
		_tyre_mesh.material = m
	var box := inst.transform * inst.mesh.get_aabb()
	var lift := _tyre_mesh.top_radius * 1.35
	inst.position.y += lift
	for k in node.get_child_count():
		var g := node.get_child(k) as Node3D
		if g and g.name.begins_with("Blink"):
			g.position.y += lift
	var hx := box.size.x * 0.5 + 0.15
	var hz := box.size.z * 0.5 * 0.68
	var cx := box.get_center().x
	var cz := box.get_center().z
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var t := MeshInstance3D.new()
			t.mesh = _tyre_mesh
			t.position = Vector3(cx + sx * hx, _tyre_mesh.top_radius, cz + sz * hz)
			t.rotation.z = PI / 2.0
			node.add_child(t)

## Lateral offset of the lane (right of travel on a two-way road; the middle of a one-way one).
func _lane(ri: int) -> float:
	if map.road_oneway[ri]:
		return map.road_w[ri] * (0.22 if map.road_lanes[ri] >= 2 else 0.0)
	return map.road_w[ri] * 0.25

## Height of a car on its own road: the deck of the road it drives (never the nearest layer in height), so a car
## on a bridge stays on the deck and one underneath stays on the ground. Cars with no road index (the dev menu's
## parked ones) keep to the layer they were first put on.
func _layer_y(c: Dictionary, at: Array, p: Vector2) -> float:
	var ri: int = c.edge[1]
	var g := map.ground(p.x, p.y)
	if c.has("i0"):
		var z := map.road_z[ri]
		if z.is_empty():
			return g + map.road_lift(ri)
		var ia: int = clampi(int(c.i0) + int(at[2]) * int(c.istep), 0, z.size() - 1)
		var ib: int = clampi(ia + int(c.istep), 0, z.size() - 1)
		return g + lerpf(z[ia], z[ib], float(at[3])) + map.road_lift(ri)
	var y_ref: float = float(c.get("y", 0.0))
	var hit := map.road_at(p.x, p.y, y_ref if y_ref != 0.0 else -INF, 1.0)
	return float(hit.height) if not hit.is_empty() else g + map.pave_top_at(p.x, p.y)

## [lane position, direction] `d` metres on from the car's place: along its edge, then on into the edge it has picked
## for the junction. The lane drifts a few centimetres side to side as a driver's hands do.
func _lane_at(c: Dictionary, d: float) -> Array:
	var s: float = float(c.s) + d
	var pts: PackedVector2Array = c.pts
	var ri: int = c.edge[1]
	var nxt: Array = c.get("next", [])
	if s > float(c.len) and not nxt.is_empty():
		pts = c.next_pts
		s -= float(c.len)
		ri = nxt[1]
	var at := _point_on(pts, s)
	var dir: Vector2 = at[1]
	var off := (_lane(ri) if c.has("i0") else 0.0) + float(c.get("dodge_now", 0.0))
	var drv: Dictionary = c.get("drv", {})
	if not drv.is_empty():
		off += sin(_t * TAU * float(drv.wob_f) + float(drv.wob)) * 0.14
	return [(at[0] as Vector2) + Vector2(-dir.y, dir.x) * off, dir, at]

## Puts the car where it drives. With dt (while driving) the drawn car steers for a point ahead on its lane and is
## pulled gently back onto it, so it arcs through bends and junctions; without (spawning, tests) it sits on the lane.
func _place(c: Dictionary, dt := 0.0) -> void:
	var here := _lane_at(c, 0.0)
	var target: Vector2 = here[0]
	var dir: Vector2 = here[1]
	var at: Array = here[2]
	c.dir = dir
	var v: float = float(c.get("v", 0.0))
	var base: Vector2
	var yaw: float
	if dt <= 0.0 or not c.has("base") or c.has("parked"):
		base = target
		yaw = atan2(dir.y, dir.x)
	else:
		base = c.base
		yaw = c.yaw
		var look_d := clampf(3.0 + v * 0.4, 3.5, 11.0)
		var look: Vector2 = _lane_at(c, look_d)[0]
		var aim := look - base
		if aim.length_squared() > 0.01 and v > 0.05:
			var max_rate := v / 3.2 + 0.2 # rad/s: nothing turns tighter than a 3.2 m circle
			var err := wrapf(aim.angle() - yaw, -PI, PI)
			yaw += clampf(err * (1.0 - exp(-dt * 5.0)), -max_rate * dt, max_rate * dt) # a hand on the wheel, not a snap
		base += Vector2(cos(yaw), sin(yaw)) * v * dt
		base = base.lerp(target, 1.0 - exp(-dt * 2.2 * clampf(v / 2.5, 0.0, 1.0))) # no crabbing at a standstill
		var off := base - target
		if off.length() > 3.0 and v > 0.5:
			base = base.move_toward(target + off.limit_length(3.0), 3.0 * dt)
		var prev_yaw: float = c.yaw
		var rate := wrapf(yaw - prev_yaw, -PI, PI) / dt
		c.lat = lerpf(float(c.get("lat", 0.0)), v * rate, 1.0 - exp(-dt * 4.0))
	c.base = base
	c.yaw = yaw
	var p: Vector2 = base + (c.push as Vector2)
	c.pos = p
	var h := yaw + float(c.spin)
	c.heading = h
	var y := _layer_y(c, at, p)
	c.y = y
	var node: Node3D = c.node
	node.position = Vector3(p.x, y, p.y)
	# nose dips under braking and lifts pulling away, the body leans out of the bend
	var pitch := clampf(float(c.get("acc", 0.0)) * 0.0055, -0.035, 0.018)
	var roll := clampf(float(c.get("lat", 0.0)) * 0.009, -0.045, 0.045)
	node.basis = Basis(Vector3.UP, -h - PI / 2.0) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)

## Picks the way out of the junction at the end of this edge (any way but back, if there is one), early, so the
## driver can slow for it, signal and give way.
func _choose_next(c: Dictionary) -> void:
	var e: Array = c.edge
	var at_node: String = e[0]
	var options := []
	for n in map.node_edges.get(at_node, []):
		if n[5] and n[0] != c.get("from", "") and map.road_rank[n[1]] >= 2:
			options.append(n)
	if options.is_empty():
		for n in map.node_edges.get(at_node, []):
			if n[5]:
				options.append(n)
	if options.is_empty():
		c.next = []
		c.next_pts = PackedVector2Array()
		c.turn = 0.0
		return
	# prefer carrying straight on a bigger road
	var pts_here: PackedVector2Array = c.pts
	var cur_dir := (pts_here[pts_here.size() - 1] - pts_here[maxi(0, pts_here.size() - 2)]).normalized()
	var best: Array = options[0]
	var best_pts := PackedVector2Array()
	var best_score := -INF
	for n in options:
		var pts := _edge_points(n)
		var d := (pts[mini(1, pts.size() - 1)] - pts[0]).normalized()
		var score := d.dot(cur_dir) * 1.2 + map.road_rank[n[1]] * 0.15 + _rng.randf() * 1.4
		if score > best_score:
			best_score = score
			best = n
			best_pts = pts
	c.next = best
	c.next_pts = best_pts
	c.next_len = _poly_len(best_pts)
	var nd := (best_pts[mini(1, best_pts.size() - 1)] - best_pts[0]).normalized()
	c.turn = cur_dir.angle_to(nd) # + right, - left (the lane is on the + side)

## Fills in what a car built elsewhere (tests, older saves of the dictionary) lacks.
func _ensure(c: Dictionary) -> void:
	if not c.has("drv"):
		c.drv = _driver(String(c.get("kind", "CarHatch")))
	if not c.has("next") and c.has("i0"):
		_choose_next(c)
	if not c.has("sense_t"):
		c.sense_t = 0.0

func _drive(c: Dictionary, dt: float, player: FreeCar) -> void:
	if c.has("parked"):
		_place(c)
		return
	_ensure(c)
	var v: float = c.v
	if c.knock > 0.0:
		# shoved: slide to a stop, then carry on
		c.knock -= dt
		c.v = maxf(0.0, v - 8.0 * dt)
		c.acc = -8.0
		c.push = (c.push as Vector2) * maxf(0.0, 1.0 - dt * 0.5)
		c.spin = float(c.spin) * maxf(0.0, 1.0 - dt * 0.8)
		c.s += c.v * dt
		_advance(c)
		_place(c, dt)
		_lamps(c)
		return
	c.push = (c.push as Vector2).move_toward(Vector2.ZERO, dt * 0.8)
	c.spin = move_toward(float(c.spin), 0.0, dt * 0.6)
	var dg: float = c.get("dodge", 0.0)
	var dn: float = c.get("dodge_now", 0.0)
	if dg != dn:
		c.dodge_now = move_toward(dn, dg, dt * (0.25 + float(c.v) * 0.3))
	c.sense_t -= dt
	if c.sense_t <= 0.0:
		c.sense_t += SENSE_DT
		_sense(c, player)
	var cmd := _accel(c, player)
	var drv: Dictionary = c.drv
	# moving off: a moment to notice the way is clear
	if v < 0.3 and cmd > 0.3:
		c.react_t = float(c.get("react_t", drv.react)) - dt
		if c.react_t > 0.0:
			cmd = 0.0
	elif v >= 0.3:
		c.react_t = drv.react
	# feet move smoothly on the pedals, except in a fright
	var acc: float = c.get("acc", 0.0)
	if cmd < -4.5:
		acc = minf(acc, cmd)
	acc = move_toward(acc, cmd, 9.0 * dt)
	c.acc = acc
	c.v = maxf(0.0, v + acc * dt)
	if float(c.v) < 0.05 and acc < 0.0:
		c.v = 0.0
	c.s += c.v * dt
	_advance(c)
	_place(c, dt)
	_lamps(c)

## The highest speed that still lets the car stop for what it saw in its last look (bends, the car ahead, a line).
func _safe_speed(c: Dictionary) -> float:
	var v := float(c.want)
	for k in c.get("bends", []):
		var d: float = float(k[0]) - float(c.s)
		v = minf(v, sqrt(float(k[1]) * float(k[1]) + 2.0 * 2.5 * maxf(d, 0.0)))
	return v

## Intelligent Driver Model acceleration (m/s²) towards the driver's pace, behind the car ahead, for the bends seen in
## the last look and for a give-way line.
func _accel(c: Dictionary, player: FreeCar) -> float:
	var drv: Dictionary = c.drv
	var v: float = c.v
	var v0: float = maxf(float(c.want), 0.1)
	if absf(float(c.get("dodge_now", 0.0))) > 0.2 or float(c.get("dodge", 0.0)) != 0.0:
		v0 = minf(v0, 6.0) # edging round something
	var a: float = drv.a
	var b: float = drv.b
	var free := a * (1.0 - pow(v / v0, 4.0))
	var acc := free
	# the car ahead, or the player
	var gap := INF
	var lv := 0.0
	var lead: Variant = c.get("lead")
	var room := 0.0 # stop well back from something odd in the road, to have room to steer round it
	if lead is Dictionary:
		var o: Dictionary = lead
		if not o.has("gone"):
			gap = (o.pos as Vector2).distance_to(c.pos) - CAR_LEN
			lv = float(o.v) * maxf(0.0, Vector2(cos(float(o.heading)), sin(float(o.heading))).dot(c.dir))
			if o.has("parked") or float(o.knock) > 0.0:
				room = 3.0
	elif lead is String and player != null:
		var pp := Vector2(player.car.x, player.car.y)
		gap = pp.distance_to(c.pos) - CAR_LEN
		lv = maxf(0.0, Vector2(player.car.vx, player.car.vy).dot(c.dir))
		if lv < 1.0:
			room = 3.0
	# a closed level crossing or the train across the lane: a stop short of it, like a car standing there
	var rail: float = c.get("rail", INF)
	if rail < INF:
		var rg := rail - 2.5 - float(c.s)
		if rg < gap:
			gap = maxf(rg, 0.0)
			lv = 0.0
	# so does a red light's stop line
	var sig: float = c.get("sig", INF)
	if sig < INF:
		var sg := sig - 2.5 - float(c.s)
		if sg < gap:
			gap = maxf(sg, 0.0)
			lv = 0.0
	# a give-way line counts as a car stopped on it
	var line: float = c.get("line", INF)
	if line < INF:
		var lg := line - float(c.s)
		if lg < gap:
			gap = lg
			lv = 0.0
	if gap < INF:
		var s_star := float(drv.s0) + room + maxf(0.0, v * float(drv.T) + v * (v - lv) / (2.0 * sqrt(a * b)))
		acc = minf(acc, free - a * pow(s_star / maxf(gap, 0.3), 2.0))
		if gap < 0.5:
			acc = minf(acc, -6.0)
	# the bends ahead: brake so as to arrive at each one at its speed
	for k in c.get("bends", []):
		var vc: float = k[1]
		var d: float = float(k[0]) - float(c.s)
		if v <= vc or d < -3.0:
			continue
		acc = minf(acc, (vc * vc - v * v) / (2.0 * maxf(d, 1.5)))
	return clampf(acc, -8.0, a)

## A driver's look round: the bends of the road ahead (and the turn it will take), what it follows, whether it must
## give way at the junction, and which way it signals.
func _sense(c: Dictionary, player: FreeCar) -> void:
	var drv: Dictionary = c.drv
	var s: float = c.s
	var len_e: float = c.len
	var nxt: Array = c.get("next", [])
	var reach := len_e - s + (float(c.next_len) if not nxt.is_empty() else 0.0)
	# bends: a corner's speed from how far the road turns over 10 m round each point
	var bends := []
	var lat: float = drv.lat
	for d: float in LOOK_AHEAD:
		if d > reach:
			break
		var d0 := _lane_at(c, maxf(0.0, d - 5.0))
		var d1 := _lane_at(c, minf(d + 5.0, reach))
		var ang := absf((d0[1] as Vector2).angle_to(d1[1]))
		if ang < 0.05:
			continue
		var r := 10.0 / ang
		bends.append([s + d, sqrt(lat * r)])
	if nxt.is_empty() and c.has("i0"):
		bends.append([len_e - 2.0, 0.0]) # a dead end: stop at it
	c.bends = bends
	c.lead = _find_lead(c, player)
	c.rail = _rail_ahead(c.pos, c.dir, float(c.y)) + s # as a place on this edge
	_signal(c)
	# waiting at a red light (or queued behind a car that is) isn't being stuck
	var lead_held: bool = c.lead is Dictionary and bool((c.lead as Dictionary).get("held", false))
	c.held = float(c.sig) < INF or lead_held
	c.stuck_t = float(c.get("stuck_t", 0.0)) + SENSE_DT if float(c.v) < 0.3 and c.lead != null and not c.held else 0.0
	if float(c.stuck_t) > 14.0 + float(drv.react) * 6.0 and _turn_back(c):
		return
	_go_round(c, player)
	_give_way(c, player)
	# signal a turn from 45 m out until the car is round it
	var turn: float = c.get("turn", 0.0)
	var blink := 0
	if len_e - s < 45.0 and absf(turn) > 0.4:
		blink = 1 if turn > 0.0 else -1
	elif float(c.get("blink_hold", 0.0)) > s:
		blink = int(c.get("blink", 0))
	var dg: float = c.get("dodge", 0.0)
	var dn: float = c.get("dodge_now", 0.0)
	if absf(dg - dn) > 0.3:
		blink = 1 if dg > dn else -1 # pulling out or back in
	c.blink = blink

## The nearest car (or the player) in front, in this lane: on the same edge or the one the driver has picked, or any
## car physically in the way (a crossing one, a shoved one, the player's car).
func _find_lead(c: Dictionary, player: FreeCar) -> Variant:
	var p: Vector2 = c.pos
	var dir: Vector2 = c.dir
	var side := Vector2(-dir.y, dir.x)
	var s: float = c.s
	var nxt: Array = c.get("next", [])
	var best := 60.0
	var lead: Variant = null
	var skip: Variant = c.get("dodge_of")
	for o in cars:
		if is_same(o, c) or is_same(o, skip):
			continue
		var along := INF
		if is_same(o.edge, c.edge):
			if float(o.s) > s:
				along = float(o.s) - s
		elif not nxt.is_empty() and is_same(o.edge, nxt):
			along = float(c.len) - s + float(o.s)
		if along == INF:
			var d: Vector2 = (o.pos as Vector2) - p
			if d.length_squared() > best * best:
				continue
			var ahead := d.dot(dir)
			if ahead <= 0.0:
				continue
			var odir := Vector2(cos(float(o.heading)), sin(float(o.heading)))
			var lat := absf(d.dot(side))
			var oncoming := odir.dot(dir) < -0.3
			var passing := float(c.get("dodge", 0.0)) != 0.0 or absf(float(o.get("dodge_now", 0.0))) > 0.3
			if float(o.v) < 1.0:
				passing = true # a stopped car is in the way whichever way it faces
			if lat < ((1.9 if passing else 1.1) if oncoming else 1.9 + ahead * 0.04):
				along = ahead
		if along < best:
			best = along
			lead = o
	if player != null and not (skip is String):
		var d := Vector2(player.car.x, player.car.y) - p
		var ahead := d.dot(dir)
		if ahead > 0.0 and ahead < best and absf(d.dot(side)) < 2.0 + ahead * 0.03:
			lead = "player"
	return lead

## Stuck behind something that is not going anywhere (the player's car, a parked or shoved one): after a moment's
## patience, and with nothing coming the other way, pull out into the other lane, creep past and tuck back in.
func _go_round(c: Dictionary, player: FreeCar) -> void:
	if not c.has("i0"):
		return
	var p: Vector2 = c.pos
	var dir: Vector2 = c.dir
	var obs: Variant = c.get("dodge_of")
	if obs != null:
		var op: Vector2
		if obs is String:
			op = Vector2(player.car.x, player.car.y) if player != null else p - dir * 100.0
		else:
			op = (obs as Dictionary).pos if not (obs as Dictionary).has("gone") else p - dir * 100.0
		var along := (op - p).dot(dir)
		c.dodge_still = float(c.get("dodge_still", 0.0)) + SENSE_DT if float(c.v) < 0.3 else 0.0
		if along < -6.0 or op.distance_to(p) > 40.0 or float(c.dodge_still) > 4.0 \
				or (along > 1.5 and _oncoming(c, 70.0)):
			# past it, or something coming before we are alongside: back into the lane
			c.dodge_of = null
			c.dodge = 0.0
			c.dodge_still = 0.0
			c.blocked = 0.0
		return
	var lead: Variant = c.get("lead")
	var stuck := false
	var lp := Vector2.ZERO
	if lead is String and player != null:
		lp = Vector2(player.car.x, player.car.y)
		stuck = Vector2(player.car.vx, player.car.vy).length() < 0.5
	elif lead is Dictionary:
		var o: Dictionary = lead
		lp = o.pos
		stuck = float(o.v) < 0.5 and (o.has("parked") or float(o.knock) > 0.0 or float(o.get("blocked", 0.0)) > 30.0)
	if not stuck or lp.distance_to(p) > 30.0:
		c.blocked = 0.0
		return
	c.blocked = float(c.get("blocked", 0.0)) + SENSE_DT
	# a parked car is passed straight away; the player's car gets a moment in case it moves off
	var patience := 0.0 if lead is Dictionary and (lead as Dictionary).has("parked") else 2.0 + float(c.drv.react) * 3.0
	if float(c.blocked) < patience or lp.distance_to(p) > 22.0 or _oncoming(c, 60.0):
		return
	var ri: int = c.edge[1]
	c.dodge_of = lead
	c.dodge = -maxf(2.5, map.road_w[ri] * 0.5)

## Gives up on a jam that is not moving: turns round on the spot onto the other side of the road (two-way roads
## only) and drives off the way it came. The drawn car swings round in a tight arc as it pulls away.
func _turn_back(c: Dictionary) -> bool:
	if not c.has("i0"):
		return false
	var e: Array = c.edge
	var back: Array = []
	for n in map.node_edges.get(e[0], []):
		if int(n[1]) == int(e[1]) and String(n[0]) == String(c.get("from", "")) and n[5] \
				and int(n[2]) == int(e[3]) and int(n[3]) == int(e[2]):
			back = n
			break
	if back.is_empty():
		c.stuck_t = 0.0
		return false
	var s_new := maxf(0.0, float(c.len) - float(c.s))
	c.from = e[0]
	c.edge = back
	c.pts = _edge_points(back)
	c.len = _poly_len(c.pts)
	c.s = minf(s_new, float(c.len))
	c.i0 = int(back[2])
	c.istep = 1 if int(back[3]) >= int(back[2]) else -1
	c.want = _want_on(c, int(back[1]))
	c.stuck_t = 0.0
	c.dodge_of = null
	c.dodge = 0.0
	c.dodge_now = 0.0
	c.blocked = 0.0
	_choose_next(c)
	c.lead = null
	c.bends = []
	c.line = INF
	c.blink = -1
	c.blink_hold = c.s + 6.0
	return true

## Whether a car is coming the other way in the lane a car would pull out into, within `reach` metres.
func _oncoming(c: Dictionary, reach: float) -> bool:
	var p: Vector2 = c.pos
	var dir: Vector2 = c.dir
	var side := Vector2(-dir.y, dir.x)
	for o in cars:
		if is_same(o, c):
			continue
		var d: Vector2 = (o.pos as Vector2) - p
		var ahead := d.dot(dir)
		var lat := d.dot(side)
		if ahead > -4.0 and ahead < reach and lat < 0.5 and lat > -6.0 \
				and Vector2(cos(float(o.heading)), sin(float(o.heading))).dot(dir) < -0.3:
			return true
	return false

## Junction rules: a line short of the junction the driver stops at while anyone with right of way is coming (or
## anyone is in the junction). The smaller road gives way to the bigger, on equal roads the car from the right goes
## first, a left turn waits for oncoming cars. A driver who has waited long enough edges out anyway, and one past the
## line keeps going.
func _give_way(c: Dictionary, player: FreeCar) -> void:
	c.line = INF
	var nxt: Array = c.get("next", [])
	if not c.has("i0"):
		return
	var s: float = c.s
	var len_e: float = c.len
	var to_node := len_e - s
	if to_node > JUNCTION_LOOK or nxt.is_empty():
		c.wait = 0.0
		return
	var node_id: String = c.edge[0]
	var incident: Array = map.node_edges.get(node_id, [])
	if incident.size() < 3:
		return
	var my_road: int = c.edge[1]
	var my_rank: int = map.road_rank[my_road]
	var top := 0
	var wide := 0.0
	for n in incident:
		if int(n[1]) != my_road:
			top = maxi(top, map.road_rank[n[1]])
			wide = maxf(wide, map.road_w[n[1]])
	var stop_at := len_e - (wide * 0.5 + 2.5)
	if s > stop_at - 0.5 and float(c.v) > 0.5:
		return # committed
	var minor := my_rank < top
	var turn: float = c.get("turn", 0.0)
	var left := turn < -0.4
	if not left and bool(c.get("sig_green", false)):
		c.wait = 0.0
		return # through on the green (turning left still gives way to oncoming cars)
	if not minor and not left and top < my_rank:
		return # the main road, straight on or turning right: right of way
	var npos: Vector2 = map.node_pos.get(node_id, c.pos)
	var dir: Vector2 = c.dir
	var right := Vector2(-dir.y, dir.x)
	var conflict := false
	for o in cars:
		if is_same(o, c) or is_same(o.edge, c.edge):
			continue
		if conflict:
			break
		var op: Vector2 = o.pos
		var od := op.distance_to(npos)
		if od > 50.0:
			continue
		if od < 6.5 and float(o.v) > 0.8 and String(o.get("from", "")) != node_id:
			conflict = true # someone crossing the junction (not one waiting at its line)
			continue
		if not o.has("i0") or String((o.edge as Array)[0]) != node_id:
			continue # not heading for this junction
		var eta := od / maxf(float(o.v), 0.5)
		if eta > 4.0:
			continue
		var o_rank: int = map.road_rank[int(o.edge[1])]
		var odir := Vector2(cos(float(o.heading)), sin(float(o.heading)))
		if o_rank > my_rank:
			conflict = true
		elif o_rank == my_rank and minor == false and int(o.edge[1]) == my_road and left and odir.dot(dir) < -0.5:
			conflict = true # oncoming while turning left
		elif o_rank == my_rank and (op - npos).dot(right) > 2.0 and odir.dot(dir) > -0.5:
			conflict = true # from the right on an equal road
	if not conflict and player != null:
		var pp := Vector2(player.car.x, player.car.y)
		var pd := pp.distance_to(npos)
		var pv := Vector2(player.car.vx, player.car.vy)
		if pd < 7.0 or (pd < 60.0 and pv.dot(npos - pp) > 0.0 and pd / maxf(pv.length(), 0.5) < 3.5):
			conflict = true
	if conflict:
		c.wait = float(c.get("wait", 0.0)) + SENSE_DT if float(c.v) < 0.5 else float(c.get("wait", 0.0))
		if float(c.wait) < 5.0 + float(c.drv.react) * 4.0:
			c.line = stop_at
			return
	else:
		c.wait = 0.0
	if minor:
		# nothing coming: still slow to look before pulling out
		c.bends.append([stop_at, ROLL_SPEED])

## The traffic signal ahead in the lane (TownMap.signal_heads). On red, and on amber while the driver can still stop
## in comfort, its stop line holds the car like a car standing on it; a car too close to stop goes on through. A
## green lets the car through the junction it guards without giving way.
func _signal(c: Dictionary) -> void:
	c.sig = INF
	c.sig_green = false
	var ahead := map.signal_ahead(c.pos, c.dir, JUNCTION_LOOK + 25.0)
	if ahead.is_empty():
		return
	var d: float = ahead[1]
	var st := TownMap.signal_state(ahead[0], map.signal_t)
	if st != TownMap.SIG_GREEN:
		var v: float = c.v
		var need := v * v / (2.0 * maxf(d - 2.5, 0.1)) # m/s² to stop at the line
		if need < (float(c.drv.b) * 1.2 if st == TownMap.SIG_AMBER else 7.0):
			c.sig = float(c.s) + d
		return
	var to_node := float(c.len) - float(c.s)
	c.sig_green = c.has("i0") and d <= to_node + 2.0 and to_node - d < TownMap.SIGNAL_JUNCTION + 10.0

## Brake lamps and indicators.
func _lamps(c: Dictionary) -> void:
	var on := float(c.get("acc", 0.0)) < -0.9 or float(c.v) < STOP_LIGHT
	if on != bool(c.get("braking", false)):
		c.braking = on
		var body: MeshInstance3D = c.get("body")
		if body:
			if _brake_mat == null:
				_brake_mat = StandardMaterial3D.new()
				_brake_mat.albedo_color = Color(0.9, 0.05, 0.03)
				_brake_mat.emission_enabled = true
				_brake_mat.emission = Color(1.0, 0.06, 0.03)
				_brake_mat.emission_energy_multiplier = 3.5
			for i: int in c.get("tails", PackedInt32Array()):
				body.set_surface_override_material(i, _brake_mat if on else null)
	var blink: int = c.get("blink", 0)
	var lit := blink != 0 and fmod(_t + float(c.drv.wob), 0.72) < 0.38
	var bl: Node3D = c.get("blink_l")
	var br: Node3D = c.get("blink_r")
	if bl:
		bl.visible = lit and blink < 0
	if br:
		br.visible = lit and blink > 0

## Distance along dir from p to the first closed crossing boom or train car across the way (INF if none in
## RAIL_LOOK). A boom counts as soon as its crossing closes (the lights go on), before it is down; a boom the car
## has already passed doesn't.
func _rail_ahead(p: Vector2, dir: Vector2, y: float) -> float:
	var tip := p + dir * RAIL_LOOK
	var best := INF
	for bm in map.booms:
		if not bm[2]:
			continue
		var a: Vector2 = bm[0]
		if a.distance_squared_to(p) > (RAIL_LOOK + 8.0) * (RAIL_LOOK + 8.0):
			continue
		var x: Variant = Geometry2D.segment_intersects_segment(p, tip, a, bm[1])
		if x != null:
			best = minf(best, ((x as Vector2) - p).dot(dir))
	for tc in map.trains:
		if tc == null or absf(float(tc[4]) - y) > 3.0 or (tc[0] as Vector2).distance_to(p) > RAIL_LOOK + float(tc[2]) + 4.0:
			continue
		var ring := _train_ring(tc, 0.6)
		for e in 4:
			var x: Variant = Geometry2D.segment_intersects_segment(p, tip, ring[e], ring[(e + 1) % 4])
			if x != null:
				best = minf(best, ((x as Vector2) - p).dot(dir))
	return best

## A train car's footprint grown by `grow` metres.
static func _train_ring(tc: Array, grow: float) -> PackedVector2Array:
	var c: Vector2 = tc[0]
	var f := Vector2.from_angle(float(tc[1]))
	var r := Vector2(-f.y, f.x)
	var hl: float = float(tc[2]) + grow
	var hw: float = float(tc[3]) + grow
	return PackedVector2Array([c + f * hl + r * hw, c + f * hl - r * hw, c - f * hl - r * hw, c - f * hl + r * hw])

## A traffic car caught by the train (it was on the crossing when it closed): shoved out of the way and knocked.
func _train_contact(c: Dictionary) -> void:
	var p: Vector2 = c.pos
	for tc in map.trains:
		if tc == null or absf(float(tc[4]) - float(c.y)) > 3.0:
			continue
		var tcen: Vector2 = tc[0]
		var f := Vector2.from_angle(float(tc[1]))
		var r := Vector2(-f.y, f.x)
		var dir := Vector2(cos(c.heading), sin(c.heading))
		for k: float in [-1.1, 1.1]:
			var q: Vector2 = p + dir * k
			var lq := q - tcen
			var ax := lq.dot(f)
			var ay := lq.dot(r)
			var ox := float(tc[2]) + RADIUS - absf(ax)
			var oy := float(tc[3]) + RADIUS - absf(ay)
			if ox <= 0.0 or oy <= 0.0:
				continue
			var tv: Vector2 = tc[5] if tc.size() > 5 else Vector2.ZERO
			var moving := tv.length() > 1.0
			# out through the nearer side; at a moving cab's front out sideways all the same (a train throws a car
			# off the line, it doesn't push it along ahead of itself)
			var n := r * (1.0 if ay >= 0.0 else -1.0)
			var depth := oy
			if ox < oy and not moving:
				n = f * (1.0 if ax >= 0.0 else -1.0)
				depth = ox
			c.push = (c.push as Vector2) + n * (depth + 0.05)
			if moving and float(c.knock) <= 0.0:
				c.knock = 3.0
				c.v = 0.0
				c.spin = float(c.spin) + (0.8 if n.cross(dir) >= 0.0 else -0.8)
				hits.append([q.x, q.y, tv.length()])
				if ox < oy:
					map.train_hit = maxf(map.train_hit, tv.length())
			break

## Onto the next edge at the end of this one (the way picked on the approach), then picks the one after.
func _advance(c: Dictionary) -> void:
	while c.s > float(c.len):
		var nxt: Array = c.get("next", [])
		if nxt.is_empty():
			if c.has("i0"):
				_choose_next(c)
				nxt = c.next
			if nxt.is_empty():
				c.s = float(c.len)
				c.v = 0.0
				return
		c.s -= float(c.len)
		c.from = c.edge[0]
		c.edge = nxt
		c.pts = c.next_pts
		c.len = c.next_len
		c.i0 = int(nxt[2])
		c.istep = 1 if int(nxt[3]) >= int(nxt[2]) else -1
		c.want = _want_on(c, int(nxt[1]))
		# keep signalling a few metres into the new road, then pick the next turn
		c.blink_hold = 8.0 if absf(float(c.get("turn", 0.0))) > 0.4 else 0.0
		_choose_next(c)
		c.line = INF
		c.rail = INF
		c.sig = INF
		c.wait = 0.0
		if c.has("drv"):
			_sense(c, null)
		c.sense_t = SENSE_DT

## Circle pairs against the player's box: push both apart, bounce the player, knock the traffic car.
func _contact(player: FreeCar) -> void:
	var car := player.car
	var pc := Vector2(car.x, car.y)
	var pv := Vector2(car.vx, car.vy)
	for c in cars:
		var p: Vector2 = c.pos
		if p.distance_squared_to(pc) > 49.0:
			c.near = false
			continue
		var dir := Vector2(cos(c.heading), sin(c.heading))
		var cv := dir * float(c.v)
		var rel := (pv - cv).length()
		var touched := false
		for k: float in [-1.1, 1.1]:
			var q: Vector2 = p + dir * k
			var local := (q - pc).rotated(-car.heading)
			var cl := Vector2(clampf(local.x, -FreeCar.HALF_L, FreeCar.HALF_L), clampf(local.y, -FreeCar.HALF_W, FreeCar.HALF_W))
			var d := local.distance_to(cl)
			if d < RADIUS:
				touched = true
				var n_local := (cl - local).normalized() if d > 1e-4 else Vector2(-1, 0)
				var n_out := n_local.rotated(car.heading) # from the traffic car towards the player
				var v := player.bump(n_out, (RADIUS - d) * (0.15 if player.monster else 0.6), cl.rotated(car.heading), CAR_MASS, cv)
				c.push = (c.push as Vector2) - n_out * (RADIUS - d) * (1.2 if player.monster else 0.4)
				if v > 2.0:
					c.knock = 2.5
					c.spin = float(c.spin) + clampf(v * 0.03, 0.0, 0.6) * signf(n_out.cross(dir))
					c.push = (c.push as Vector2) - n_out * minf(v * 0.15, 2.0)
					hits.append([q.x, q.y, v])
				break
		if touched:
			c.near = true # no near-miss credit for a hit
			continue
		# a near miss: passed close at speed without touching
		var dist := p.distance_to(pc)
		if dist < 3.2 and rel > 12.0 and not c.near and pv.length() > 14.0:
			c.near = true
			near_misses.append(rel)
		elif dist > 6.0:
			c.near = false
