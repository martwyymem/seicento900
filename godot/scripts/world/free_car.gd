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
const TRAIN_TOP := 3.6 ## m: a car this far over the rails clears the train's roof
const SLOPE_BREAK := 0.3 ## m: the two sides of the car's slope sample differ this much: one is off a ledge
const BOOM_R := 0.12 ## m: half the thickness of a level crossing boom
const KERB_BUMP_MIN := 0.05 ## m: a step up at least this high is a bump (a kerb is 0.13)
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
var rev_lock := false ## set by place(): a brake already held (through a spawn or a respawn) selects reverse only once let go
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
	rev_lock = true
	var hit := map.road_at(p.x, p.y, -INF, 1.0)
	z = float(hit.height) if not hit.is_empty() else map.ground(p.x, p.y)
	road = hit

## Back on the nearest road, facing along it the way the car was pointing (or the way `prefer` points, when given:
## a spawn facing on down its GPS route).
func respawn(prefer := Vector2.ZERO) -> void:
	var near := map.nearest_road(Vector2(car.x, car.y), 400.0, 1)
	var want := car.heading if prefer == Vector2.ZERO else prefer.angle()
	if near.is_empty():
		place(Vector2(car.x, car.y), want)
		return
	var dir: Vector2 = near.dir
	var h := atan2(dir.y, dir.x)
	if cos(h - want) < 0.0:
		h += PI
	# the right-hand lane of a two-way road
	var side := Vector2(-dir.y, dir.x) * (1.0 if cos(h - atan2(dir.y, dir.x)) > 0.0 else -1.0)
	var lane := 0.0 if map.road_oneway[near.road] else map.road_w[near.road] * 0.22
	place(near.pos + side * lane, h)
	# on the road it was put back on (the deck of a bridge, not the street under it)
	z = map.ground(car.x, car.y) + map.deck_at(int(near.road), int(near.i), float(near.t)) + map.road_lift(int(near.road))
	road = map.road_at(car.x, car.y, z)

func speed_kmh() -> float:
	return absf(car.speed) * 3.6

## Height the car would ride at on (x, y), keeping to the deck nearest its current height. Streets and pavements are
## drawn road_lift / PAVEMENT_TOP over the ground and the tyres stand on that. lifted = false gives the surface without
## that lift (the ground, a deck, a kerb KERB_H high): the slope under the car and so gravity, unchanged by the lift's
## ramp at a street's edge.
func support(x: float, y: float, lifted := true) -> float:
	var g := map.ground(x, y)
	# the drawn terrain: ponds and river beds slope down their banks (a dyke track through the fishponds stays up)
	var lowest := map.road_at(x, y)
	if lowest.is_empty():
		g = map.terrain(x, y) + (map.pave_top_at(x, y) if lifted else map.kerb_at(x, y))
	var g_bare := g # what a raised road's deck stands on
	if lifted and not lowest.is_empty() and float(lowest.deck) <= 0.05:
		# a street on the ground is drawn road_lift over it (the tyres rest on it, not in it); a raised road's deck
		# below carries its own lift
		g += map.road_lift(int(lowest.road)) * map.lift_share(float(lowest.half) - absf(float(lowest.dist)))
	# a railway embankment is solid earth: the car rides up its 1:1.5 slopes like a road embankment's, and a cut's
	# vertical face (or a steep step onto one) stops it (_vertical). Not in an underpass's cut, where the street runs.
	var bank := map.rail_bank(x, y)
	g = maxf(g, bank)
	g_bare = maxf(g_bare, bank) # a street beside the embankment is no surface under its slope
	var best := g
	var best_d := absf(g - z)
	# a raised road that is no bridge stands on a solid embankment: where it is the lowest road on the spot the bare
	# ground under it is out of reach, or a car at the foot of a ramp stays down there while the road rises over it
	if not lowest.is_empty() and float(lowest.deck) > 0.05 and map.road_bridge[int(lowest.road)] != 1:
		best_d = INF
	var decks := map.decks_at(x, y, TownMap.DRIVE_REACH)
	# on a raised road's own carriageway another road's side slope is no surface (a junction of two embankments)
	var on_solid := false
	for d in decks:
		if not d[5] and float(d[2]) <= 0.0 and float(d[1]) > 0.05:
			on_solid = true
			break
	for d in decks:
		if on_solid and not d[5] and float(d[2]) > 0.0:
			continue
		var over := maxf(float(d[2]), 0.0)
		var deck: float = d[1]
		if d[5]:
			if over > TownMap.PARAPET:
				continue # off the side of a bridge: the parapet ends here, nothing holds the car up
		else:
			# beyond a raised road's edge the earth embankment falls away, it is no plane at deck height
			deck = maxf(0.0, deck - over / TownMap.EMBANKMENT)
		var h: float = g_bare + deck + (map.road_lift(int(d[0])) * (1.0 - smoothstep(0.0, TownMap.LIFT_RAMP, float(d[2]))) if lifted else 0.0)
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
	if hit.is_empty() and map.kerb_at(x, y) > 0.0 and z < map.ground(x, y) + 0.6:
		return Physics.SURF_ASPHALT # a pavement grips like tarmac
	return map.surface_of(hit)

