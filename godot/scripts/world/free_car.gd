## The player's Seicento loose in the open world: the race's tyre-model physics (Physics, the same car model
## and set-up the circuits use) on the town's own ground. The town gives it the surface under each wheel, the
## slope, a height to ride at (the ground, or the deck of the bridge or embankment it is on), and solid things to
## hit: buildings, trees, lamp posts, the edge of the map and the traffic. Drive off an embankment and it flies.
class_name FreeCar
extends RefCounted

const G := 9.81
const HALF_L := 1.68 ## half the Seicento's length (3.34 m) and width (1.51 m)
const HALF_W := 0.76
const WALL_STEP := 0.9 ## m: a deck this much above the car is a wall (the side of an embankment), not a ramp
const UNDER_DECK := 3.6 ## m: a deck this far above the car is a bridge it passes under
const BOOM_R := 0.12 ## m: half the thickness of a level crossing boom
const WATER_RESPAWN := 2.2 ## s in deep water before the car is put back on the road

var map: TownMap
var car: RaceCar
var model: CarModel
var phys: Physics
var env := Physics.Env.new()
var ctl := Physics.Controls.new()
var gearbox := "auto"
var assists := "abs" ## full | abs | off
var mu := 1.0 ## weather grip
var grav_mul := 1.0 ## CarMods: moon gravity
var grip_mul := 1.0 ## CarMods: ice rink
var rear_grip := 1.0 ## CarMods: drift king
var drift_king := false
var monster := false ## CarMods: monster truck (any surface grips like tarmac, climbs higher steps, shrugs off traffic)
var power_mul := 1.0 ## CarMods: nitrous

var z := 0.0 ## height of the car's ground contact (m above sea level)
var vz := 0.0
var airborne := false
var air_time := 0.0
var last_air := 0.0 ## seconds of the last jump, set on landing (for the skill score)
var landed := 0.0 ## landing speed (m/s) of the last touchdown, cleared by whoever reads it
var hits: Array = [] ## [[x, y, closing speed]] since the reader last emptied it
var in_water := false
var water_t := 0.0
var wants_respawn := false
var odometer := 0.0
var surface := Physics.SURF_TRACK ## under the car's centre
var road := {} ## the road under the car's centre ({} off road)
var tilt := Basis() ## the ground's slope under the car, for the visual
var _surface_fn: Callable

func _init(town: TownMap, car_model: CarModel = null) -> void:
	map = town
	model = car_model if car_model else CarModel.new()
	phys = Physics.new(model)
	car = RaceCar.new()
	car.is_player = true
	car.name = "You"
	car.model = model
	car.physics = phys
	car.control = "free"
	car.fuel = 30.0
	_surface_fn = func(x: float, y: float) -> int: return _surface_at(x, y)

## Swaps the car for another model (the Hypercar Seicento): a fresh drivetrain, same place.
func fit_model(m: CarModel) -> void:
	model = m
	phys = Physics.new(m)
	car.model = m
	car.physics = phys
	car.phys = null
	car.gear = 0
	car.rev = false
	car.rpm = m.spec.idle_rpm
	car.shift_t = 0.0
	car.hold_t = 0.0

## Puts the car at rest at a map point, facing heading (radians from +x towards +y).
func place(p: Vector2, heading: float) -> void:
	car.x = p.x
	car.y = p.y
	car.heading = heading
	car.vx = 0.0
	car.vy = 0.0
	car.yaw_rate = 0.0
	car.gear = 0
	car.rev = false
	car.rpm = model.spec.idle_rpm
	car.phys = null
	airborne = false
	vz = 0.0
	in_water = false
	water_t = 0.0
	wants_respawn = false
	var hit := map.road_at(p.x, p.y, -INF, 1.0)
	z = float(hit.height) if not hit.is_empty() else map.ground(p.x, p.y)
	road = hit

