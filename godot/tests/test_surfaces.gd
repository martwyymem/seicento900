## Surface handling (TASKS.md Phase 2, backlog 1): tarmac, wet tarmac, dirt, gravel and grass must drive
## differently, and a loose road must never be quicker than tarmac. Measured on the stock Seicento in the race
## physics (Physics.step with a fixed Env.surface) and in the open-world FreeCar (on a flat, empty TownMap).
## SURF_GRAVEL is the gravel trap (a run-off that stops cars); the loose roads are SURF_DIRT (the open world's
## unpaved roads) and SURF_GRAVEL_ROAD (OSM gravel roads, gravel rally stages). The figures in a table:
## godot --headless --path godot -s tests/_surface_probe.gd
extends RefCounted

var completed := false

const DT := 1.0 / 120.0
const V100 := 100.0 / 3.6
const SKID_V := 15.0 ## m/s held round the skidpad at full steering input
const FUEL := 30.0

## The race's physics on its own: one car, a surface that is the same everywhere, the race's auto gearbox.
class PhysRig:
	var model: CarModel
	var phys: Physics
	var env := Physics.Env.new()
	var ctl := Physics.Controls.new()
	var car: RaceCar
	var surf := 0

	func _init(surface_id: int, mu: float) -> void:
		model = CarModel.new()
		phys = Physics.new(model)
		surf = surface_id
		env.mu = mu
		env.mass = model.mass_with_fuel(FUEL)
		env.abs_on = true
		env.tc_on = false
		env.esc_on = false
		env.drift_assist = Race.DRIFT_ASSIST_ABS
		env.surface = func(_x: float, _y: float) -> int: return surf

	func reset(v0: float) -> void:
		car = RaceCar.new()
		car.model = model
		car.physics = phys
		car.fuel = FUEL
		car.heading = 0.0
		car.vx = v0
		car.rpm = model.spec.idle_rpm
		car.gear = 0
		for k in 6:
			_auto_shift(v0, 0.0)
			car.shift_t = 0.0
			car.hold_t = 0.0
		car.phys = null

	func step(thr: float, brk: float, steer: float) -> void:
		var vF := car.vx * cos(car.heading) + car.vy * sin(car.heading)
		_auto_shift(vF, brk)
		ctl.throttle = thr
		ctl.brake = brk
		ctl.steer = steer
		phys.step(car, ctl, env, DT)
		car.shift_t = maxf(0.0, car.shift_t - DT)
		car.hold_t = maxf(0.0, car.hold_t - DT)

	func speed() -> float:
		return sqrt(car.vx * car.vx + car.vy * car.vy)

	## FreeCar._auto_shift (= Race.auto_shift for the player's auto box).
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

## A flat, empty open world: one endless road whose physics surface is forced (or no road at all for grass).
class FlatTown extends TownMap:
	var force_surf := 0 ## Physics SURF_* id handed to FreeCar by surface_of

	func ground(_x: float, _y: float) -> float:
		return 0.0
	func terrain(_x: float, _y: float) -> float:
		return 0.0
	func road_at(_x: float, _y: float, _z_ref := -INF, _reach := 0.0) -> Dictionary:
		return {"road": 0, "i": 0, "t": 0.0, "dist": 0.0, "half": 50.0, "deck": 0.0, "surface": 0, "height": 0.0}
	func surface_of(hit: Dictionary) -> int:
		return Physics.SURF_GRASS if hit.is_empty() else force_surf
	func decks_at(_x: float, _y: float, _reach: float) -> Array:
		return []
	func water_at(_p: Vector2) -> float:
		return NAN
	func edge_push(_p: Vector2) -> Vector2:
		return Vector2.ZERO
	func buildings_near(_p: Vector2, _r: float) -> PackedInt32Array:
		return PackedInt32Array()
	func posts_near(_p: Vector2, _r: float) -> PackedVector3Array:
		return PackedVector3Array()
	func walls_near(_p: Vector2, _r: float) -> Array[PackedFloat32Array]:
		return []
	func parapets_near(_p: Vector2, _r: float) -> Array[PackedFloat32Array]:
		return []
	func piers_near(_p: Vector2, _r: float) -> Array[Vector4]:
		return []