## What each wheel stands on (Physics.SURF_*, front left, front right, rear left, rear right), for the sounds and
## the dust; the physics asks the same per wheel in its step.
func wheel_surfaces() -> PackedInt32Array:
	var out := PackedInt32Array()
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	for i in 4:
		var ox := phys.WX[i] * ch - phys.WY[i] * sh
		var oy := phys.WX[i] * sh + phys.WY[i] * ch
		out.append(_surface_at(car.x + ox, car.y + oy))
	return out

## One physics tick. Pedals 0..1, steer -1..1 (+ right).
func step(dt: float, thr: float, brk: float, steer_in: float, shift_up := false, shift_down := false, handbrake := 0.0) -> void:
	var spec := model.spec
	var mass := model.mass_with_fuel(car.fuel)
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var vF := car.vx * ch + car.vy * sh
	# reverse: hold the brake at a standstill; throttle selects first again
	if rev_lock and brk < 0.1:
		rev_lock = false
	if not car.rev and not rev_lock and brk > 0.3 and thr < 0.05 and absf(vF) < 0.4:
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
	var zc := support(car.x, car.y, false)
	var dz_dx := _slope(support(car.x - 1.5, car.y, false), zc, support(car.x + 1.5, car.y, false))
	var dz_dy := _slope(support(car.x, car.y - 1.5, false), zc, support(car.x, car.y + 1.5, false))
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
	if surface == Physics.SURF_GRASS and not in_water and map.kerb_at(car.x, car.y) > 0.0:
		surface = Physics.SURF_ASPHALT
	var n := Vector3(-dz_dx, 1.0, -dz_dy).normalized()
	tilt = tilt.slerp(Basis(Quaternion(Vector3.UP, n)), minf(1.0, dt * 10.0)) if not airborne else tilt

## Slope over 1.5 m either side of the car (heights lo, mid, hi). Where one side falls off a ledge (a sample off the
## edge of a bridge reads the ground metres below, past a parapet the car can't cross) the two sides disagree: that
## side is no surface the car stands on, so the gentler side alone gives the slope. A real slope (a ramp, an
## embankment, a rail bank) rises alike on both sides and keeps its tilt.
func _slope(lo: float, mid: float, hi: float) -> float:
	var a := mid - lo
	var b := hi - mid
	if absf(b - a) <= SLOPE_BREAK:
		return (hi - lo) / 3.0
	return (a if absf(a) < absf(b) else b) / 1.5

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
				_impact(n_out, -n_out * HALF_W, 1.0)
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
	var rise := target - z
	var spd := absf(car.speed)
	if rise > KERB_BUMP_MIN and rise < 0.4 and spd > 1.5:
		_kerb_strike(rise, spd)
		if airborne:
			z = target
			return
	vz = clampf(rise / maxf(dt, 1e-4), -25.0, 25.0)
	z = target

## Wheels hit the edge of a kerb: the car loses speed, thumps (a hit event for the sound) and, if quick, hops.
func _kerb_strike(rise: float, spd: float) -> void:
	var keep := 1.0 - clampf(spd * 0.012 * (rise / 0.13), 0.0, 0.22)
	if monster:
		keep = 1.0 - (1.0 - keep) * 0.25
	car.vx *= keep
	car.vy *= keep
	car.yaw_rate *= 0.85
	hits.append([car.x, car.y, minf(spd * 0.3, 5.0)])
	if spd > 9.0 and not monster:
		vz = minf(spd * 0.05, 1.1)
		airborne = true
		air_time = 0.0

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