## Back on the nearest road, facing along it the way the car was pointing.
func respawn() -> void:
	var near := map.nearest_road(Vector2(car.x, car.y), 400.0, 1)
	if near.is_empty():
		place(Vector2(car.x, car.y), car.heading)
		return
	var dir: Vector2 = near.dir
	var h := atan2(dir.y, dir.x)
	if cos(h - car.heading) < 0.0:
		h += PI
	# the right-hand lane of a two-way road
	var side := Vector2(-dir.y, dir.x) * (1.0 if cos(h - atan2(dir.y, dir.x)) > 0.0 else -1.0)
	var lane := 0.0 if map.road_oneway[near.road] else map.road_w[near.road] * 0.22
	place(near.pos + side * lane, h)

func speed_kmh() -> float:
	return absf(car.speed) * 3.6

## Height the car would ride at on (x, y), keeping to the deck nearest its current height.
func support(x: float, y: float) -> float:
	var g := map.ground(x, y)
	# the drawn terrain: ponds and river beds slope down their banks (a dyke track through the fishponds stays up)
	if map.road_at(x, y).is_empty():
		g = map.terrain(x, y)
	var best := g
	var best_d := absf(g - z)
	for d in map.decks_at(x, y, TownMap.DRIVE_REACH):
		var over := maxf(float(d[2]), 0.0)
		var deck: float = d[1]
		if d[5]:
			if over > TownMap.PARAPET:
				continue # off the side of a bridge: the parapet ends here, nothing holds the car up
		else:
			# beyond a raised road's edge the earth embankment falls away, it is no plane at deck height
			deck = maxf(0.0, deck - over / TownMap.EMBANKMENT)
		var h: float = g + deck
		if h - z > UNDER_DECK:
			continue # a bridge overhead
		var dd := absf(h - z)
		if dd < best_d:
			best_d = dd
			best = h
	return best

func _surface_at(x: float, y: float) -> int:
	if airborne:
		return Physics.SURF_GRAVEL
	if monster and not in_water:
		return Physics.SURF_TRACK
	var hit := map.road_at(x, y, z)
	if not hit.is_empty() and absf(float(hit.height) - z) > 1.2:
		hit = {}
	if in_water:
		return Physics.SURF_GRAVEL
	return map.surface_of(hit)

## One physics tick. Pedals 0..1, steer -1..1 (+ right).
func step(dt: float, thr: float, brk: float, steer_in: float, shift_up := false, shift_down := false, handbrake := 0.0) -> void:
	var spec := model.spec
	var mass := model.mass_with_fuel(car.fuel)
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var vF := car.vx * ch + car.vy * sh
	# reverse: hold the brake at a standstill; throttle selects first again
	if not car.rev and brk > 0.3 and thr < 0.05 and absf(vF) < 0.4:
		car.rev = true
		car.gear = 0
	elif car.rev and thr > 0.05:
		# still rolling backwards: the pedals stay swapped below, so throttle brakes (never speeds up reverse)
		if vF >= -0.5:
			car.rev = false
	if car.rev:
		var t := thr
		thr = brk
		brk = t
	if not car.rev and gearbox == "auto":
		_auto_shift(vF, brk)
	elif not car.rev:
		if shift_up and car.gear < spec.gears.size() - 1:
			car.gear += 1
			car.shift_t = 0.18
		if shift_down and car.gear > 0:
			car.gear -= 1
			car.shift_t = 0.18

	# slope of what the car stands on
	var dz_dx := (support(car.x + 1.5, car.y) - support(car.x - 1.5, car.y)) / 3.0
	var dz_dy := (support(car.x, car.y + 1.5) - support(car.x, car.y - 1.5)) / 3.0
	if airborne:
		dz_dx = 0.0
		dz_dy = 0.0
	env.gx = -G * grav_mul * dz_dx / sqrt(1.0 + dz_dx * dz_dx)
	env.gy = -G * grav_mul * dz_dy / sqrt(1.0 + dz_dy * dz_dy)
	env.mu = (0.04 if airborne else mu * grip_mul)
	env.rear_grip = rear_grip
	env.mass = mass
	env.surface = _surface_fn
	env.power = power_mul
	env.drag_mul = 4.0 if in_water else 1.0
	env.abs_on = assists != "off"
	env.tc_on = assists == "full"
	env.esc_on = assists == "full"
	ctl.throttle = thr
	ctl.brake = brk
	ctl.steer = steer_in
	ctl.handbrake = handbrake
	env.drift_assist = Race.DRIFT_ASSIST_FULL if assists == "full" else (Race.DRIFT_ASSIST_ABS if assists == "abs" else 0.0)
	if drift_king:
		env.drift_assist = 1.0
	var px := car.x
	var py := car.y
	car.px = px
	car.py = py
	car.ph = car.heading
	car.has_prev = true
	phys.step(car, ctl, env, dt)
	car.shift_t = maxf(0.0, car.shift_t - dt)
	car.hold_t = maxf(0.0, car.hold_t - dt)
	odometer += Vector2(car.x - px, car.y - py).length()

	_vertical(dt, px, py, mass)
	_collide(mass)
	road = map.road_at(car.x, car.y, z)
	if not road.is_empty() and absf(float(road.height) - z) > 1.2:
		road = {}
	_water(dt)
	surface = map.surface_of(road) if not road.is_empty() and absf(float(road.height) - z) < 1.2 else Physics.SURF_GRASS
	var n := Vector3(-dz_dx, 1.0, -dz_dy).normalized()
	tilt = tilt.slerp(Basis(Quaternion(Vector3.UP, n)), minf(1.0, dt * 10.0)) if not airborne else tilt