## The open-world car on the flat town.
class FreeRig:
	var town: FlatTown
	var fc: FreeCar
	var car: RaceCar

	func _init(surface_id: int, mu: float) -> void:
		town = FlatTown.new()
		town.force_surf = surface_id
		fc = FreeCar.new(town)
		fc.mu = mu
		fc.assists = "abs"

	func reset(v0: float) -> void:
		fc.place(Vector2.ZERO, 0.0)
		car = fc.car
		car.vx = v0
		for k in 6:
			fc._auto_shift(v0, 0.0)
			car.shift_t = 0.0
			car.hold_t = 0.0
		car.phys = null

	func step(thr: float, brk: float, steer: float) -> void:
		fc.step(DT, thr, brk, steer)

	func speed() -> float:
		return sqrt(car.vx * car.vx + car.vy * car.vy)

## Every figure for one rig: t100 (s, INF if never), v30 (km/h after 30 s flat out), brake (m from 100 km/h),
## coast (km/h left after 5 s off the pedals from 100), lat_g (steady g round the skidpad at full lock input).
static func measure(rig) -> Dictionary:
	var out := {}
	rig.reset(0.0)
	var t := 0.0
	var t100 := INF
	while t < 30.0 - 1e-9:
		rig.step(1.0, 0.0, 0.0)
		t += DT
		if t100 == INF and rig.speed() >= V100:
			t100 = t
	out.t100 = t100
	out.v30 = rig.speed() * 3.6
	rig.reset(V100)
	var dist := 0.0
	t = 0.0
	while rig.speed() > 0.3 and t < 30.0:
		rig.step(0.0, 1.0, 0.0)
		dist += rig.speed() * DT
		t += DT
	out.brake = dist
	rig.reset(V100)
	for k in int(5.0 / DT):
		rig.step(0.0, 0.0, 0.0)
	out.coast = rig.speed() * 3.6
	rig.reset(SKID_V)
	var ay := 0.0
	var n := 0
	t = 0.0
	while t < 10.0:
		var v: float = rig.speed()
		var err := SKID_V - v
		rig.step(clampf(0.2 + err * 0.6, 0.0, 1.0), clampf(-err * 0.3, 0.0, 1.0), 1.0)
		t += DT
		if t > 6.0:
			ay += absf(rig.car.yaw_rate) * rig.speed()
			n += 1
	out.lat_g = ay / n / Physics.G
	out.skid_v = rig.speed() * 3.6
	return out

## Lower is quicker: time to 100, or past 30 s by how far short of 100 it ended.
static func accel_score(m: Dictionary) -> float:
	return m.t100 if m.t100 < INF else 30.0 + (100.0 - m.v30)

static func surf_ids() -> Dictionary:
	var c: Dictionary = (Physics as Script).get_script_constant_map()
	return {"tarmac": c.SURF_TRACK, "asphalt": c.SURF_ASPHALT, "dirt": c.SURF_DIRT, "gravel": c.SURF_GRAVEL_ROAD,
		"grass": c.SURF_GRASS, "gravel_trap": c.SURF_GRAVEL}

## A Race on a rally stage of the given surface, disposed by the caller.
static func rally_race(surface: String) -> Race:
	LapRecords.use_disk = false
	var st := RaceSettings.new()
	Rally.configure_stage(st, {"track": "fiat", "from": 0.0, "to": 0.0, "surface": surface, "weather": "dry", "hour": 12.0})
	return Race.new(st, null, 3)

var errors := []