# ------------------------------------------------------------------------------------------- contacts
# Every solid the car meets in the open world is one of three shapes against the car's box: a thick segment (fences,
# walls, hedges, parapets, the bore's side walls, a closure's barrier, a building's face), a round post (trees, lamps,
# piers, parked cars) or a point the box must stay clear of (the map's edge). Each contact is the shallowest way out
# of the solid and is answered by _impact(), an arcade-style response: the car's speed into the surface goes (with a
# small bounce), its speed along the surface mostly stays, and the knock turns it along the surface.

const WALL_BOUNCE_SOFT := 0.3 ## restitution of a gentle knock ...
const WALL_BOUNCE_HARD := 0.08 ## ... and of a hard hit (closing at WALL_HARD_V or more)
const WALL_HARD_V := 20.0 ## m/s
const WALL_FRICTION := 0.15 ## speed along the surface lost per m/s of normal velocity change (a scrape, not a stop)
const WALL_SPIN := 0.45 ## share of a rigid body's spin from an off-centre knock (the rest of it keeps the car going)
const WALL_SPIN_MAX := 2.5 ## rad/s: most yaw rate one knock adds
const ALIGN_TIME := 0.3 ## s: a knock's spin turns the car at most as far as the surface's direction in this long
const SWEEP_STEP := 0.3 ## m: a car moving further than this in one tick is checked at points along its path
const SCRAPE_V := 2.0 ## m/s: a contact closing slower than this scrapes along without bouncing
const ALIGN_GRIP := 0.25 ## share of the turn towards the surface's direction a scrape gives each tick (more for a harder hit)
const ALIGN_NUDGE := 0.07 ## rad: most the heading is eased round towards the surface's direction per contact
const JOINT_GAP := 0.2 ## m: segment ends this close are joined (no end cap: the car slides over the joint)

func _collide(mass: float) -> void:
	if airborne and z > map.ground(car.x, car.y) + 5.0:
		return # flying high over whatever is down there
	var cur := Vector2(car.x, car.y)
	var prev := Vector2(car.px, car.py) if car.has_prev else cur
	var moved := prev.distance_to(cur)
	if moved <= SWEEP_STEP:
		_collide_at(prev, mass)
		return
	# fast: walk the box along the tick's path, stopping where it first touches something
	var steps := mini(int(ceil(moved / SWEEP_STEP)), 12)
	var h1 := car.heading
	var h0 := car.ph if car.has_prev else h1
	var from := prev
	for k in range(1, steps + 1):
		var f := float(k) / float(steps)
		var at := prev.lerp(cur, f)
		car.x = at.x
		car.y = at.y
		car.heading = lerp_angle(h0, h1, f)
		if _collide_at(from, mass) or k == steps:
			return
		from = at

