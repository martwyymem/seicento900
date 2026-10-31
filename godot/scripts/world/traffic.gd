## Ambient traffic for the open world: cars that drive the town's real road graph in their lane, at about the
## limit, pick a way at each junction, keep their distance from the car ahead (and from the player), and get
## shoved when the player hits them. They live only round the player: spawned out of sight ahead, dropped when
## far behind. Near misses are reported for the skill score.
class_name Traffic
extends RefCounted

const MAX_CARS := 34
const SPAWN_MIN := 140.0
const SPAWN_MAX := 420.0
const DESPAWN := 560.0
const CAR_MASS := 1150.0
const RADIUS := 0.95 ## each car is two circles this big, 1.1 m either side of its middle
const KINDS := ["CarHatch", "CarSedan", "CarVan", "Maluch", "CarHatch", "CarSedan"]

var map: TownMap
var root: Node3D
var builder: TownBuilder
var cars: Array = [] ## dictionaries, see _spawn
var near_misses: Array = [] ## [relative speed m/s] since the reader last emptied it
var hits: Array = [] ## [[x, y, speed]]
var _rng := RandomNumberGenerator.new()
var _paint_cache := {}
var _spawn_t := 0.0
var _edges := [] ## [from node, edge] usable by traffic
var monster := false ## CarMods' Monster Truck: every traffic car stands on giant wheels
static var _tyre_mesh: CylinderMesh

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
	var pp := Vector2(player.car.x, player.car.y)
	_spawn_t -= dt
	if _spawn_t <= 0.0 and cars.size() < MAX_CARS:
		_spawn_t = 0.25
		_try_spawn(pp, player)
	var i := cars.size() - 1
	while i >= 0:
		var c: Dictionary = cars[i]
		if (c.pos as Vector2).distance_to(pp) > DESPAWN:
			(c.node as Node3D).queue_free()
			cars.remove_at(i)
		i -= 1
	for c in cars:
		_drive(c, dt, player)
	_contact(player)

func clear() -> void:
	for c in cars:
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

func _spawn(from_node: String, e: Array, pts: PackedVector2Array, s: float) -> void:
	var kind: String = KINDS[_rng.randi() % KINDS.size()]
	var paint := Color(TownBuilder.CAR_PAINTS[_rng.randi() % TownBuilder.CAR_PAINTS.size()])
	var node := _car_node(kind, paint)
	root.add_child(node)
	var ri: int = e[1]
	var limit := map.road_limit[ri] / 3.6
	var c := {"node": node, "from": from_node, "edge": e, "pts": pts, "len": _poly_len(pts), "s": s, "i0": int(e[2]),
		"istep": 1 if int(e[3]) >= int(e[2]) else -1,
		"v": limit * 0.8, "want": limit * (0.75 + _rng.randf() * 0.25), "pos": Vector2.ZERO, "dir": Vector2.RIGHT,
		"heading": 0.0, "knock": 0.0, "push": Vector2.ZERO, "spin": 0.0, "near": false, "kind": kind, "y": 0.0}
	_place(c)
	cars.append(c)

## Dev menu: a parked car `gap` metres ahead of the player, along the way the player faces (it stays until it is knocked off).
func spawn_ahead(player: FreeCar, kind: String, gap := 22.0) -> void:
	var dir := Vector2(cos(player.car.heading), sin(player.car.heading))
	var start := Vector2(player.car.x, player.car.y) + dir * gap
	var pts := PackedVector2Array([start, start + dir * 60.0])
	var ri: int = int(player.road.road) if not player.road.is_empty() else 0
	var paint := Color(TownBuilder.CAR_PAINTS[_rng.randi() % TownBuilder.CAR_PAINTS.size()])
	var node := _car_node(kind, paint)
	root.add_child(node)
	var c := {"node": node, "from": "", "edge": ["", ri], "pts": pts, "len": 60.0, "s": 0.0,
		"v": 0.0, "want": 0.0, "pos": Vector2.ZERO, "dir": dir, "heading": 0.0, "knock": 0.0, "push": Vector2.ZERO,
		"spin": 0.0, "near": false, "kind": kind, "y": player.z}
	_place(c)
	cars.append(c)

func _car_node(kind: String, paint: Color) -> Node3D:
	var node := Node3D.new()
	var mesh_xf := builder._model(kind, TownBuilder._fallback_car.bind(kind))
	var inst := MeshInstance3D.new()
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
	if monster:
		_add_monster_wheels(node, inst)
	return node

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
			return g - TownBuilder.ROAD_LIFT * 0.5 + 0.1
		var ia: int = clampi(int(c.i0) + int(at[2]) * int(c.istep), 0, z.size() - 1)
		var ib: int = clampi(ia + int(c.istep), 0, z.size() - 1)
		return g + lerpf(z[ia], z[ib], float(at[3])) - TownBuilder.ROAD_LIFT * 0.5 + 0.1
	var y_ref: float = float(c.get("y", 0.0))
	var hit := map.road_at(p.x, p.y, y_ref if y_ref != 0.0 else -INF, 1.0)
	return float(hit.height) - TownBuilder.ROAD_LIFT * 0.5 + 0.1 if not hit.is_empty() else g