func check(what: String, ok: bool) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	# ---- parity guard: the four existing surfaces keep their ids and figures (the parity tests depend on them)
	check("SURF_TRACK/ASPHALT/GRASS/GRAVEL stay 0/1/2/3", Physics.SURF_TRACK == 0 and Physics.SURF_ASPHALT == 1
		and Physics.SURF_GRASS == 2 and Physics.SURF_GRAVEL == 3)
	var grip0 := [1.0, 0.9, 0.5, 0.42]
	var drag0 := [0.0, 0.004, 0.07, 0.22]
	for i in 4:
		check("SURF_GRIP[%d] stays %s" % [i, grip0[i]], Physics.SURF_GRIP[i] == grip0[i])
		check("SURF_DRAG[%d] stays %s" % [i, drag0[i]], Physics.SURF_DRAG[i] == drag0[i])

	# ---- the loose roads: new ids with every table entry, and the open world's unpaved roads on them
	var ids := surf_ids()
	for k in ["dirt", "gravel"]:
		check("SURF %s is a new id (>= 4) with SURF_GRIP/SURF_DRAG/SURF_STEER entries" % k, ids[k] >= 4
			and Physics.SURF_GRIP.size() > ids[k] and Physics.SURF_DRAG.size() > ids[k] and Physics.SURF_STEER.size() > ids[k])
		check("a %s road gives the driver more lock than tarmac (SURF_STEER > 1)" % k, Physics.SURF_STEER[ids[k]] > 1.0)
	for i in 4:
		check("SURF_STEER[%d] stays 1 (parity)" % i, Physics.SURF_STEER[i] == 1.0)
	var tm := TownMap.new()
	var unpaved := tm.surface_of({"dist": 0.0, "half": 3.0, "surface": 2})
	check("the open world's unpaved roads (baked surface 2) drive as SURF_DIRT, got %d" % unpaved, unpaved == ids.dirt)
	var loose_road := tm.surface_of({"dist": 0.0, "half": 3.0, "surface": 2, "gravel": 1})
	check("an unpaved road baked as gravel (g 1) drives as SURF_GRAVEL_ROAD, got %d" % loose_road, loose_road == ids.gravel)
	check("Rally.SURFACE_GRIP.gravel is the gravel road's SURF_GRIP", Rally.SURFACE_GRIP.gravel == Physics.SURF_GRIP[ids.gravel])
	check("Rally.SURFACE_GRIP.dirt is the dirt road's SURF_GRIP", Rally.SURFACE_GRIP.dirt == Physics.SURF_GRIP[ids.dirt])

	# ---- the ordering, in the race physics and in the open-world car
	for rig_name in ["physics", "freecar"]:
		var m := {}
		for sname in ids:
			m[sname] = measure(PhysRig.new(ids[sname], 1.0) if rig_name == "physics" else FreeRig.new(ids[sname], 1.0))
		var wet: Dictionary = measure(PhysRig.new(ids.tarmac, 0.7) if rig_name == "physics" else FreeRig.new(ids.tarmac, 0.7))
		var tag := "[%s] " % rig_name
		for loose in ["dirt", "gravel"]:
			check(tag + "tarmac reaches 100 km/h at least 5%% sooner than %s (%.2f vs %.2f)" % [loose, accel_score(m.tarmac), accel_score(m[loose])],
				accel_score(m.tarmac) * 1.05 < accel_score(m[loose]))
			check(tag + "tarmac is quicker after 30 s than %s (%.1f vs %.1f km/h)" % [loose, m.tarmac.v30, m[loose].v30],
				m.tarmac.v30 > m[loose].v30 + 0.5)
			check(tag + "tarmac stops shorter from 100 than %s (%.1f vs %.1f m)" % [loose, m.tarmac.brake, m[loose].brake],
				m.tarmac.brake < m[loose].brake)
			check(tag + "tarmac holds more lateral g than %s (%.2f vs %.2f)" % [loose, m.tarmac.lat_g, m[loose].lat_g],
				m.tarmac.lat_g > m[loose].lat_g)
			check(tag + "wet tarmac still beats %s to 100 or matches it" % loose, accel_score(wet) <= accel_score(m[loose]) + 0.05)
		check(tag + "a dirt road is still a road: 95-110 km/h after 30 s (%.1f)" % m.dirt.v30, m.dirt.v30 >= 95.0 and m.dirt.v30 <= 110.0)
		check(tag + "a gravel road is still a road: 85-105 km/h after 30 s (%.1f)" % m.gravel.v30, m.gravel.v30 >= 85.0 and m.gravel.v30 <= 105.0)
		check(tag + "dirt reaches 100 sooner than gravel", accel_score(m.dirt) < accel_score(m.gravel))
		check(tag + "dirt stops shorter than gravel", m.dirt.brake < m.gravel.brake)
		check(tag + "dirt holds more lateral g than gravel", m.dirt.lat_g > m.gravel.lat_g)
		check(tag + "dirt slows a coasting car less than gravel", m.dirt.coast > m.gravel.coast)
		check(tag + "the gravel trap stops cars: under 40 km/h after 30 s (%.1f)" % m.gravel_trap.v30, m.gravel_trap.v30 < 40.0)
		check(tag + "gravel reaches 100 sooner than grass (%.2f vs %.2f)" % [accel_score(m.gravel), accel_score(m.grass)],
			accel_score(m.gravel) < accel_score(m.grass))
		check(tag + "gravel holds more lateral g than grass (%.2f vs %.2f)" % [m.gravel.lat_g, m.grass.lat_g],
			m.gravel.lat_g > m.grass.lat_g)
		check(tag + "gravel stops shorter than grass (%.1f vs %.1f m)" % [m.gravel.brake, m.grass.brake], m.gravel.brake < m.grass.brake)
		check(tag + "wet tarmac stops longer than dry (%.1f vs %.1f m)" % [wet.brake, m.tarmac.brake], wet.brake > m.tarmac.brake * 1.1)
		check(tag + "wet tarmac holds less lateral g than dry (%.2f vs %.2f)" % [wet.lat_g, m.tarmac.lat_g], wet.lat_g < m.tarmac.lat_g)

	# ---- a gravel rally stage is a loose surface under the wheels, not grippier-less tarmac
	var tr := rally_race("tarmac")
	var gr := rally_race("gravel")
	gr.player.tyre = tr.player.tyre.duplicate()
	var p := gr.player
	var s_on := gr.surface_at(p, p.x, p.y)
	check("a gravel rally stage's road is SURF_GRAVEL_ROAD (got SURF id %d)" % s_on, s_on == Physics.SURF_GRAVEL_ROAD)
	check("a tarmac rally stage's road is SURF_TRACK", tr.surface_at(tr.player, tr.player.x, tr.player.y) == Physics.SURF_TRACK)
	var g_t := tr.grip(tr.player)
	var g_g := gr.grip(gr.player)
	check("the gravel isn't counted twice: the tyres' grip is the same on both stages (%.3f vs %.3f)" % [g_g, g_t], g_g == g_t)
	var mt := measure(PhysRig.new(tr.surface_at(tr.player, tr.player.x, tr.player.y), g_t))
	var mg := measure(PhysRig.new(s_on, g_g))
	check("a gravel rally stage is slower to 100 than tarmac (%.2f vs %.2f s)" % [accel_score(mg), accel_score(mt)],
		accel_score(mg) > accel_score(mt) + 0.1)
	check("a gravel rally stage costs speed after 30 s (%.1f vs %.1f km/h)" % [mg.v30, mt.v30], mg.v30 < mt.v30 - 0.5)
	check("a gravel rally stage slows a coasting car more than tarmac (%.1f vs %.1f km/h)" % [mg.coast, mt.coast], mg.coast < mt.coast - 0.5)
	check("a gravel rally stage stops longer than tarmac (%.1f vs %.1f m)" % [mg.brake, mt.brake], mg.brake > mt.brake)
	tr.dispose()
	gr.dispose()

	completed = true
	return errors