## Resolves the car's box at its current place against everything solid near it; `prev` is where its centre came
## from (a thin fence is pushed back out on that side, so it is never crossed between two ticks). True on contact.
func _collide_at(prev: Vector2, mass: float) -> bool:
	var c := Vector2(car.x, car.y)
	var touched := false
	# fences, walls, hedges and the bore's side walls (two-sided), bridge parapets for a car on that deck
	var segs: Array[PackedFloat32Array] = map.walls_near(c, HALF_L + 1.0)
	for wall in map.parapets_near(c, HALF_L + 1.0):
		if absf(z - wall[5]) < 2.5:
			segs.append(wall)
	var free := _free_ends(segs)
	# buildings: each face near the car, one-sided (its outside), its ends joined to the next face
	var faces: Array = []
	for bi in map.buildings_near(c, HALF_L + 0.6):
		var ring := map.bld_rings[bi]
		var m := ring.size()
		if m < 3:
			continue
		var area := 0.0
		for k in m:
			area += ring[k].cross(ring[(k + 1) % m])
		for k in m:
			var a := ring[k]
			var b := ring[(k + 1) % m]
			if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) > HALF_L + 0.3:
				continue
			var t := (b - a).normalized()
			faces.append([a, b, Vector2(t.y, -t.x) if area > 0.0 else Vector2(-t.y, t.x)])
	# two passes settle a box wedged into a corner (each contact moves it, so the next is measured afresh). Contacts
	# with one face (the panels of a fence, a facade's runs, a wall and the building behind it) merge into one, so a
	# box across a joint is not knocked twice off centre and spun.
	for _round in 2:
		var found: Array = []
		for i in segs.size():
			var w: PackedFloat32Array = segs[i]
			var hit := _seg_contact(Vector2(w[0], w[1]), Vector2(w[2], w[3]), w[4], prev, Vector2.ZERO, free[i] & 1 != 0, free[i] & 2 != 0)
			if not hit.is_empty():
				found.append(hit)
		for f: Array in faces:
			var hit := _seg_contact(f[0], f[1], 0.0, prev, f[2], false, false)
			if not hit.is_empty():
				found.append(hit)
		if found.is_empty():
			break
		touched = true
		for hit: Array in _merge_contacts(found):
			_resolve(hit, 1.0)
	c = Vector2(car.x, car.y)
	# trees, lamp posts, signs, parked cars
	for post in map.posts_near(c, HALF_L + 0.6):
		touched = _round_contact(Vector2(post.x, post.y), post.z) or touched
	# bridge piers hold up the deck: solid to a car beneath it, not to one driving over
	for pier in map.piers_near(c, HALF_L + 0.6):
		if z < pier.w - 2.0:
			touched = _round_contact(Vector2(pier.x, pier.y), pier.z) or touched
	# the train's cars: moving boxes that push the car out of them (they don't give way)
	for tc in map.trains:
		if tc != null:
			_train_push(tc, mass)
	# a level crossing's boom once it is (nearly) down: a thin bar the car's box can't pass
	for bm in map.booms:
		if float(bm[3]) > 0.3:
			continue
		var a: Vector2 = bm[0]
		var b: Vector2 = bm[1]
		if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) > HALF_L + 1.0:
			continue
		var hit := _seg_contact(a, b, BOOM_R, prev, Vector2.ZERO, true, true)
		if not hit.is_empty():
			_resolve(hit, 1.0)
			touched = true
	# the edge of the map
	for q in corners():
		var push := map.edge_push(q)
		if push != Vector2.ZERO:
			_resolve([push.normalized(), push.length(), q - Vector2(car.x, car.y)], 1.0)
			touched = true
	return touched

## Contacts [normal, depth, point] whose normals agree (one face met at several places) as one: the deepest depth,
## the points averaged. The deepest face first.
static func _merge_contacts(found: Array) -> Array:
	var groups: Array = []
	for hit: Array in found:
		var n: Vector2 = hit[0]
		var joined := false
		for g: Array in groups:
			if (g[0] as Vector2).dot(n) > 0.995:
				g[1] = maxf(float(g[1]), float(hit[1]))
				g[2] = (g[2] as Vector2) + (hit[2] as Vector2)
				g[3] = int(g[3]) + 1
				joined = true
				break
		if not joined:
			groups.append([n, float(hit[1]), hit[2], 1])
	var out: Array = []
	for g: Array in groups:
		out.append([g[0], g[1], (g[2] as Vector2) / float(g[3])])
	out.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
	return out

## Per segment, bit 0 set when its end a is free and bit 1 when b is: no other segment of the set starts, ends or
## runs within JOINT_GAP of it. A free end is a post the car can hit end on; a joined one is not (a car sliding along
## a fence made of many short panels never catches on the joints between them).
func _free_ends(segs: Array[PackedFloat32Array]) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(segs.size())
	for i in segs.size():
		var w := segs[i]
		var bits := 0
		for e in 2:
			var p := Vector2(w[e * 2], w[e * 2 + 1])
			var joined := false
			for j in segs.size():
				if j == i:
					continue
				var o := segs[j]
				if Geometry2D.get_closest_point_to_segment(p, Vector2(o[0], o[1]), Vector2(o[2], o[3])).distance_to(p) < JOINT_GAP + o[4]:
					joined = true
					break
			if not joined:
				bits |= 1 << e
		out[i] = bits
	return out