## Ground following, jumps and landings; the steep side of an embankment stops the car like a wall.
func _vertical(dt: float, px: float, py: float, mass: float) -> void:
	var target := support(car.x, car.y)
	var step_h := CarMods.MONSTER_STEP if monster else WALL_STEP
	if target > z + step_h and not airborne:
		# the side of an embankment: push back off it
		for d in map.decks_at(car.x, car.y, TownMap.DRIVE_REACH):
			var off: Vector2 = d[4]
			if off.length() > 0.01:
				var n_out := off.normalized()
				car.x = px + n_out.x * 0.05
				car.y = py + n_out.y * 0.05
				var v := phys.barrier_hit(car, -n_out.x, -n_out.y, -n_out.x * HALF_W, -n_out.y * HALF_W, mass)
				if v > 1.0:
					hits.append([car.x, car.y, v])
				break
		target = support(car.x, car.y)
		if target > z + step_h:
			car.x = px
			car.y = py
			target = support(car.x, car.y)
	if airborne:
		air_time += dt
		vz -= G * grav_mul * dt
		z += vz * dt
		if z <= target:
			landed = -vz
			last_air = air_time
			z = target
			vz = 0.0
			airborne = false
			air_time = 0.0
		return
	var pred := z + vz * dt
	if target < pred - 0.3 and absf(car.speed) > 6.0:
		airborne = true
		air_time = 0.0
		z = pred
		return
	vz = clampf((target - z) / maxf(dt, 1e-4), -25.0, 25.0)
	z = target

func _water(dt: float) -> void:
	var w := map.water_at(Vector2(car.x, car.y))
	# a dyke track through the fishponds is road, not water
	in_water = not is_nan(w) and z <= w + 0.6 and road.is_empty()
	if in_water:
		water_t += dt
		if water_t > WATER_RESPAWN:
			wants_respawn = true
	else:
		water_t = 0.0

## Corners of the car's footprint in the map frame.
func corners() -> PackedVector2Array:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var f := Vector2(ch, sh)
	var r := Vector2(-sh, ch)
	var c := Vector2(car.x, car.y)
	return PackedVector2Array([c + f * HALF_L + r * HALF_W, c + f * HALF_L - r * HALF_W,
		c - f * HALF_L - r * HALF_W, c - f * HALF_L + r * HALF_W])

## Push the car out of a round post (a tree, a lamp, a pier).
func _post_push(pc: Vector2, radius: float, mass: float) -> void:
	var c := Vector2(car.x, car.y)
	var local := (pc - c).rotated(-car.heading)
	var cl := Vector2(clampf(local.x, -HALF_L, HALF_L), clampf(local.y, -HALF_W, HALF_W))
	var d := local.distance_to(cl)
	if d < radius:
		var n_local := (cl - local).normalized() if d > 1e-4 else Vector2(signf(local.x), 0.0) * -1.0
		var n_out := n_local.rotated(car.heading)
		_push(n_out * (radius - d + 0.01), cl.rotated(car.heading), n_out, mass)