func _place(c: Dictionary) -> void:
	var at := _point_on(c.pts, c.s)
	var dir: Vector2 = at[1]
	var ri: int = c.edge[1]
	var side := Vector2(-dir.y, dir.x)
	var p: Vector2 = (at[0] as Vector2) + side * _lane(ri) + c.push
	c.pos = p
	c.dir = dir
	var h := atan2(dir.y, dir.x) + float(c.spin)
	c.heading = h
	var y := _layer_y(c, at, p)
	c.y = y
	var node: Node3D = c.node
	node.position = Vector3(p.x, y, p.y)
	node.basis = Basis(Vector3.UP, -h - PI / 2.0)

func _drive(c: Dictionary, dt: float, player: FreeCar) -> void:
	if c.knock > 0.0:
		# shoved: slide to a stop, then carry on
		c.knock -= dt
		c.v = maxf(0.0, c.v - 8.0 * dt)
		c.push = (c.push as Vector2) * maxf(0.0, 1.0 - dt * 0.5)
		c.spin = float(c.spin) * maxf(0.0, 1.0 - dt * 0.8)
		c.s += c.v * dt
		_advance(c)
		_place(c)
		return
	c.push = (c.push as Vector2).move_toward(Vector2.ZERO, dt * 0.8)
	c.spin = move_toward(float(c.spin), 0.0, dt * 0.6)
	# the gap to whatever is ahead in this lane, the player included
	var ahead := INF
	var p: Vector2 = c.pos
	var dir: Vector2 = c.dir
	for o in cars:
		if o == c:
			continue
		var d: Vector2 = (o.pos as Vector2) - p
		var along := d.dot(dir)
		if along > 0.0 and along < ahead and absf(d.dot(Vector2(-dir.y, dir.x))) < 2.2:
			ahead = along
	var pd := Vector2(player.car.x, player.car.y) - p
	var p_along := pd.dot(dir)
	if p_along > 0.0 and absf(pd.dot(Vector2(-dir.y, dir.x))) < 2.4:
		ahead = minf(ahead, p_along)
	# slow for bends: the corner ahead within 25 m
	var want: float = c.want
	var look := _point_on(c.pts, minf(float(c.len), c.s + 18.0))
	var turn := absf(dir.angle_to(look[1]))
	if c.s + 18.0 > float(c.len):
		turn = maxf(turn, 0.6) # a junction: ease off
	want = minf(want, lerpf(want, 6.0, clampf(turn / 1.2, 0.0, 1.0)))
	if ahead < INF:
		want = minf(want, maxf(0.0, (ahead - 8.0) * 0.9))
	var acc := 2.2 if want > c.v else -6.5
	c.v = clampf(c.v + acc * dt, 0.0, maxf(want, 0.0) if acc < 0.0 else want)
	c.s += c.v * dt
	_advance(c)
	_place(c)

## Onto the next edge at the end of this one: any way out of the junction but back, if there is one.
func _advance(c: Dictionary) -> void:
	while c.s > float(c.len):
		var e: Array = c.edge
		var at_node: String = e[0]
		var options := []
		for n in map.node_edges.get(at_node, []):
			if n[5] and n[0] != c.from and map.road_rank[n[1]] >= 2:
				options.append(n)
		if options.is_empty():
			for n in map.node_edges.get(at_node, []):
				if n[5]:
					options.append(n)
		if options.is_empty():
			c.s = float(c.len)
			c.v = 0.0
			return
		c.s -= float(c.len)
		# prefer carrying straight on a bigger road
		var cur_dir: Vector2 = c.dir
		var best: Array = options[0]
		var best_score := -INF
		for n in options:
			var pts := _edge_points(n)
			var d := (pts[mini(1, pts.size() - 1)] - pts[0]).normalized()
			var score := d.dot(cur_dir) * 1.2 + map.road_rank[n[1]] * 0.15 + _rng.randf() * 1.4
			if score > best_score:
				best_score = score
				best = n
		c.from = at_node
		c.edge = best
		c.pts = _edge_points(best)
		c.len = _poly_len(c.pts)
		c.want = map.road_limit[best[1]] / 3.6 * (0.75 + _rng.randf() * 0.25)

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
				var v := player.bump(n_out, (RADIUS - d) * (0.15 if player.monster else 0.6), cl.rotated(car.heading), CAR_MASS)
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