## The car's box against a segment a-b of half thickness r: [outward normal, depth, contact point from the centre]
## or [] when clear. one_sided (non-zero) is the face's outward normal: a building wall, only met from outside. A
## two-sided wall is met from the side `prev` (the centre's last place) is on, so a thin fence the box crossed in one
## tick still pushes it back. Inside the segment's length the way out is along its normal (a long fence made of
## joined panels is one smooth face); at a free end the end itself may be the shallower way out.
func _seg_contact(a: Vector2, b: Vector2, r: float, prev: Vector2, one_sided: Vector2, free_a: bool, free_b: bool) -> Array:
	var ab := b - a
	var ln := ab.length()
	if ln < 1e-3:
		return _round_hit(a, maxf(r, 0.05))
	var t := ab / ln
	var n := Vector2(-t.y, t.x)
	var c := Vector2(car.x, car.y)
	if one_sided != Vector2.ZERO:
		n = one_sided
		if (prev - a).dot(n) < -0.3 and (c - a).dot(n) < -0.3:
			return [] # the car is behind this face (it is round the building's corner or beside its other side)
	else:
		var sp := (prev - a).dot(n)
		if absf(sp) < 1e-3:
			sp = (c - a).dot(n)
		if sp < 0.0:
			n = -n
	# the box, clipped to the slab the segment covers along its length (an end cap's thickness beyond a free end)
	var poly := corners()
	poly = _clip(poly, a, t, -(r if free_a else 0.0))
	poly = _clip(poly, b, -t, -(r if free_b else 0.0))
	var best: Array = []
	if poly.size() > 0:
		var lo := INF
		for p in poly:
			lo = minf(lo, (p - a).dot(n))
		var depth := r - lo
		if depth > 0.0:
			var at := Vector2.ZERO
			var cnt := 0
			for p in poly:
				if (p - a).dot(n) < lo + 0.04:
					at += p
					cnt += 1
			best = [n, depth, at / float(cnt) - c]
	for e in 2:
		if not (free_a if e == 0 else free_b):
			continue
		var cap := _round_hit(a if e == 0 else b, r)
		if not cap.is_empty() and (best.is_empty() or float(cap[1]) < float(best[1])):
			best = cap
	return best