## Push the car out of a thin wall segment [ax, ay, bx, by, half thickness, ...].
func _wall_push(c: Vector2, wall: PackedFloat32Array, mass: float) -> void:
	var a := Vector2(wall[0], wall[1])
	var b := Vector2(wall[2], wall[3])
	var cp := Geometry2D.get_closest_point_to_segment(c, a, b)
	var local := (cp - c).rotated(-car.heading)
	var cl := Vector2(clampf(local.x, -HALF_L, HALF_L), clampf(local.y, -HALF_W, HALF_W))
	var d := local.distance_to(cl)
	if d < wall[4]:
		var n_local := (cl - local).normalized() if d > 1e-4 else Vector2(signf(local.x), 0.0) * -1.0
		var n_out := n_local.rotated(car.heading)
		_push(n_out * (wall[4] - d + 0.02), cl.rotated(car.heading), n_out, mass)

func _collide(mass: float) -> void:
	var c := Vector2(car.x, car.y)
	if airborne and z > map.ground(car.x, car.y) + 5.0:
		return # flying high over whatever is down there
	# buildings: a corner inside a wall is pushed out along the nearest face; a building's corner inside
	# the car pushes the car off it
	for bi in map.buildings_near(c, 2.2):
		var ring := map.bld_rings[bi]
		for q in corners():
			if Geometry2D.is_point_in_polygon(q, ring):
				var best := INF
				var n_out := Vector2.ZERO
				for k in ring.size():
					var a := ring[k]
					var b := ring[(k + 1) % ring.size()]
					var cp := Geometry2D.get_closest_point_to_segment(q, a, b)
					var d := q.distance_to(cp)
					if d < best:
						best = d
						n_out = (cp - q).normalized() if d > 1e-4 else Vector2(b.y - a.y, a.x - b.x).normalized()
				_push(n_out * (best + 0.02), q - c, n_out, mass)
		_vertex_push(ring, mass)
	# trees, lamp posts and the like
	for post in map.posts_near(c, HALF_L + 0.6):
		_post_push(Vector2(post.x, post.y), post.z, mass)
	# bridge piers hold up the deck: solid to a car beneath it, not to one driving over
	for pier in map.piers_near(c, HALF_L + 0.6):
		if z < pier.w - 2.0:
			_post_push(Vector2(pier.x, pier.y), pier.z, mass)
	# bridge parapets: a wall along the deck edge for a car on that deck (not one under it or far below)
	for wall in map.parapets_near(c, HALF_L + 1.0):
		if absf(z - wall[5]) < 2.5:
			_wall_push(c, wall, mass)
	# fences, walls and hedges: treat each segment as a thin capsule against the car's box
	for wall in map.walls_near(c, HALF_L + 1.0):
		_wall_push(c, wall, mass)
	# the train's cars: boxes that push the car out of them (they don't give way)
	for tc in map.trains:
		if tc == null or absf(float(tc[4]) - z) > 3.0:
			continue
		var tcen: Vector2 = tc[0]
		if tcen.distance_to(c) > float(tc[2]) + HALF_L + 2.0:
			continue
		var f := Vector2.from_angle(float(tc[1]))
		var r := Vector2(-f.y, f.x)
		var hl: float = tc[2]
		var hw: float = tc[3]
		var ring := PackedVector2Array([tcen + f * hl + r * hw, tcen + f * hl - r * hw, tcen - f * hl - r * hw, tcen - f * hl + r * hw])
		for q in corners():
			var lq := q - tcen
			var ax := lq.dot(f)
			var ay := lq.dot(r)
			if absf(ax) < hl and absf(ay) < hw:
				# out through the nearer side (a car hits a train side-on, not its buffers, almost always)
				var dx := hl - absf(ax)
				var dy := hw - absf(ay)
				var n_out := f * signf(ax) if dx < dy else r * signf(ay)
				_push(n_out * (minf(dx, dy) + 0.02), q - c, n_out, mass)
		_vertex_push(ring, mass)
	# a level crossing's boom once it is (nearly) down: a thin bar the car's box can't pass
	for bm in map.booms:
		if float(bm[3]) > 0.3:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(c, bm[0], bm[1])
		if cp.distance_to(c) > HALF_L + 1.0:
			continue
		var local := (cp - c).rotated(-car.heading)
		var cl := Vector2(clampf(local.x, -HALF_L, HALF_L), clampf(local.y, -HALF_W, HALF_W))
		var d := local.distance_to(cl)
		if d >= BOOM_R:
			continue
		var n_local: Vector2
		var depth: float
		if d > 1e-4:
			n_local = (cl - local) / d
			depth = BOOM_R - d
		else:
			# the boom is already inside the box (a fast car crossed it in one tick): back out along the car
			var sx := signf(local.x) if local.x != 0.0 else 1.0
			n_local = Vector2(-sx, 0.0)
			depth = HALF_L - absf(local.x) + BOOM_R
		var n_out := n_local.rotated(car.heading)
		_push(n_out * (depth + 0.01), cl.rotated(car.heading), n_out, mass)
	# the edge of the map
	for q in corners():
		var push := map.edge_push(q)
		if push != Vector2.ZERO:
			_push(push, q - Vector2(car.x, car.y), push.normalized(), mass)