## Part of polygon poly where (p - o) . dir >= k.
static func _clip(poly: PackedVector2Array, o: Vector2, dir: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := poly.size()
	for i in m:
		var p := poly[i]
		var q := poly[(i + 1) % m]
		var fp := (p - o).dot(dir) - k
		var fq := (q - o).dot(dir) - k
		if fp >= 0.0:
			out.append(p)
		if (fp >= 0.0) != (fq >= 0.0):
			out.append(p.lerp(q, fp / (fp - fq)))
	return out

## A round post at pc of radius `radius` against the car's box: [outward normal, depth, contact point] or [].
func _round_hit(pc: Vector2, radius: float) -> Array:
	var c := Vector2(car.x, car.y)
	var local := (pc - c).rotated(-car.heading)
	if absf(local.x) >= HALF_L + radius or absf(local.y) >= HALF_W + radius:
		return []
	var cl := Vector2(clampf(local.x, -HALF_L, HALF_L), clampf(local.y, -HALF_W, HALF_W))
	var d := local.distance_to(cl)
	var n_local: Vector2
	var depth: float
	if d > 1e-4:
		if d >= radius:
			return []
		n_local = (cl - local) / d
		depth = radius - d
	else:
		# the post's centre is inside the box: out the shorter way, past the face it is nearest
		var dx := HALF_L - absf(local.x)
		var dy := HALF_W - absf(local.y)
		if dx < dy:
			n_local = Vector2(-1.0 if local.x >= 0.0 else 1.0, 0.0)
			depth = dx + radius
			cl = Vector2(HALF_L * signf(local.x), local.y)
		else:
			n_local = Vector2(0.0, -1.0 if local.y >= 0.0 else 1.0)
			depth = dy + radius
			cl = Vector2(local.x, HALF_W * signf(local.y))
	return [n_local.rotated(car.heading), depth, cl.rotated(car.heading)]

func _round_contact(pc: Vector2, radius: float) -> bool:
	var hit := _round_hit(pc, radius)
	if hit.is_empty():
		return false
	_resolve(hit, 1.0)
	return true

## Moves the car out of a contact [outward normal, depth, contact point] and answers it with _impact().
func _resolve(hit: Array, share: float) -> float:
	var n: Vector2 = hit[0]
	var depth: float = hit[1]
	car.x += n.x * (depth + 0.005)
	car.y += n.y * (depth + 0.005)
	return _impact(n, hit[2], share)

## The knock off a surface with outward normal n (towards the car) at r from the car's centre. share: how much of
## the car's speed into it goes (1 for the town's solids, less for a car that gives way). Returns the closing speed.
## Arcade, not a rigid body: the centre's speed into the surface is taken out with a little bounce (more at a gentle
## knock than at a big hit, so a crash stops rather than rebounds), friction scrapes a little off the speed along it,
## and an off-centre knock spins the car the way a rigid one would turn, scaled down and capped so a glancing hit
## swings the car along the surface rather than round past it.
func _impact(n: Vector2, r: Vector2, share: float) -> float:
	var v := Vector2(car.vx, car.vy)
	var w := car.yaw_rate
	var vp := v + Vector2(-w * r.y, w * r.x) # the contact point's velocity
	var cg_in := -v.dot(n)
	var closing := maxf(cg_in, -vp.dot(n))
	if closing <= 0.0:
		return 0.0
	# a scrape (under SCRAPE_V) does not bounce, a knock does a little, a big hit hardly
	var e := lerpf(WALL_BOUNCE_SOFT, WALL_BOUNCE_HARD, clampf((closing - 3.0) / (WALL_HARD_V - 3.0), 0.0, 1.0)) * smoothstep(0.3, SCRAPE_V, closing)
	var dvn := maxf(cg_in, 0.0) * (1.0 + e) * share
	v += n * dvn
	var vt := v - n * v.dot(n)
	var vt_len := vt.length()
	if vt_len > 1e-3:
		v -= vt / vt_len * minf(vt_len, WALL_FRICTION * dvn)
	# spin: the rigid body's turn from an impulse at r, scaled; and the point's own spin into the surface goes
	var k2 := (model.spec.length * model.spec.length + model.spec.width * model.spec.width) / 12.0
	var rn := r.cross(n)
	var dw := rn * closing * (1.0 + e) * share / k2 * WALL_SPIN
	var spin_in := -w * rn # the contact point's speed into the surface from the car's own rotation
	if spin_in > 0.0 and absf(rn) > 0.05:
		dw += spin_in / rn * share # stop turning that corner into it
	dw = clampf(dw, -WALL_SPIN_MAX, WALL_SPIN_MAX)
	# never swing further than the surface's direction: the angle from the heading to the nearer way along it
	var f := Vector2.from_angle(car.heading)
	var along := Vector2(-n.y, n.x)
	if along.dot(f) < 0.0:
		along = -along
	var to_wall := f.angle_to(along)
	if signf(dw) == signf(to_wall) and absf(dw) * ALIGN_TIME > absf(to_wall):
		dw = to_wall / ALIGN_TIME
	# a car nosed into the surface it touches is steered along it (an arcade wall: it slides off rather than grinding
	# along nose first, the tyres pulling it back in): its yaw eases towards turning that way within ALIGN_TIME
	# along it (the tyre model damps a yaw kick within a tenth of a second, so the heading itself is eased round)
	var nudge := 0.0
	if f.dot(-n) > 0.0 and absf(to_wall) < deg_to_rad(80.0):
		var want := to_wall / ALIGN_TIME
		var turn := want - (w + dw)
		if signf(turn) == signf(to_wall):
			dw += turn * clampf(ALIGN_GRIP + closing * 0.1, 0.0, 1.0) * share
		nudge = clampf(to_wall * clampf(ALIGN_GRIP + closing * 0.08, 0.0, 0.7) * share, -ALIGN_NUDGE, ALIGN_NUDGE)
	car.vx = v.x
	car.vy = v.y
	car.yaw_rate = w + dw
	car.heading += nudge
	if closing > 1.0:
		hits.append([car.x + r.x, car.y + r.y, closing])
	return closing

## One car of the train [centre, heading, half length, half width, rail height, velocity] against the car's box:
## a separating-axis test over both boxes' axes finds the shallowest way out, the car is moved out along it and
## bounced in the train's frame (so a moving train shoves it rather than acting like a wall). Hit by the front of
## a moving unit, the car is thrown aside off the track instead of being pushed along ahead of it, and the
## driver brakes (TownMap.train_hit).
func _train_push(tc: Array, mass: float) -> void:
	var h: float = tc[4]
	if z < h - 2.0 or z > h + TRAIN_TOP:
		return # under a rail bridge, or over the roof
	var tcen: Vector2 = tc[0]
	var hl: float = tc[2]
	var hw: float = tc[3]
	var c := Vector2(car.x, car.y)
	var d := c - tcen
	if d.length_squared() > (hl + HALF_L + 1.0) * (hl + HALF_L + 1.0):
		return
	var f := Vector2.from_angle(float(tc[1]))
	var r := Vector2(-f.y, f.x)
	var cf := Vector2.from_angle(car.heading)
	var cr := Vector2(-cf.y, cf.x)
	var best := INF
	var n := Vector2.ZERO
	var train_face := true
	var axes := [f, r, cf, cr]
	for i in 4:
		var ax: Vector2 = axes[i]
		var reach := hl * absf(f.dot(ax)) + hw * absf(r.dot(ax)) + HALF_L * absf(cf.dot(ax)) + HALF_W * absf(cr.dot(ax))
		var sep := d.dot(ax)
		var overlap := reach - absf(sep)
		if overlap <= 0.0:
			return # a separating axis: no contact
		# the train's own faces win a near tie (the car's axes are the same ones when it lies alongside)
		if overlap < best - (0.0 if i < 2 else 0.02):
			best = overlap
			n = ax * (1.0 if sep >= 0.0 else -1.0)
			train_face = i < 2
	# the contact: the car's corners deepest in a train face, or the train's corners deepest in the car
	var pts := PackedVector2Array()
	if train_face:
		pts = corners()
	else:
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				pts.append(tcen + f * hl * sx + r * hw * sy)
	var sgn := 1.0 if train_face else -1.0
	var deepest := INF
	for q in pts:
		deepest = minf(deepest, (q - c).dot(n) * sgn)
	var at := Vector2.ZERO
	var count := 0
	for q in pts:
		if (q - c).dot(n) * sgn < deepest + 0.05:
			at += q
			count += 1
	at /= float(count)
	var rr := at - c
	if not train_face:
		var lr := rr.rotated(-car.heading)
		rr = Vector2(clampf(lr.x, -HALF_L, HALF_L), clampf(lr.y, -HALF_W, HALF_W)).rotated(car.heading)
	car.x += n.x * (best + 0.01)
	car.y += n.y * (best + 0.01)
	var tv: Vector2 = tc[5] if tc.size() > 5 else Vector2.ZERO
	car.vx -= tv.x
	car.vy -= tv.y
	var hit := phys.barrier_hit(car, -n.x, -n.y, rr.x, rr.y, mass)
	var tspeed := tv.length()
	if tspeed > 1.0 and n.dot(tv) > 0.7 * tspeed:
		# the cab's front: fling the car off the line to the side it is already on, and spin it
		var side := signf(d.dot(r)) if absf(d.dot(r)) > 0.05 else (1.0 if (cf.dot(r)) >= 0.0 else -1.0)
		var throw := minf(tspeed, 8.0) * (0.55 if hit > 1.0 else 0.004) # a knock, or a steady shove (per 1/120 s tick)
		car.vx += r.x * side * throw
		car.vy += r.y * side * throw
		if hit > 1.0:
			car.yaw_rate += side * signf(cf.dot(f)) * clampf(hit * 0.12, 0.0, 2.5)
		map.train_hit = maxf(map.train_hit, hit)
	car.vx += tv.x
	car.vy += tv.y
	if hit > 1.0:
		hits.append([car.x + rr.x, car.y + rr.y, hit])

## A push from another car (traffic, a street rival): its outward normal (towards this car), how far to move out, the
## contact point from the centre, its mass and its velocity. The knock is taken in the other car's frame (rear-ending
## a car doing 50 at 55 is a 5 km/h tap, not a 55 km/h wall) and this car only loses its share of the closing speed
## (the other one is shoved too). Returns the closing speed.
func bump(n_out: Vector2, depth: float, r: Vector2, other_mass: float, other_v := Vector2.ZERO) -> float:
	car.x += n_out.x * depth
	car.y += n_out.y * depth
	var mass := model.mass_with_fuel(car.fuel)
	if monster:
		other_mass *= CarMods.MONSTER_SHRUG
	car.vx -= other_v.x
	car.vy -= other_v.y
	var v := _impact(n_out, r, other_mass / (mass + other_mass))
	car.vx += other_v.x
	car.vy += other_v.y
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