func _vertex_push(ring: PackedVector2Array, mass: float) -> void:
	var c := Vector2(car.x, car.y)
	for v in ring:
		var local := (v - c).rotated(-car.heading)
		if absf(local.x) < HALF_L and absf(local.y) < HALF_W:
			var dx := HALF_L - absf(local.x)
			var dy := HALF_W - absf(local.y)
			# push the car away from the corner along the shorter way out
			var n_local := Vector2(-signf(local.x), 0.0) if dx < dy else Vector2(0.0, -signf(local.y))
			var n_out := n_local.rotated(car.heading)
			_push(n_out * (minf(dx, dy) + 0.02), v - c, n_out, mass)

## Moves the car by `by` and bounces it off a surface whose outward normal (towards the car) is n_out,
## touching at r from the car's centre.
func _push(by: Vector2, r: Vector2, n_out: Vector2, mass: float) -> void:
	car.x += by.x
	car.y += by.y
	var v := phys.barrier_hit(car, -n_out.x, -n_out.y, r.x, r.y, mass)
	if v > 1.0:
		hits.append([car.x + r.x, car.y + r.y, v])

## A rigid push from something else (traffic): pass its outward normal, contact point offset and its mass.
func bump(n_out: Vector2, depth: float, r: Vector2, other_mass: float) -> float:
	car.x += n_out.x * depth
	car.y += n_out.y * depth
	var mass := model.mass_with_fuel(car.fuel)
	if monster:
		other_mass *= CarMods.MONSTER_SHRUG
	var eff := mass * other_mass / (mass + other_mass) * 2.0
	var v := phys.barrier_hit(car, -n_out.x, -n_out.y, r.x, r.y, eff)
	if v > 1.0:
		hits.append([car.x + r.x, car.y + r.y, v])
	return v

## The race's automatic gearbox (Race.auto_shift), for a car without a race around it.
func _auto_shift(vF: float, brk: float) -> void:
	var cm := model
	var vp := maxf(0.0, vF)
	var top := cm.spec.gears.size() - 1
	var g := car.gear
	if vF < 1.0:
		g = 0
	elif g < top and (car.rpm > cm.spec.limiter - 150.0 or cm.wheel_force(vp, g + 1, 1.0) > cm.wheel_force(vp, g, 1.0)) and cm.rpm_for(vF, g + 1) > cm.spec.limiter * 4.0 / 9.0:
		g += 1
	elif g > 0 and car.hold_t <= 0.0 and (cm.spec.shift_hold <= 0.0 or cm.rpm_for(vF, g) < cm.spec.limiter * 0.5) and cm.rpm_for(vF, g - 1) < cm.spec.limiter - 400.0 and (cm.wheel_force(vp, g - 1, 1.0) > cm.wheel_force(vp, g, 1.0) * 1.06 or (brk > 0.1 and cm.rpm_for(vF, g) < cm.spec.limiter * 32.0 / 63.0)):
		g -= 1
	if g != car.gear:
		car.shift_t = 0.15 if g > car.gear else 0.12
		if g > car.gear:
			car.hold_t = cm.spec.shift_hold
		car.gear = g
